@Timeout(Duration(seconds: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/services/crc32.dart';
import 'package:connectible_mobile/src/state/file_transfer_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Minimal [SyncConnection] test double (T-905): records every frame
/// [FileTransferModel] pushes outbound instead of needing a real network
/// connection, matching the pattern already established in
/// `test/screens/clipboard_screen_test.dart`/`transfers_screen_test.dart`.
class _FakeConnection implements SyncConnection {
  @override
  bool connected = true;

  @override
  String? activePeerId = 'peer-1';

  final List<pb.SyncFrame> sent = [];

  /// Optional stand-in for the active peer's upload client; null unless a
  /// test wires one up (upload-send tests need a real client, so they use
  /// the integration path instead).
  pb.ConnectibleClient? uploadClientOverride;

  @override
  pb.ConnectibleClient? get uploadClient => uploadClientOverride;

  @override
  pb.Identity get localIdentity => pb.Identity(deviceId: 'this-device');

  @override
  void sendFrame(pb.SyncFrame frame) => sent.add(frame);

  List<pb.FileChunk> get chunksSent =>
      sent.where((f) => f.whichPayload() == pb.SyncFrame_Payload.fileChunk)
          .map((f) => f.fileChunk)
          .toList();

  List<pb.FileChunkRequest> get chunkRequestsSent => sent
      .where((f) => f.whichPayload() == pb.SyncFrame_Payload.fileChunkRequest)
      .map((f) => f.fileChunkRequest)
      .toList();
}

/// Fakes `path_provider`'s application-documents directory (T-905/T-908):
/// [FileTransferModel]'s incoming-file path goes through
/// `getApplicationDocumentsDirectory()`, which needs a real platform
/// channel outside a running app. Points it at a per-test temp directory
/// instead, so incoming-transfer tests exercise the real disk-write path.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ft_model_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// Writes a source file of [size] bytes with deterministic, non-repeating
  /// content (same generator shape as the daemon's
  /// `corrupted_chunk_triggers_resend_and_transfer_completes` fixture) so a
  /// byte-flip is unambiguously detectable and multi-chunk sends have
  /// real chunk boundaries to exercise.
  Future<File> writeSourceFile(String name, int size) async {
    final bytes = List<int>.generate(size, (i) => (i * 31) % 251);
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  group('FileTransferModel - outgoing send (upload path)', () {
    test('sendFile is a no-op when there is no active peer upload client',
        () async {
      // The upload path needs the active peer's ConnectibleClient; with
      // none (responder-only / not connected), sendFile does nothing.
      final connection = _FakeConnection()..uploadClientOverride = null;
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      final file = await writeSourceFile('idle.bin', 10);
      await model.sendFile(file.path);

      expect(connection.sent, isEmpty);
      expect(model.transfers, isEmpty);
    });
  });

  group('FileTransferModel - incoming upload receive (Phase A)', () {
    Future<pb.PrepareUploadResponse> prepare(
        FileTransferModel model, String fileId, String name, List<int> bytes,
        {String? hash}) {
      return model.handlePrepareUpload(pb.PrepareUploadRequest(
        sender: pb.Identity(deviceId: 'peer-1'),
        sessionId: 'sess-$fileId',
        files: [
          pb.UploadFileMeta(
            fileId: fileId,
            fileName: name,
            fileSizeBytes: Int64(bytes.length),
            fileHash: hash ?? sha256.convert(bytes).toString(),
            mimeType: 'application/octet-stream',
          ),
        ],
      ));
    }

    Stream<pb.UploadFilePart> uploadStream(
        String session, String fileId, String token, List<int> bytes,
        {int offset = 0, int chunk = 64 * 1024}) async* {
      yield pb.UploadFilePart(
        header: pb.UploadFileHeader(
          sessionId: session,
          fileId: fileId,
          token: token,
          offsetBytes: Int64(offset),
        ),
      );
      for (var i = offset; i < bytes.length; i += chunk) {
        final end = (i + chunk) > bytes.length ? bytes.length : (i + chunk);
        yield pb.UploadFilePart(chunk: bytes.sublist(i, end));
      }
    }

    test('a prepared + streamed upload lands verified on disk', () async {
      final model = FileTransferModel(connection: _FakeConnection());
      addTearDown(model.dispose);

      final bytes = List<int>.generate(150000, (i) => (i * 31) % 251);
      const fileId = 'up-happy';
      final prep = await prepare(model, fileId, 'photo.bin', bytes);
      final offer = prep.offers.single;
      expect(offer.accepted, isTrue);
      expect(offer.resumeOffsetBytes.toInt(), 0);

      final result = await model
          .handleUploadFile(uploadStream(prep.sessionId, fileId, offer.token, bytes));
      expect(result.completed, isTrue);
      expect(result.hashOk, isTrue);

      final saved = model.incomingFilePath(fileId);
      expect(saved, isNotNull);
      expect(File(saved!).readAsBytesSync(), bytes);
    });

    test('a dropped stream keeps a partial that a second upload resumes',
        () async {
      final model = FileTransferModel(connection: _FakeConnection());
      addTearDown(model.dispose);

      final bytes = List<int>.generate(150000, (i) => (i * 17) % 251);
      const fileId = 'up-resume';
      const cut = 90000;

      final prep1 = await prepare(model, fileId, 'r.bin', bytes);
      final offer1 = prep1.offers.single;
      final r1 = await model.handleUploadFile(uploadStream(
          prep1.sessionId, fileId, offer1.token, bytes.sublist(0, cut)));
      expect(r1.completed, isFalse);

      final prep2 = await prepare(model, fileId, 'r.bin', bytes);
      final offer2 = prep2.offers.single;
      expect(offer2.resumeOffsetBytes.toInt(), cut);

      final r2 = await model.handleUploadFile(uploadStream(
          prep2.sessionId, fileId, offer2.token, bytes,
          offset: cut));
      expect(r2.completed, isTrue);
      expect(r2.hashOk, isTrue);
      final saved = model.incomingFilePath(fileId);
      expect(File(saved!).readAsBytesSync(), bytes);
    });

    test('a wrong declared hash fails without finalizing', () async {
      final model = FileTransferModel(connection: _FakeConnection());
      addTearDown(model.dispose);

      final bytes = List<int>.generate(50000, (i) => i % 250);
      const fileId = 'up-badhash';
      final prep =
          await prepare(model, fileId, 'bad.bin', bytes, hash: '00ff00ff00ff');
      final offer = prep.offers.single;

      final result = await model
          .handleUploadFile(uploadStream(prep.sessionId, fileId, offer.token, bytes));
      expect(result.completed, isFalse);
      expect(result.hashOk, isFalse);
      expect(model.incomingFilePath(fileId), isNull);
    });
  });

  group('FileTransferModel - incoming receive (T-905)', () {
    test('handleFileChunk for an unregistered transfer id is ignored',
        () async {
      final connection = _FakeConnection();
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      model.handleFileChunk(pb.FileChunk(
        transferId: 'never-started',
        offsetBytes: Int64(0),
        data: [1, 2, 3],
        isLast: true,
        chunkChecksum: Crc32.compute([1, 2, 3]),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      expect(model.transfers, isEmpty);
    });

    test('a single correct chunk completes and hash-verifies', () async {
      final connection = _FakeConnection();
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      final content = utf8.encode('incoming payload');
      const transferId = 'incoming-ok-1';
      model.handleFileTransferStart(pb.FileTransferStart(
        transferId: transferId,
        fileName: 'note.txt',
        fileSizeBytes: Int64(content.length),
        fileHash: sha256.convert(content).toString(),
        chunkSizeBytes: content.length,
        resumeOffsetBytes: Int64(0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      model.handleFileChunk(pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(0),
        data: content,
        isLast: true,
        chunkChecksum: Crc32.compute(content),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      expect(model.transfers[transferId]!.completed, isTrue);
      expect(model.transfers[transferId]!.failed, isFalse);
      expect(model.transfers[transferId]!.bytesTransferred, content.length);
      // The finalized file's path is remembered so the UI's "Save to..."
      // action can copy it out of the app-private received/ dir, and it
      // actually exists on disk with the received bytes.
      final savedPath = model.incomingFilePath(transferId);
      expect(savedPath, isNotNull);
      expect(File(savedPath!).existsSync(), isTrue);
      expect(File(savedPath).readAsBytesSync(), content);
    });

    test('a whole-file hash mismatch fails the transfer instead of '
        'completing it', () async {
      final connection = _FakeConnection();
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      final content = utf8.encode('this content does not match the hash');
      const transferId = 'incoming-bad-hash';
      model.handleFileTransferStart(pb.FileTransferStart(
        transferId: transferId,
        fileName: 'note2.txt',
        fileSizeBytes: Int64(content.length),
        // Deliberately wrong whole-file hash, even though every
        // individual chunk's CRC32 will check out below.
        fileHash: sha256.convert(utf8.encode('something else entirely')).toString(),
        chunkSizeBytes: content.length,
        resumeOffsetBytes: Int64(0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      model.handleFileChunk(pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(0),
        data: content,
        isLast: true,
        chunkChecksum: Crc32.compute(content),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      expect(model.transfers[transferId]!.failed, isTrue);
      expect(model.transfers[transferId]!.completed, isFalse);
    });
  });

  // --- T-908: mobile-side fault injection, mirroring the daemon's
  // corrupted_chunk_triggers_resend_and_transfer_completes (grpc_smoke.rs)
  // -------------------------------------------------------------------

  group('FileTransferModel - chunk-corruption fault injection (T-908)', () {
    test(
        'a corrupted incoming chunk triggers exactly one FileChunkRequest, '
        'and the transfer completes with the correct hash once the '
        'resend arrives', () async {
      final connection = _FakeConnection();
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      // Two-chunk file, same shape as the daemon fixture: a first chunk
      // that gets corrupted in transit and a second (last) chunk that
      // arrives untouched.
      final chunk0 = List<int>.generate(40000, (i) => (i * 31) % 251);
      final chunk1 = List<int>.generate(20000, (i) => ((i + 7) * 53) % 251);
      final whole = [...chunk0, ...chunk1];
      const transferId = 'fault-injection-1';

      model.handleFileTransferStart(pb.FileTransferStart(
        transferId: transferId,
        fileName: 'payload.bin',
        fileSizeBytes: Int64(whole.length),
        fileHash: sha256.convert(whole).toString(),
        chunkSizeBytes: chunk0.length,
        resumeOffsetBytes: Int64(0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      // Chunk 0 arrives with one bit flipped -- the checksum was computed
      // honestly over the *correct* bytes by the sender, so this chunk's
      // CRC32 will not match what actually arrived (mirrors the daemon
      // test's proxy that XORs the first byte after the checksum is
      // already computed).
      final corruptedChunk0 = List<int>.from(chunk0);
      corruptedChunk0[0] ^= 0xFF;
      model.handleFileChunk(pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(0),
        data: corruptedChunk0,
        isLast: false,
        chunkChecksum: Crc32.compute(chunk0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      expect(connection.chunkRequestsSent, hasLength(1));
      expect(connection.chunkRequestsSent.single.transferId, transferId);
      expect(connection.chunkRequestsSent.single.offsetBytes.toInt(), 0);
      // Not yet complete or failed: still waiting on the resend.
      expect(model.transfers[transferId]!.completed, isFalse);
      expect(model.transfers[transferId]!.failed, isFalse);

      // The last chunk arrives correctly while offset 0 is still pending
      // -- must not finalize prematurely with the corrupt bytes still
      // outstanding.
      model.handleFileChunk(pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(chunk0.length),
        data: chunk1,
        isLast: true,
        chunkChecksum: Crc32.compute(chunk1),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      expect(model.transfers[transferId]!.completed, isFalse);
      expect(model.transfers[transferId]!.failed, isFalse);

      // Sender resends offset 0 with the correct bytes this time.
      model.handleFileChunk(pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(0),
        data: chunk0,
        isLast: false,
        chunkChecksum: Crc32.compute(chunk0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      // Still exactly one resend request was ever needed.
      expect(connection.chunkRequestsSent, hasLength(1));
      expect(model.transfers[transferId]!.completed, isTrue);
      expect(model.transfers[transferId]!.failed, isFalse);
      expect(model.transfers[transferId]!.bytesTransferred, whole.length);
    });

    test(
        'the same offset repeatedly failing CRC32 beyond the resend limit '
        'fails the whole transfer instead of looping forever', () async {
      final connection = _FakeConnection();
      final model = FileTransferModel(connection: connection);
      addTearDown(model.dispose);

      final content = List<int>.generate(1000, (i) => i % 200);
      const transferId = 'fault-injection-give-up';
      model.handleFileTransferStart(pb.FileTransferStart(
        transferId: transferId,
        fileName: 'never-fixed.bin',
        fileSizeBytes: Int64(content.length),
        fileHash: sha256.convert(content).toString(),
        chunkSizeBytes: content.length,
        resumeOffsetBytes: Int64(0),
      ));
      await pumpEventQueue();
      await model.pendingIoForTests;

      // Every attempt at offset 0 is corrupted -- the checksum is
      // deliberately wrong every single time, simulating a systematically
      // broken link rather than a one-off bit flip.
      final badChecksum = Crc32.compute(content) ^ 0xFFFFFFFF;
      for (var i = 0; i < 4; i++) {
        model.handleFileChunk(pb.FileChunk(
          transferId: transferId,
          offsetBytes: Int64(0),
          data: content,
          isLast: true,
          chunkChecksum: badChecksum,
        ));
        await pumpEventQueue();
      await model.pendingIoForTests;
      }

      expect(model.transfers[transferId]!.failed, isTrue);
      expect(model.transfers[transferId]!.completed, isFalse);
      // Bounded, not unbounded: at most a few resend requests were made,
      // not one per corrupted attempt forever.
      expect(connection.chunkRequestsSent.length, lessThanOrEqualTo(3));
    });
  });
}
