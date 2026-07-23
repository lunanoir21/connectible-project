@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/state/file_transfer_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fresh, empty-backed prefs instance per call (Phase J): FileTransferModel
/// now persists its transfer history through shared_preferences the same
/// way DeviceListModel persists its paired-device roster.
Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

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
      final model =
          FileTransferModel(connection: connection, prefs: await _testPrefs());
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
      final model = FileTransferModel(
          connection: _FakeConnection(), prefs: await _testPrefs());
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
      final model = FileTransferModel(
          connection: _FakeConnection(), prefs: await _testPrefs());
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
      final model = FileTransferModel(
          connection: _FakeConnection(), prefs: await _testPrefs());
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

    test(
        'a stream that errors mid-transfer yields a failed row (not stuck '
        'Receiving), and a later upload still works (T-X23)', () async {
      final model = FileTransferModel(
          connection: _FakeConnection(), prefs: await _testPrefs());
      addTearDown(model.dispose);

      final bytes = List<int>.generate(150000, (i) => (i * 13) % 251);
      const fileId = 'up-stream-error';
      final prep = await prepare(model, fileId, 'e.bin', bytes);
      final offer = prep.offers.single;

      Stream<pb.UploadFilePart> erroringStream() async* {
        yield pb.UploadFilePart(
          header: pb.UploadFileHeader(
            sessionId: prep.sessionId,
            fileId: fileId,
            token: offer.token,
            offsetBytes: Int64(0),
          ),
        );
        yield pb.UploadFilePart(chunk: bytes.sublist(0, 40000));
        // Simulates a dropped TCP connection: the stream itself errors
        // instead of just ending early.
        throw Exception('simulated connection reset');
      }

      await expectLater(
          model.handleUploadFile(erroringStream()), throwsException);

      final progress = model.transfers[fileId];
      expect(progress, isNotNull);
      expect(progress!.completed, isFalse);
      expect(progress.failed, isTrue,
          reason: 'must not be left stuck in a non-terminal Receiving state');

      // The failure must not have wedged the model -- a fresh, unrelated
      // upload still completes normally.
      const otherId = 'up-after-stream-error';
      final otherBytes = List<int>.generate(1000, (i) => i % 250);
      final prep2 = await prepare(model, otherId, 'ok.bin', otherBytes);
      final offer2 = prep2.offers.single;
      final result2 = await model.handleUploadFile(uploadStream(
          prep2.sessionId, otherId, offer2.token, otherBytes));
      expect(result2.completed, isTrue);
      expect(result2.hashOk, isTrue);
    });

    test('a full ticket registry declines further offers (T-X23)', () async {
      final model = FileTransferModel(
          connection: _FakeConnection(), prefs: await _testPrefs());
      addTearDown(model.dispose);

      // Same single-file request repeated: each call mints a fresh token
      // (the map key), so this fills the registry to the cap without
      // needing distinct file ids.
      for (var i = 0; i < FileTransferModel.maxUploadTickets; i++) {
        final prep = await prepare(model, 'fill-$i', 'f.bin', const [1, 2, 3]);
        expect(prep.offers.single.accepted, isTrue,
            reason: 'offer $i should still be under the cap');
      }

      final full = await prepare(model, 'overflow', 'f.bin', const [1, 2, 3]);
      final offer = full.offers.single;
      expect(offer.accepted, isFalse);
      expect(offer.rejectReason, pb.ErrorCode.ERROR_CODE_INTERNAL.name);
    });
  });

  group('FileTransferModel - persisted history (Phase J)', () {
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
        String session, String fileId, String token, List<int> bytes) async* {
      yield pb.UploadFilePart(
        header: pb.UploadFileHeader(
          sessionId: session,
          fileId: fileId,
          token: token,
          offsetBytes: Int64(0),
        ),
      );
      for (var i = 0; i < bytes.length; i += 64 * 1024) {
        final end =
            (i + 64 * 1024) > bytes.length ? bytes.length : (i + 64 * 1024);
        yield pb.UploadFilePart(chunk: bytes.sublist(i, end));
      }
    }

    test(
        'a completed incoming transfer survives an app restart '
        '(model reconstruction against the same prefs)', () async {
      final prefs = await _testPrefs();
      final model =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(model.dispose);

      final bytes = List<int>.generate(20000, (i) => (i * 7) % 251);
      const fileId = 'hist-restart';
      final prep = await prepare(model, fileId, 'keeper.bin', bytes);
      final result = await model.handleUploadFile(
          uploadStream(prep.sessionId, fileId, prep.offers.single.token, bytes));
      expect(result.completed, isTrue);

      expect(model.history, hasLength(1));
      expect(model.history.single.transferId, fileId);
      expect(model.history.single.status, 'completed');
      expect(model.history.single.direction, TransferDirection.incoming);
      expect(model.history.single.fileName, 'keeper.bin');
      expect(model.history.single.totalBytes, bytes.length);

      // "Restart": a brand-new model against the same prefs instance has
      // an empty in-memory transfers map but the persisted history entry.
      final restarted =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(restarted.dispose);
      expect(restarted.transfers, isEmpty);
      expect(restarted.history, hasLength(1));
      expect(restarted.history.single.transferId, fileId);
      expect(restarted.history.single.status, 'completed');
    });

    test('a hash-mismatched incoming transfer is recorded as failed',
        () async {
      final prefs = await _testPrefs();
      final model =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(model.dispose);

      final bytes = List<int>.generate(10000, (i) => i % 250);
      const fileId = 'hist-badhash';
      final prep =
          await prepare(model, fileId, 'bad.bin', bytes, hash: 'deadbeef');
      final result = await model.handleUploadFile(
          uploadStream(prep.sessionId, fileId, prep.offers.single.token, bytes));
      expect(result.completed, isFalse);

      expect(model.history, hasLength(1));
      expect(model.history.single.status, 'failed');
      expect(model.history.single.direction, TransferDirection.incoming);
    });

    test('a corrupted stored history blob falls back to empty, not a crash',
        () async {
      SharedPreferences.setMockInitialValues(
          {'connectible.transfer_history': 'not json at all {'});
      final prefs = await SharedPreferences.getInstance();
      final model =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(model.dispose);
      expect(model.history, isEmpty);
    });

    test(
        'incomingFilePath survives an app restart via the persisted '
        'localPath (T-X5)', () async {
      final prefs = await _testPrefs();
      final model =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(model.dispose);

      final bytes = List<int>.generate(20000, (i) => (i * 13) % 251);
      const fileId = 'hist-savepath';
      final prep = await prepare(model, fileId, 'kept.bin', bytes);
      final result = await model.handleUploadFile(uploadStream(
          prep.sessionId, fileId, prep.offers.single.token, bytes));
      expect(result.completed, isTrue);
      final livePath = model.incomingFilePath(fileId);
      expect(livePath, isNotNull);

      // "Restart": the in-memory path map is gone, but the persisted
      // history entry still resolves the same on-disk file.
      final restarted =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(restarted.dispose);
      expect(restarted.incomingFilePath(fileId), livePath);
      expect(File(restarted.incomingFilePath(fileId)!).existsSync(), isTrue);
    });

    test(
        'a pre-T-X5 history blob without localPath loads, and the entry '
        'simply has no saved path (backward compatibility)', () async {
      SharedPreferences.setMockInitialValues({
        'connectible.transfer_history':
            '[{"transferId":"legacy-1","peerDeviceId":"peer-1",'
                '"fileName":"old.bin","totalBytes":10,'
                '"direction":"incoming","status":"completed",'
                '"startedAtMs":1,"finishedAtMs":2}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final model =
          FileTransferModel(connection: _FakeConnection(), prefs: prefs);
      addTearDown(model.dispose);
      expect(model.history.single.localPath, isEmpty);
      expect(model.incomingFilePath('legacy-1'), isNull);
    });
  });

  // The legacy chunk-over-SyncStream receive path (T-905's
  // handleFileTransferStart/handleFileChunk and T-908's
  // chunk-corruption/resend fault injection) was removed in Phase I
  // along with the production code it tested -- every transfer now
  // runs over the dedicated PrepareUpload/UploadFile RPCs, covered by
  // the groups above.
}
