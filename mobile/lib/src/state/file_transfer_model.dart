import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/crc32.dart';
import '../services/file_util.dart';
import 'sync_connection.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

const int _chunkSize = 65536;

/// Mirrors the daemon's `MAX_CHUNK_RESEND_ATTEMPTS`
/// (daemon/src/transfer/mod.rs) -- how many times a single corrupted
/// offset may be re-requested (T-306) before the receiver gives up and
/// fails the whole transfer, so a systematically broken link can't
/// loop forever.
const int _maxChunkResendAttempts = 3;

/// Owns file transfer send/receive/resume (T-204). Depends only on the
/// narrow [SyncConnection] interface (send frames, connectivity, active
/// peer id for resumable transfer ids) rather than on [PairingModel]
/// concretely.
class FileTransferModel extends ChangeNotifier {
  FileTransferModel({required SyncConnection connection})
      : _connection = connection;

  final SyncConnection _connection;

  Map<String, TransferProgress> transfers = {};

  // --- outgoing ----------------------------------------------------------

  /// Transfer ids the user asked to cancel mid-send; the streaming send
  /// loop checks this and stops early.
  final Set<String> _canceledOutgoing = {};

  /// Local file path + size for every outgoing transfer currently
  /// in-flight, keyed by transfer_id, so [handleFileChunkRequest] (T-306)
  /// can reopen the file and resend one specific chunk without needing
  /// its own handle into the streaming loop's local `raf`. Populated at
  /// the start of [sendFile], removed when it finishes/fails/cancels.
  final Map<String, _OutgoingSend> _activeSends = {};

  // --- incoming ------------------------------------------------------------

  final Map<String, _IncomingTransfer> _incoming = {};

  /// On-disk path of each completed, hash-verified incoming file, keyed
  /// by transfer_id. Received files land in an app-private directory the
  /// user's file manager can't browse, so the UI offers a "Save to..."
  /// action (Android's system document picker) that copies the bytes to
  /// a user-chosen location; this map is how that action finds the file.
  final Map<String, String> _incomingFinalPaths = {};

  /// The saved on-disk path of a completed incoming transfer, or null if
  /// it never completed (or was a send). Used by the transfers screen's
  /// "Save to..." action.
  String? incomingFilePath(String transferId) => _incomingFinalPaths[transferId];

  /// Serializes incoming-file disk writes in frame-arrival order (the
  /// inbound stream callback is sync, so async I/O must be chained).
  Future<void> _ioChain = Future<void>.value();

  /// Lets tests deterministically wait for every `handleFileTransferStart`/
  /// `handleFileChunk` call queued so far to finish its disk I/O, instead
  /// of guessing with `pumpEventQueue()` -- which pumps a fixed number of
  /// microtask turns and is not guaranteed to outlast real (if small) file
  /// I/O latency, especially across the two chained operations a single
  /// incoming chunk triggers.
  @visibleForTesting
  Future<void> get pendingIoForTests => _ioChain;

  /// Requests that an in-flight outgoing transfer stop. The streaming
  /// send loop notices on its next chunk and marks the transfer failed.
  void cancelTransfer(String transferId) {
    if (transfers[transferId]?.direction != TransferDirection.outgoing) return;
    _canceledOutgoing.add(transferId);
  }

  void _emitOutgoing(String id, String name, int sent, int total,
      {bool completed = false, bool failed = false, bool canceled = false}) {
    transfers = {
      ...transfers,
      id: TransferProgress(
        transferId: id,
        fileName: name,
        bytesTransferred: sent,
        totalBytes: total,
        direction: TransferDirection.outgoing,
        completed: completed,
        failed: failed,
        canceled: canceled,
      ),
    };
    notifyListeners();
  }

