import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/file_util.dart';
import 'sync_connection.dart';
import '../generated/connectible.pbgrpc.dart' as pb;

const int _chunkSize = 65536;

/// Owns file transfer send/receive/resume (T-204). Depends only on the
/// narrow [SyncConnection] interface (send frames, connectivity, active
/// peer id for resumable transfer ids) rather than on [PairingModel]
/// concretely.
class FileTransferModel extends ChangeNotifier {
  FileTransferModel({required SyncConnection connection, required SharedPreferences prefs})
      : _connection = connection,
        _prefs = prefs {
    _loadHistory();
  }

  final SyncConnection _connection;
  final SharedPreferences _prefs;

  Map<String, TransferProgress> transfers = {};

  // --- persisted history (Phase J) ----------------------------------------
  // Mobile has no separate daemon process, so (unlike desktop) this model
  // persists its own history directly, mirroring DeviceListModel's
  // shared_preferences JSON-blob pattern rather than going through an RPC.

  static const _historyPrefsKey = 'connectible.transfer_history';
  /// Mirrors the daemon's own MAX_ROWS cap (Phase J, `db/history.rs`),
  /// chosen smaller since a phone's storage/UI surface is more
  /// constrained than desktop's.
  static const _historyCap = 200;

  List<TransferHistoryEntry> _history = const [];

  /// Persisted history, most recent first (both directions). Read-only
  /// view for `transfers_screen.dart`.
  List<TransferHistoryEntry> get history => _history;

  void _loadHistory() {
    final raw = _prefs.getString(_historyPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _history = list
          .map((m) => TransferHistoryEntry(
                transferId: m['transferId'] as String,
                peerDeviceId: m['peerDeviceId'] as String? ?? '',
                fileName: m['fileName'] as String,
                totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
                direction: m['direction'] == 'outgoing'
                    ? TransferDirection.outgoing
                    : TransferDirection.incoming,
                status: m['status'] as String? ?? 'completed',
                startedAtMs: (m['startedAtMs'] as num?)?.toInt() ?? 0,
                finishedAtMs: (m['finishedAtMs'] as num?)?.toInt() ?? 0,
                // Optional key (T-X5): blobs written before it existed
                // simply load with no saved path.
                localPath: m['localPath'] as String? ?? '',
              ))
          .toList(growable: false);
    } catch (e) {
      debugPrint('transfer history parse failed: $e');
      _history = const [];
    }
  }

  void _saveHistory() {
    final json = jsonEncode(_history
        .map((h) => {
              'transferId': h.transferId,
              'peerDeviceId': h.peerDeviceId,
              'fileName': h.fileName,
              'totalBytes': h.totalBytes,
              'direction': h.direction == TransferDirection.outgoing ? 'outgoing' : 'incoming',
              'status': h.status,
              'startedAtMs': h.startedAtMs,
              'finishedAtMs': h.finishedAtMs,
              'localPath': h.localPath,
            })
        .toList(growable: false));
    _prefs.setString(_historyPrefsKey, json);
  }

  /// Records one terminal transfer outcome, most-recent-first, capped at
  /// [_historyCap] entries (T-J3's retention-cap counterpart on mobile).
  void _recordHistory({
    required String transferId,
    required String fileName,
    required int totalBytes,
    required TransferDirection direction,
    required String status,
    required int startedAtMs,
    String localPath = '',
  }) {
    final entry = TransferHistoryEntry(
      transferId: transferId,
      peerDeviceId: _connection.activePeerId ?? '',
      fileName: fileName,
      totalBytes: totalBytes,
      direction: direction,
      status: status,
      startedAtMs: startedAtMs,
      finishedAtMs: DateTime.now().millisecondsSinceEpoch,
      localPath: localPath,
    );
    _history = [entry, ..._history].take(_historyCap).toList(growable: false);
    _saveHistory();
  }

  // --- outgoing ----------------------------------------------------------

  /// Transfer ids the user asked to cancel mid-send; the streaming send
  /// loop checks this and stops early.
  final Set<String> _canceledOutgoing = {};

  // --- incoming ------------------------------------------------------------

  /// On-disk path of each completed, hash-verified incoming file, keyed
  /// by transfer_id. Received files land in an app-private directory the
  /// user's file manager can't browse, so the UI offers a "Save to..."
  /// action (Android's system document picker) that copies the bytes to
  /// a user-chosen location; this map is how that action finds the file.
  final Map<String, String> _incomingFinalPaths = {};

  /// The saved on-disk path of a completed incoming transfer, or null if
  /// it never completed (or was a send). Used by the transfers screen's
  /// "Save to..." action. Falls back to the persisted history entry's
  /// [TransferHistoryEntry.localPath] (T-X5) so a file received before
  /// the last app restart is still reachable; the caller keeps its
  /// exists-on-disk check for genuinely deleted files.
  String? incomingFilePath(String transferId) {
    final live = _incomingFinalPaths[transferId];
    if (live != null) return live;
    for (final h in _history) {
      if (h.transferId == transferId &&
          h.direction == TransferDirection.incoming &&
          h.localPath.isNotEmpty) {
        return h.localPath;
      }
    }
    return null;
  }

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
    final name = path.split(Platform.pathSeparator).last;
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;

