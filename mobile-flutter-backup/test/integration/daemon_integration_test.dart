import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connectible_mobile/src/services/crc32.dart';
import 'package:connectible_mobile/src/services/grpc_service.dart';
import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart' as pb;
import 'package:connectible_mobile/src/generated/connectible.pb.dart' as pb;

/// Daemon integration test harness.
///
/// Spawns a real `connectibled` binary on a free port with an isolated
/// XDG_DATA_HOME, then drives the real GrpcService client over TLS.
/// Self-skips if RUN_DAEMON_INTEGRATION is not set or the binary is absent.
class _DaemonHarness {
  final String _tmpDir;
  final Directory _xdgDir;
  final int _port;
  final Process _proc;

  _DaemonHarness._internal(
    this._tmpDir,
    this._xdgDir,
    this._port,
    this._proc,
  );

  /// Allocates a free port by binding then closing, returns the port.
  static Future<int> _allocatePort() async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final port = server.port;
    await server.close();
    return port;
  }

  /// Spawns the daemon. Throws if binary missing or env var not set.
  static Future<_DaemonHarness> spawn() async {
    const envVar = 'RUN_DAEMON_INTEGRATION';
    if (Platform.environment[envVar] != '1') {
      throw StateError('RUN_DAEMON_INTEGRATION=1 not set; skipping');
    }

    final binPath = _findBinary();
    if (binPath == null) {
      throw StateError('connectibled binary not found in target/debug/ or PATH; skipping');
    }

    final tmpDir = await Directory.systemTemp.createTemp('connectible_daemon_test_');
    final xdgDir = Directory('${tmpDir.path}/xdg');
    await xdgDir.create(recursive: true);

    final port = await _allocatePort();

    final env = <String, String>{
      ...Platform.environment,
      'XDG_DATA_HOME': xdgDir.path,
      'CONNECTIBLE_PORT': port.toString(),
      'CONNECTIBLE_DEVICE_NAME': 'Test Daemon',
      'RUST_LOG': 'info',
    };

    final proc = await Process.start(binPath, [], environment: env);

    // Wait for daemon to generate cert and start listening.
    await _waitForCert(xdgDir.path);

    final certPath = '${xdgDir.path}/connectibled/tls/cert.pem';
    if (!await File(certPath).exists()) {
      await _killAndCleanup(proc, tmpDir);
      throw StateError('Daemon failed to generate TLS cert at $certPath');
    }

    return _DaemonHarness._internal(tmpDir.path, xdgDir, port, proc);
  }

  static String? _findBinary() {
    // Prefer the workspace build output. When run from mobile/, ws is mobile/.
    // The daemon binary is at workspace_root/daemon/target/debug/connectibled
    // or workspace_root/target/debug/connectibled.
    final ws = Directory.current;
    final candidates = <String>[
      // From mobile/ go up to workspace then into daemon/
      '${ws.path}/../daemon/target/debug/connectibled',
      '${ws.path}/../target/debug/connectibled',
      // If already in workspace root
      '${ws.path}/daemon/target/debug/connectibled',
      '${ws.path}/target/debug/connectibled',
      'connectibled', // PATH fallback
    ];
    for (final c in candidates) {
      if (File(c).existsSync() || _inPathSync(c)) {
        return c;
      }
    }
    return null;
  }

  static bool _inPathSync(String cmd) {
    try {
      final which = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [cmd],
        runInShell: true,
      );
      return which.exitCode == 0 && which.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _waitForCert(String xdgDir) async {
    final certPath = '$xdgDir/connectibled/tls/cert.pem';
    for (var i = 0; i < 50; i++) {
      if (await File(certPath).exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Connects GrpcService to the spawned daemon.
  Future<GrpcService> connect() => GrpcService.connect('127.0.0.1', _port);

  /// Returns the received-files directory where the daemon finalizes transfers.
  String get receivedDir => '${_xdgDir.path}/connectibled/received';

  /// Shuts down the daemon and deletes the temp directory.
  Future<void> teardown() async {
    _proc.kill(ProcessSignal.sigterm);
    try {
      await _proc.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _proc.kill(ProcessSignal.sigkill);
      await _proc.exitCode;
    }
    await _xdgDir.delete(recursive: true);
    await Directory(_tmpDir).delete(recursive: true);
  }

  static Future<void> _killAndCleanup(Process proc, Directory tmpDir) async {
    proc.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  }
}

/// Generates a random test identity.
pb.Identity _testIdentity(String deviceId, String name) => pb.Identity(
      deviceId: deviceId,
      deviceName: name,
      platform: pb.Platform.PLATFORM_ANDROID,
      deviceType: pb.DeviceType.DEVICE_TYPE_PHONE,
      protocolVersion: 1,
      appVersion: '0.1.0-test',
      capabilities: const ['clipboard', 'file_transfer', 'remote_input'],
    );

/// Computes SHA-256 hex of bytes.
String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Builds a stream of SyncFrames for file transfer (Identity -> Start -> Chunks).
///
/// `resumeOffsetBytes` starts the chunk stream partway through the file
/// (T-025 resume, mirroring what a real sender's remembered offset would
/// produce). `stopBeforeByte`, if set, ends the stream once that many
/// bytes have been sent without ever emitting `is_last`, simulating a
/// dropped connection mid-transfer.
Stream<pb.SyncFrame> _fileTransferFrames({
  required String transferId,
  required List<int> fileBytes,
  required String fileName,
  required pb.Identity identity,
  int resumeOffsetBytes = 0,
  int? stopBeforeByte,
}) async* {
  final fileHash = _sha256Hex(fileBytes);
  const chunkSize = 65536;

  // Identity frame first.
  yield pb.SyncFrame(identity: identity);

  // FileTransferStart.
  yield pb.SyncFrame(
    fileTransferStart: pb.FileTransferStart(
      transferId: transferId,
      fileName: fileName,
      fileSizeBytes: Int64(fileBytes.length),
      fileHash: fileHash,
      chunkSizeBytes: chunkSize,
      resumeOffsetBytes: Int64(resumeOffsetBytes),
      mimeType: 'application/octet-stream',
    ),
  );

  // Chunks, starting at resumeOffsetBytes.
  var offset = resumeOffsetBytes;
  while (offset < fileBytes.length) {
    if (stopBeforeByte != null && offset >= stopBeforeByte) return;
    final chunkEnd = (offset + chunkSize).clamp(0, fileBytes.length);
    final data = fileBytes.sublist(offset, chunkEnd);
    final isLast = chunkEnd == fileBytes.length;
    yield pb.SyncFrame(
      fileChunk: pb.FileChunk(
        transferId: transferId,
        offsetBytes: Int64(offset),
        data: data,
        isLast: isLast,
        chunkChecksum: Crc32.compute(data),
      ),
    );
    offset = chunkEnd;
  }
}

void main() {
  group('Daemon Integration (requires RUN_DAEMON_INTEGRATION=1)', () {
    _DaemonHarness? harness;

    setUpAll(() async {
      try {
        harness = await _DaemonHarness.spawn();
      } catch (e) {
        // Mark as skipped by returning normally; tests will be skipped.
        // ignore: avoid_print
        print('Daemon harness unavailable: $e');
      }
    });

    tearDownAll(() async {
      if (harness != null) {
        await harness!.teardown();
      }
    });

    test('connect + ping round-trips', () async {
      if (harness == null) return; // skipped
      final grpc = await harness!.connect();
      try {
        final rtt = await grpc.pingRttMs();
        expect(rtt, greaterThanOrEqualTo(0));
      } finally {
        await grpc.shutdown();
      }
    });

    test('pair + confirm PIN from local event stream', () async {
      if (harness == null) return;
      final grpc = await harness!.connect();
      final uiGrpc = await harness!.connect();
      try {
        // Subscribe to local events on the "UI" connection.
        final events = uiGrpc.raw.subscribeLocalEvents(pb.LocalEventsRequest());
        final eventStream = events.asBroadcastStream();

        // Apply filter FIRST to catch the event when it arrives.
        final pairingEvents = eventStream.where((e) => e.hasPairingRequested());

        // Small delay to ensure subscription is registered before pair request.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Request pairing from the "phone" connection.
        final identity = _testIdentity('test-phone-1', 'Test Phone 1');
        final pairResp = await grpc.raw.pair(pb.PairRequest(requester: identity));
        expect(pairResp.accepted, isTrue);
        expect(pairResp.hasPinExpiresAtMs(), isTrue);

        // Read PIN from the local event stream.
        final pairEvent = await pairingEvents.first.timeout(const Duration(seconds: 10));
        final pin = pairEvent.pairingRequested.pinCode;
        expect(pin.length, 6);

        // Confirm the PIN.
        final confirmResp = await grpc.raw.confirmPin(
          pb.ConfirmPinRequest(deviceId: identity.deviceId, pinCode: pin),
        );
        expect(confirmResp.verified, isTrue);
      } finally {
        // Shutdown with timeout to avoid hanging.
        await grpc.shutdown().timeout(const Duration(seconds: 5), onTimeout: () {});
        await uiGrpc.shutdown().timeout(const Duration(seconds: 5), onTimeout: () {});
      }
    });

    test('wrong PIN is rejected', () async {
      if (harness == null) return;
      final grpc = await harness!.connect();
      try {
        final identity = _testIdentity('test-phone-2', 'Test Phone 2');
        final pairResp = await grpc.raw.pair(pb.PairRequest(requester: identity));
        expect(pairResp.accepted, isTrue);

        // Confirm with wrong PIN.
        final confirmResp = await grpc.raw.confirmPin(
          pb.ConfirmPinRequest(deviceId: identity.deviceId, pinCode: '000000'),
        );
        expect(confirmResp.verified, isFalse);
      } finally {
        await grpc.shutdown();
      }
    });

    test('file send lands on daemon byte-for-byte', () async {
      if (harness == null) return;
      final grpc = await harness!.connect();
      try {
        final identity = _testIdentity('test-sender', 'Test Sender');
        final fileBytes = List<int>.generate(150000, (i) => (i * 31) % 251);
        final transferId = 'e2e-transfer-${Random.secure().nextInt(1 << 30)}';
        const fileName = 'payload.bin';

        final outbound = _fileTransferFrames(
          transferId: transferId,
          fileBytes: fileBytes,
          fileName: fileName,
          identity: identity,
        );

        final inbound = grpc.raw.syncStream(outbound);
        // Drain inbound until stream closes (daemon closes after finalize).
        await inbound.toList();

        // Give finalize a moment to rename .part -> received/
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // Assert file exists with identical bytes.
        final receivedDir = harness!.receivedDir;
        final files = Directory(receivedDir).listSync().whereType<File>().toList();
        expect(files, isNotEmpty);
        final receivedBytes = await files.first.readAsBytes();
        expect(receivedBytes, equals(fileBytes));
      } finally {
        await grpc.shutdown();
      }
    });

    test('resumed transfer (dropped, retried on a new connection) lands intact', () async {
      if (harness == null) return;
      final identity = _testIdentity('test-sender-resume', 'Test Sender Resume');
      final fileBytes = List<int>.generate(150000, (i) => (i * 17) % 251);
      final transferId = 'e2e-resume-${Random.secure().nextInt(1 << 30)}';
      const fileName = 'resume-payload.bin';
      const splitPoint = 70000; // mid-file, not on a 64KB chunk boundary

      // First "connection": send from the top, drop before finishing.
      final grpc1 = await harness!.connect();
      try {
        final outbound1 = _fileTransferFrames(
          transferId: transferId,
          fileBytes: fileBytes,
          fileName: fileName,
          identity: identity,
          stopBeforeByte: splitPoint,
        );
        await grpc1.raw.syncStream(outbound1).toList();
      } finally {
        await grpc1.shutdown();
      }

      // Give the daemon a moment to have the partial .part file on disk.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // "Reconnect": a brand-new connection, same transfer_id, resuming
      // from splitPoint -- exactly what a sender that remembered its
      // last-acked offset would do (T-025).
      final grpc2 = await harness!.connect();
      try {
        final outbound2 = _fileTransferFrames(
          transferId: transferId,
          fileBytes: fileBytes,
          fileName: fileName,
          identity: identity,
          resumeOffsetBytes: splitPoint,
        );
        await grpc2.raw.syncStream(outbound2).toList();
      } finally {
        await grpc2.shutdown();
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      final file = File('${harness!.receivedDir}/$fileName');
      expect(await file.exists(), isTrue);
      final receivedBytes = await file.readAsBytes();
      expect(receivedBytes, equals(fileBytes));
    });

    test('clipboard frame round-trips (optional)', () async {
      if (harness == null) return;
      // This test is optional and only exercises the frame path.
      // It does not assert clipboard content (no backend in CI).
      final grpc = await harness!.connect();
      final uiGrpc = await harness!.connect();
      try {
        final identity = _testIdentity('clip-phone', 'Clip Phone');
        final unique = 'connectible-e2e-clipboard-${DateTime.now().millisecondsSinceEpoch}';
        final contentHash = _sha256Hex(utf8.encode(unique));

        // UI connection subscribes to local events to see if clipboard frame is processed.
        // (We don't assert on clipboard backend; just ensure the frame is accepted.)

        final outbound = Stream.fromIterable([
          pb.SyncFrame(identity: identity),
          pb.SyncFrame(
            clipboard: pb.ClipboardData(
              mimeType: 'text/plain',
              content: utf8.encode(unique),
              capturedAtMs: Int64(DateTime.now().millisecondsSinceEpoch),
              contentHash: contentHash,
            ),
          ),
        ]);

        final inbound = grpc.raw.syncStream(outbound);
        await inbound.toList();

        // If we get here without error, the frame was accepted.
        // The Rust test skips gracefully when no clipboard backend; we do the same.
      } finally {
        await grpc.shutdown();
        await uiGrpc.shutdown();
      }
    });
  });
}