  /// Sends a file to the active peer over the dedicated PrepareUpload +
  /// UploadFile RPCs (TASKS.md Phase A) -- bytes stream one-way on their
  /// own client-streaming RPC, not chunk-framed onto the SyncStream, so a
  /// control-stream reconnect can't kill the transfer and HTTP/2 flow
  /// control is the backpressure. Resume offset comes from the receiver's
  /// PrepareUpload answer, not local bookkeeping.
  Future<void> sendFile(String path) async {
    final client = _connection.uploadClient;
    if (client == null) return; // no outgoing session to a peer
    final file = File(path);
    final size = await file.length();
    final name = path.split(Platform.pathSeparator).last;
    final mtime = await file.lastModified();
    // Deterministic (not random) so retrying the *same* file to the
    // *same* peer after a dropped connection reuses the file_id the
    // receiver keyed its partial under, which is what makes resume work.
    final fileId = _deterministicTransferId(path, size, mtime);
    // Streaming whole-file SHA-256 (constant memory) declared up front.
    final fileHash = await _hashFile(file);
    _emitOutgoing(fileId, name, 0, size);

    // Step 1: PrepareUpload -- declare the file, learn accept + resume.
    pb.PrepareUploadResponse prep;
    try {
      prep = await client.prepareUpload(pb.PrepareUploadRequest(
        sender: _connection.localIdentity,
        sessionId: fileId,
        files: [
          pb.UploadFileMeta(
            fileId: fileId,
            fileName: name,
            fileSizeBytes: Int64(size),
            fileHash: fileHash,
            mimeType: 'application/octet-stream',
          ),
        ],
      ));
    } catch (e) {
      debugPrint('prepareUpload failed for $fileId: $e');
      _emitOutgoing(fileId, name, 0, size, failed: true);
      return;
    }

    final offer = prep.offers.firstWhere(
      (o) => o.fileId == fileId,
      orElse: () => pb.UploadFileOffer(accepted: false),
    );
    if (!offer.accepted) {
      _emitOutgoing(fileId, name, 0, size, failed: true);
      return;
    }
    final resume = offer.resumeOffsetBytes.toInt().clamp(0, size).toInt();
    _emitOutgoing(fileId, name, resume, size);

    // Step 2: UploadFile -- header, then raw bytes from the resume offset.
    Stream<pb.UploadFilePart> body() async* {
      yield pb.UploadFilePart(
        header: pb.UploadFileHeader(
          sessionId: prep.sessionId,
          fileId: fileId,
          token: offer.token,
          offsetBytes: Int64(resume),
        ),
      );
      final raf = await file.open(mode: FileMode.read);
      try {
        if (resume > 0) await raf.setPosition(resume);
        var sent = resume;
        while (sent < size) {
          if (_canceledOutgoing.contains(fileId)) break;
          final chunk = await raf.read(_chunkSize);
          if (chunk.isEmpty) break;
          yield pb.UploadFilePart(chunk: chunk);
          sent += chunk.length;
          _emitOutgoing(fileId, name, sent, size);
          // Yield so the UI can paint progress between chunks.
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        await raf.close();
      }
    }

    try {
      final result = await client.uploadFile(body());
      if (result.completed && result.hashOk) {
        _emitOutgoing(fileId, name, size, size, completed: true);
      } else if (_canceledOutgoing.contains(fileId)) {
        _emitOutgoing(fileId, name, result.bytesReceived.toInt(), size,
            failed: true, canceled: true);
      } else {
        _emitOutgoing(fileId, name, result.bytesReceived.toInt(), size,
            failed: true);
      }
    } catch (e) {
      debugPrint('uploadFile failed for $fileId: $e');
      _emitOutgoing(fileId, name, resume, size, failed: true);
    } finally {
      _canceledOutgoing.remove(fileId);
    }
  }

  /// Called by [PairingModel] when an inbound `SyncFrame` carries a
  /// `FileChunkRequest` (T-306): the peer's CRC32 check failed on one
  /// chunk of a transfer this device is sending, so it wants just that
  /// offset resent rather than the whole transfer restarted. Only
  /// meaningful while [sendFile] for this transfer_id is still running
  /// (or, for a transfer that already finished sending every chunk, if
  /// the request arrives before [_activeSends] was cleared -- see
  /// `sendFile`'s `finally`); an unknown transfer_id is silently
  /// ignored, mirroring the daemon's `note_corrupt_chunk` returning
  /// `false` for a transfer it no longer knows about.
  Future<void> handleFileChunkRequest(pb.FileChunkRequest request) async {
    final send = _activeSends[request.transferId];
    if (send == null) return;
    final offset = request.offsetBytes.toInt();
    try {
      final raf = await File(send.path).open(mode: FileMode.read);
      try {
        await raf.setPosition(offset);
        final chunk = await raf.read(_chunkSize);
        if (chunk.isEmpty) return;
        final isLast = offset + chunk.length >= send.totalBytes;
        _connection.sendFrame(pb.SyncFrame(
          fileChunk: pb.FileChunk(
            transferId: request.transferId,
            offsetBytes: Int64(offset),
            data: chunk,
            isLast: isLast,
            chunkChecksum: Crc32.compute(chunk),
          ),
        ));
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('chunk resend failed for ${request.transferId}@$offset: $e');
    }
  }

  /// Stable id for a (peer, file) pair so a retried send after a
  /// dropped connection reuses the transfer_id the receiver's partial
  /// file is keyed under, enabling resume. Not security-sensitive
  /// (worst case of a collision is caught by the existing whole-file
  /// SHA-256 verification on the receiving side), so this only needs
  /// to be *stable*, not cryptographically strong.
  String _deterministicTransferId(String path, int size, DateTime mtime) {
    final peerKey = _connection.activePeerId ?? '';
    final raw = '$peerKey|$path|$size|${mtime.millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  /// Streaming SHA-256 of a file (constant memory).
  Future<String> _hashFile(File file) async {
    Digest? digest;
    final input = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback(
          (digests) => digest = digests.single),
    );
    final raf = await file.open(mode: FileMode.read);
    try {
      while (true) {
        final block = await raf.read(_chunkSize);
        if (block.isEmpty) break;
        input.add(block);
      }
    } finally {
      await raf.close();
    }
    input.close();
    return digest!.toString();
  }

  // --- incoming file transfers ---------------------------------------------

  /// Called by [PairingModel] when an inbound `SyncFrame` carries a
  /// `FileTransferStart`.
  void handleFileTransferStart(pb.FileTransferStart start) {
    _enqueueIo(() => _beginIncoming(start));
  }

  /// Called by [PairingModel] when an inbound `SyncFrame` carries a
  /// `FileChunk`.
  void handleFileChunk(pb.FileChunk chunk) {
    _enqueueIo(() => _writeIncoming(chunk));
  }

  void _enqueueIo(Future<void> Function() op) {
    _ioChain = _ioChain.then((_) => op()).catchError((Object e) {
      debugPrint('incoming file io error: $e');
    });
  }

  Future<void> _beginIncoming(pb.FileTransferStart start) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/received');
    await dir.create(recursive: true);
    // Written to a transfer_id-keyed partial path, not the peer-supplied
    // file name directly -- two concurrent/sequential incoming transfers
    // sharing a file name must not overwrite each other's bytes (T-108).
    // The collision-safe user-visible name is only assigned once the
    // transfer completes and is hash-verified, in _writeIncoming.
    final file = File('${dir.path}/${partialFileName(start.transferId)}');
    // FileMode.append (not .write) so a resumed transfer_id (T-025)
    // keeps whatever bytes are already on disk from a prior, dropped
    // attempt instead of truncating them away -- re-sent chunks at
    // earlier offsets are safe no-op overwrites via setPosition() in
    // _writeIncoming, not data loss. Mirrors the daemon's
    // TransferManager::begin (daemon/src/transfer/mod.rs).
    final raf = await file.open(mode: FileMode.append);
    final resumeOffset = start.resumeOffsetBytes
        .toInt()
        .clamp(0, start.fileSizeBytes.toInt())
        .toInt();
    _incoming[start.transferId] = _IncomingTransfer(
      transferId: start.transferId,
      fileName: start.fileName,
      path: file.path,
      totalBytes: start.fileSizeBytes.toInt(),
      fileHash: start.fileHash,
      raf: raf,
    )..received = resumeOffset;
    _emitIncoming(start.transferId, resumeOffset);
  }

  Future<void> _writeIncoming(pb.FileChunk chunk) async {
    final t = _incoming[chunk.transferId];
    if (t == null) return;
    final offset = chunk.offsetBytes.toInt();
    // Reject a corrupted chunk up front (cheap CRC32) before writing it.
    // Rather than failing the whole transfer immediately (T-306), ask
    // the sender to resend just this offset, up to
    // _maxChunkResendAttempts times per offset -- mirrors the daemon's
    // TransferManager::note_corrupt_chunk.
    if (Crc32.compute(chunk.data) != chunk.chunkChecksum) {
      final attempts = (t.corruptAttempts[offset] ?? 0) + 1;
      t.corruptAttempts[offset] = attempts;
      if (attempts > _maxChunkResendAttempts) {
        await _failIncoming(t);
        return;
      }
      t.pendingResendOffsets.add(offset);
      _connection.sendFrame(pb.SyncFrame(
        fileChunkRequest: pb.FileChunkRequest(
          transferId: chunk.transferId,
          offsetBytes: chunk.offsetBytes,
        ),
      ));
      return;
    }
    await t.raf.setPosition(offset);
    await t.raf.writeFrom(chunk.data);
    // High-water mark, not last-write-wins (T-306): a resend can arrive
    // *after* a later chunk was already written (e.g. the last chunk's
    // CRC32 passes and gets written while an earlier offset is still
    // pending a fix), so a plain assignment here would regress progress
    // back down to the resent offset's end instead of reflecting how
    // much of the file is actually down. Mirrors the daemon's
    // `TransferManager::record_progress` (daemon/src/transfer/mod.rs),
    // which folds each write into `bytes_written.max(position)`.
    t.received = math.max(t.received, offset + chunk.data.length);
    // This offset (if it had previously failed CRC32 and was pending a
    // resend) is now correctly rewritten.
    t.pendingResendOffsets.remove(offset);
    if (chunk.isLast) {
      t.finalizePending = true;
    }

    if (t.finalizePending && t.pendingResendOffsets.isEmpty) {
      await t.raf.close();
      final ok = await _verifyWholeFile(t);
      if (ok) {
        await _finalizeIncoming(t);
      }
      _incoming.remove(chunk.transferId);
      _emitIncoming(t.transferId, t.received,
          completed: ok, failed: !ok, transfer: t);
    } else {
      _emitIncoming(t.transferId, t.received, transfer: t);
    }
  }

  Future<bool> _verifyWholeFile(_IncomingTransfer t) async {
    if (t.fileHash.isEmpty) return true;
    try {
      final bytes = await File(t.path).readAsBytes();
      return sha256.convert(bytes).toString() == t.fileHash;
    } catch (e) {
      debugPrint('incoming file verify failed for ${t.path}: $e');
      return false;
    }
  }

  /// Renames a completed, hash-verified transfer's partial file (written
  /// at a transfer_id-keyed path, see [_beginIncoming]) to its final,
  /// user-visible name -- disambiguated against whatever else is already
  /// in the received/ directory so it can never silently overwrite an
  /// unrelated file that happens to share a name (T-108).
  Future<void> _finalizeIncoming(_IncomingTransfer t) async {
    final partial = File(t.path);
    final dir = partial.parent;
    final existing = <String>{};
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          existing.add(entity.path.split(Platform.pathSeparator).last);
        }
      }
    } catch (e) {
      debugPrint('incoming file finalize: could not list ${dir.path}: $e');
    }
    final finalName =
        uniqueFileName(existing, safeReceivedFileName(t.fileName));
    final finalPath = '${dir.path}/$finalName';
    try {
      await partial.rename(finalPath);
      // Remembered so the UI's "Save to..." action can copy this file
      // out of the app-private received/ dir to a user-chosen location.
      _incomingFinalPaths[t.transferId] = finalPath;
    } catch (e) {
      debugPrint('incoming file finalize: rename failed for ${t.path}: $e');
    }
  }

  Future<void> _failIncoming(_IncomingTransfer t) async {
    try {
      await t.raf.close();
    } catch (e) {
      debugPrint('incoming file fail: close errored for ${t.path}: $e');
    }
    _incoming.remove(t.transferId);
    _emitIncoming(t.transferId, t.received, failed: true, transfer: t);
  }

  void _emitIncoming(
    String id,
    int received, {
    bool completed = false,
    bool failed = false,
    _IncomingTransfer? transfer,
  }) {
    final t = transfer ?? _incoming[id];
    if (t == null) return;
    transfers = {
      ...transfers,
      id: TransferProgress(
        transferId: id,
        fileName: t.fileName,
        bytesTransferred: received,
        totalBytes: t.totalBytes,
        direction: TransferDirection.incoming,
        completed: completed,
        failed: failed,
      ),
    };
    notifyListeners();
  }

  // --- dedicated upload receive (PrepareUpload + UploadFile) -------------
  // LocalSend-style path: bytes arrive on their own client-streaming RPC
  // (not the SyncStream), written straight to disk while a streaming
  // SHA-256 is folded -- never buffering the whole file in RAM (the OOM
  // fix vs `_verifyWholeFile`'s readAsBytes on the old chunk path).

  /// Live upload tickets minted by [handlePrepareUpload], keyed by token.
  final Map<String, _UploadTicket> _uploadTickets = {};

  /// Responder side of `PrepareUpload`: per file, report how many bytes we
  /// already hold (resume) and mint a token the matching `UploadFile`
  /// stream must echo. Authorization (is the sender paired?) is done one
  /// layer up, in `PairingModel`, before this is called.
  Future<pb.PrepareUploadResponse> handlePrepareUpload(
      pb.PrepareUploadRequest req) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/received');
    await dir.create(recursive: true);
    final sessionId = req.sessionId.isEmpty ? _mintToken() : req.sessionId;

    final offers = <pb.UploadFileOffer>[];
    for (final f in req.files) {
      final partPath = '${dir.path}/${partialFileName(f.fileId)}';
      final partial = File(partPath);
      final resume = await partial.exists() ? await partial.length() : 0;
      final token = _mintToken();
      _uploadTickets[token] = _UploadTicket(
        sessionId: sessionId,
        fileId: f.fileId,
        fileName: f.fileName,
        partPath: partPath,
        totalBytes: f.fileSizeBytes.toInt(),
        expectedHash: f.fileHash,
      );
      offers.add(pb.UploadFileOffer(
        fileId: f.fileId,
        accepted: true,
        resumeOffsetBytes: Int64(resume),
        token: token,
      ));
    }
    return pb.PrepareUploadResponse(sessionId: sessionId, offers: offers);
  }

  /// Responder side of `UploadFile`: the first frame is the header (token-
  /// validated against a live offer); every later frame is a raw chunk
  /// appended to the `.part` while a streaming SHA-256 is folded. Ends by
  /// finalizing (all bytes + hash match), discarding (hash mismatch), or
  /// keeping a resumable partial (stream dropped early).
  Future<pb.UploadFileResult> handleUploadFile(
      Stream<pb.UploadFilePart> parts) async {
    _UploadTicket? ticket;
    String? token;
    RandomAccessFile? raf;
    var received = 0;
    Digest? digestResult;
    ChunkedConversionSink<List<int>>? hashInput;
    final hashOut = ChunkedConversionSink<Digest>.withCallback(
        (digests) => digestResult = digests.single);
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

    await for (final part in parts) {
      if (part.hasHeader()) {
        final h = part.header;
        final t = _uploadTickets[h.token];
        if (t == null || t.fileId != h.fileId || t.sessionId != h.sessionId) {
          throw const GrpcError.permissionDenied(
              'unknown or mismatched upload token');
        }
        ticket = t;
        token = h.token;
        final offset = h.offsetBytes.toInt().clamp(0, t.totalBytes).toInt();
        hashInput = sha256.startChunkedConversion(hashOut);

        final file = File(t.partPath);
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        // Seed the digest with the bytes already on disk [0, offset),
        // read streaming so even a big resume never buffers the file.
        if (offset > 0) {
          await for (final block in file.openRead(0, offset)) {
            hashInput.add(block);
          }
        }
        raf = await file.open(mode: FileMode.append);
        await raf.truncate(offset);
        await raf.setPosition(offset);
        received = offset;
        _emitUpload(t, received, completed: false, failed: false);
      } else if (part.hasChunk()) {
        if (ticket == null || raf == null || hashInput == null) {
          throw const GrpcError.invalidArgument('chunk before header');
        }
        final data = part.chunk;
        await raf.writeFrom(data);
        hashInput.add(data);
        received += data.length;
        final now = DateTime.now();
        if (now.difference(lastEmit).inMilliseconds >= 250) {
          lastEmit = now;
          _emitUpload(ticket, received, completed: false, failed: false);
        }
      }
    }

    if (ticket == null || raf == null || hashInput == null) {
      throw const GrpcError.invalidArgument('upload stream had no header');
    }
    await raf.flush();
    await raf.close();
    hashInput.close();

    // Dropped mid-stream: keep the partial for a later resume.
    if (received < ticket.totalBytes) {
      _uploadTickets.remove(token);
      _emitUpload(ticket, received, completed: false, failed: false);
      return pb.UploadFileResult(
          fileId: ticket.fileId,
          completed: false,
          bytesReceived: Int64(received),
          hashOk: false);
    }

    final actualHash = digestResult!.toString();
    if (ticket.expectedHash.isNotEmpty && actualHash != ticket.expectedHash) {
      try {
        await File(ticket.partPath).delete();
      } catch (_) {
        // best-effort cleanup of the corrupt partial
      }
      _uploadTickets.remove(token);
      _emitUpload(ticket, received, completed: false, failed: true);
      return pb.UploadFileResult(
          fileId: ticket.fileId,
          completed: false,
          bytesReceived: Int64(received),
          hashOk: false);
    }

    final finalPath = await _finalizeUploadPart(ticket);
    _incomingFinalPaths[ticket.fileId] = finalPath;
    _uploadTickets.remove(token);
    _emitUpload(ticket, received, completed: true, failed: false);
    return pb.UploadFileResult(
        fileId: ticket.fileId,
        completed: true,
        bytesReceived: Int64(received),
        hashOk: true);
  }

  Future<String> _finalizeUploadPart(_UploadTicket t) async {
    final partial = File(t.partPath);
    final dir = partial.parent;
    final existing = <String>{};
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          existing.add(entity.path.split(Platform.pathSeparator).last);
        }
      }
    } catch (e) {
      debugPrint('upload finalize: could not list ${dir.path}: $e');
    }
    final finalName = uniqueFileName(existing, safeReceivedFileName(t.fileName));
    final finalPath = '${dir.path}/$finalName';
    await partial.rename(finalPath);
    return finalPath;
  }

  void _emitUpload(_UploadTicket t, int received,
      {required bool completed, required bool failed}) {
    transfers = {
      ...transfers,
      t.fileId: TransferProgress(
        transferId: t.fileId,
        fileName: t.fileName,
        bytesTransferred: received,
        totalBytes: t.totalBytes,
        direction: TransferDirection.incoming,
        completed: completed,
        failed: failed,
      ),
    };
    notifyListeners();
  }

  String _mintToken() {
    final rng = math.Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void dispose() {
    for (final t in _incoming.values) {
      unawaited(t.raf.close());
    }
    super.dispose();
  }
}