    // File-reading steps (size/mtime/whole-file hash) can throw just as
    // easily as the RPC calls below (e.g. the picked file was deleted or
    // became unreadable between pick and send), so they get the same
    // try/catch + failed-transfer emission instead of propagating
    // uncaught and leaving the user with no error row at all.
    int size;
    DateTime mtime;
    String fileId;
    String fileHash;
    try {
      size = await file.length();
      mtime = await file.lastModified();
      // Deterministic (not random) so retrying the *same* file to the
      // *same* peer after a dropped connection reuses the file_id the
      // receiver keyed its partial under, which is what makes resume work.
      fileId = _deterministicTransferId(path, size, mtime);
      // Streaming whole-file SHA-256 (constant memory) declared up front.
      fileHash = await _hashFile(file);
    } catch (e) {
      debugPrint('sendFile: failed to read $path: $e');
      // No real size/mtime available, so the id can't be the usual
      // resumable one -- this file was never opened, so there is nothing
      // to resume anyway. Still stable enough per path to dedupe repeat
      // taps on the same broken file into one row instead of piling up.
      final fallbackId = sha256.convert(utf8.encode('unreadable|$path')).toString().substring(0, 32);
      _emitOutgoing(fallbackId, name, 0, 0, failed: true);
      _recordHistory(
        transferId: fallbackId,
        fileName: name,
        totalBytes: 0,
        direction: TransferDirection.outgoing,
        status: 'failed',
        startedAtMs: startedAtMs,
      );
      return;
    }
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
      _recordHistory(
        transferId: fileId,
        fileName: name,
        totalBytes: size,
        direction: TransferDirection.outgoing,
        status: 'failed',
        startedAtMs: startedAtMs,
      );
      return;
    }

    final offer = prep.offers.firstWhere(
      (o) => o.fileId == fileId,
      orElse: () => pb.UploadFileOffer(accepted: false),
    );
    if (!offer.accepted) {
      _emitOutgoing(fileId, name, 0, size, failed: true);
      _recordHistory(
        transferId: fileId,
        fileName: name,
        totalBytes: size,
        direction: TransferDirection.outgoing,
        status: 'failed',
        startedAtMs: startedAtMs,
      );
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
        _recordHistory(
          transferId: fileId,
          fileName: name,
          totalBytes: size,
          direction: TransferDirection.outgoing,
          status: 'completed',
          startedAtMs: startedAtMs,
        );
      } else if (_canceledOutgoing.contains(fileId)) {
        _emitOutgoing(fileId, name, result.bytesReceived.toInt(), size,
            failed: true, canceled: true);
        _recordHistory(
          transferId: fileId,
          fileName: name,
          totalBytes: size,
          direction: TransferDirection.outgoing,
          status: 'canceled',
          startedAtMs: startedAtMs,
        );
      } else {
        _emitOutgoing(fileId, name, result.bytesReceived.toInt(), size,
            failed: true);
        _recordHistory(
          transferId: fileId,
          fileName: name,
          totalBytes: size,
          direction: TransferDirection.outgoing,
          status: 'failed',
          startedAtMs: startedAtMs,
        );
      }
    } catch (e) {
      debugPrint('uploadFile failed for $fileId: $e');
      _emitOutgoing(fileId, name, resume, size, failed: true);
      _recordHistory(
        transferId: fileId,
        fileName: name,
        totalBytes: size,
        direction: TransferDirection.outgoing,
        status: 'failed',
        startedAtMs: startedAtMs,
      );
    } finally {
      _canceledOutgoing.remove(fileId);
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

  // --- incoming file transfers (PrepareUpload + UploadFile) --------------
  // LocalSend-style path: bytes arrive on their own client-streaming RPC
  // (not the SyncStream), written straight to disk while a streaming
  // SHA-256 is folded -- never buffers the whole file in RAM.

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
    // Captured when the header is processed (not when PrepareUpload
    // originally minted the ticket), same convention the daemon's own
    // upload_file handler uses -- a resumed transfer's history entry
    // reflects the last attempt that actually finished it.
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;

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
      _recordHistory(
        transferId: ticket.fileId,
        fileName: ticket.fileName,
        totalBytes: ticket.totalBytes,
        direction: TransferDirection.incoming,
        status: 'failed',
        startedAtMs: startedAtMs,
      );
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
    _recordHistory(
      transferId: ticket.fileId,
      fileName: ticket.fileName,
      totalBytes: ticket.totalBytes,
      direction: TransferDirection.incoming,
      status: 'completed',
      startedAtMs: startedAtMs,
      // T-X5: persist where the finalized file landed so "Save to..."
      // still resolves it after an app restart.
      localPath: finalPath,
    );
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