/// A live, accepted upload offer between `PrepareUpload` and the matching
/// `UploadFile` stream (mobile receiver).
class _UploadTicket {
  _UploadTicket({
    required this.sessionId,
    required this.fileId,
    required this.fileName,
    required this.partPath,
    required this.totalBytes,
    required this.expectedHash,
  });

  final String sessionId;
  final String fileId;
  final String fileName;
  final String partPath;
  final int totalBytes;
  final String expectedHash;
}

/// In-progress receive of a file pushed from a paired device. Writes go
/// straight to disk (via [raf]) so large files never have to be buffered
/// in memory.
class _IncomingTransfer {
  _IncomingTransfer({
    required this.transferId,
    required this.fileName,
    required this.path,
    required this.totalBytes,
    required this.fileHash,
    required this.raf,
  });

  final String transferId;
  final String fileName;
  final String path;
  final int totalBytes;
  final String fileHash;
  final RandomAccessFile raf;
  int received = 0;

  /// Offsets that failed CRC32 and have a `FileChunkRequest` resend
  /// in flight (T-306). Finalizing on a bare `isLast` flag while this
  /// is non-empty would race a still-corrupt byte range still being
  /// fixed up, so [FileTransferModel._writeIncoming] gates finalize on
  /// this being empty too -- mirrors the daemon's
  /// `TransferMeta::pending_resend_offsets`.
  final Set<int> pendingResendOffsets = {};

  /// How many times a resend has been requested for each offset that
  /// has ever failed CRC32, bounded by [_maxChunkResendAttempts].
  final Map<int, int> corruptAttempts = {};

  /// Set once the `isLast` chunk has been seen; finalize only happens
  /// once this is true *and* [pendingResendOffsets] is empty.
  bool finalizePending = false;
}

/// Local source for an outgoing transfer still in flight, kept around
/// so [FileTransferModel.handleFileChunkRequest] (T-306) can reopen the
/// file and resend one specific chunk on demand.
class _OutgoingSend {
  _OutgoingSend({required this.path, required this.totalBytes});

  final String path;
  final int totalBytes;
}
