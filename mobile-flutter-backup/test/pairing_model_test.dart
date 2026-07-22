@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/services/connectible_server.dart';
import 'package:connectible_mobile/src/services/pairing_manager.dart';
import 'package:connectible_mobile/src/services/server_identity.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/state/pairing_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Responder-side test double (T-905): a real [ConnectibleServer] bound to
/// an ephemeral loopback port, driven by a real [PairingManager] (no PIN
/// logic is faked -- see `pairing_manager_test.dart` for that in
/// isolation). This lets `PairingModel`'s requester-side code
/// (`startPair`/`confirmPin`/session activation/reconnect) run against
/// real TLS 1.3 + gRPC instead of a mock, mirroring the existing
/// `test/integration/server_pairing_test.dart` pattern rather than
/// inventing a second one.
class _RespondingDelegate implements ServerDelegate {
  _RespondingDelegate(this.localIdentity);

  @override
  final pb.Identity localIdentity;

  final List<pb.Identity> paired = [];
  final List<StreamController<pb.SyncFrame>> inboundOuts = [];

  @override
  void onPeerPaired(pb.Identity requester) => paired.add(requester);

  @override
  List<DeviceInfo> knownDevices() => const [];

  @override
  Stream<pb.SyncFrame> onInboundSyncStream(Stream<pb.SyncFrame> inbound) {
    final out = StreamController<pb.SyncFrame>();
    inboundOuts.add(out);
    out.add(pb.SyncFrame(identity: localIdentity));
    inbound.listen((_) {}, onDone: out.close, onError: (_) => out.close());
    return out.stream;
  }

  @override
  Future<pb.PrepareUploadResponse> prepareUpload(
          pb.PrepareUploadRequest request) async =>
      throw UnimplementedError();

  @override
  Future<pb.UploadFileResult> uploadFile(
          Stream<pb.UploadFilePart> request) async =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DeviceListModel> buildDeviceList() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return DeviceListModel(prefs,
        deviceName: 'Test Phone', pairableEnabled: false);
  }

  // pairableEnabled: false on every PairingModel under test so the
  // constructor never tries to start this device's *own* real inbound
  // server (which needs path_provider/on-disk cert storage, unavailable
  // in this unit test host) -- responder-side coverage below drives
  // ServerDelegate's entry points directly instead, exactly like
  // `remote_input_screen_test.dart` already does for widget tests.
  PairingModel buildPairing(
    DeviceListModel deviceList, {
    void Function(pb.ClipboardData)? onClipboardFrame,
    void Function(pb.FileTransferStart)? onFileTransferStart,
    void Function(pb.FileChunk)? onFileChunk,
    void Function(pb.FileChunkRequest)? onFileChunkRequest,
  }) =>
      PairingModel(
        deviceList: deviceList,
        onClipboardFrame: onClipboardFrame ?? (_) {},
        onFileTransferStart: onFileTransferStart ?? (_) {},
        onFileChunk: onFileChunk ?? (_) {},
        onFileChunkRequest: onFileChunkRequest ?? (_) {},
        pairableEnabled: false,
      );

  group('PairingModel - responder (inbound) session lifecycle', () {
    test(
        'onInboundSyncStream transitions connected false -> true, and back '
        'to false once the inbound stream closes', () async {
      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      expect(pairing.connected, isFalse);

      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      expect(pairing.connected, isTrue);

      await inbound.close();
      await sub.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(pairing.connected, isFalse);
    });

    test(
        'dispatches each inbound frame kind to its matching callback exactly '
        'once', () async {
      final deviceList = await buildDeviceList();
      pb.ClipboardData? clip;
      pb.FileTransferStart? start;
      pb.FileChunk? chunk;
      pb.FileChunkRequest? req;
      final pairing = buildPairing(
        deviceList,
        onClipboardFrame: (c) => clip = c,
        onFileTransferStart: (s) => start = s,
        onFileChunk: (c) => chunk = c,
        onFileChunkRequest: (r) => req = r,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      addTearDown(() {
        sub.cancel();
        inbound.close();
      });

      inbound.add(
          pb.SyncFrame(clipboard: pb.ClipboardData(content: 'hi'.codeUnits)));
      inbound.add(
          pb.SyncFrame(fileTransferStart: pb.FileTransferStart(transferId: 't1')));
      inbound.add(pb.SyncFrame(fileChunk: pb.FileChunk(transferId: 't1')));
      inbound.add(
          pb.SyncFrame(fileChunkRequest: pb.FileChunkRequest(transferId: 't1')));
      await Future<void>.delayed(Duration.zero);

      expect(clip?.content, 'hi'.codeUnits);
      expect(start?.transferId, 't1');
      expect(chunk?.transferId, 't1');
      expect(req?.transferId, 't1');
    });

    test('onPeerPaired/knownDevices delegate straight through to DeviceListModel',
        () async {
      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      pairing.onPeerPaired(
          pb.Identity(deviceId: 'peer-9', deviceName: 'Peer Nine'));

      expect(pairing.knownDevices().map((d) => d.deviceId), contains('peer-9'));
    });
  });

  group('PairingModel - requester pairing flow (real loopback TLS server)', () {
    late ServerIdentity identity;
    setUpAll(() {
      identity = ServerIdentity.generate();
    });

    Future<
        ({
          ConnectibleServer server,
          PairingManager pairingManager,
          _RespondingDelegate delegate,
          int port
        })> startResponder() async {
      final delegate =
          _RespondingDelegate(pb.Identity(deviceId: 'desk-1', deviceName: 'Desk'));
      final pairingManager = PairingManager();
      final server = ConnectibleServer(delegate, pairingManager);
      final port = await server.start(identity, port: 0);
      return (
        server: server,
        pairingManager: pairingManager,
        delegate: delegate,
        port: port
      );
    }

    NearbyDevice deviceFor(int port) => NearbyDevice(
          deviceId: 'desk-1',
          deviceName: 'Desk',
          platform: 'PLATFORM_LINUX_X11',
          host: 'localhost',
          port: port,
        );

    test(
        'startPair against an unreachable peer sets lastError and leaves '
        'pendingPairing unset (connecting -> error, not connected)', () async {
      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      // A port nothing listens on: bind, then close immediately, so the
      // dial that follows is refused deterministically and fast instead
      // of depending on real network hardware (RULES.md Testing section).
      final freeSrv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = freeSrv.port;
      await freeSrv.close();

      final ok = await pairing.startPair(deviceFor(closedPort));

      expect(ok, isFalse);
      expect(pairing.pendingPairing, isNull);
      expect(pairing.lastError, isNotNull);
      expect(pairing.connected, isFalse);
    });

    test(
        'startPair against a real responder sets pendingPairing with the '
        "daemon's PIN deadline (connecting -> pending)", () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      final ok = await pairing.startPair(deviceFor(r.port));

      expect(ok, isTrue);
      expect(pairing.lastError, isNull);
      expect(pairing.pendingPairing, isNotNull);
      // The responder's real PairingManager created a pending entry keyed
      // by this device's own identity, proving the Pair RPC actually
      // reached it rather than pendingPairing being set speculatively.
      expect(r.pairingManager.peekPin(pairing.localIdentity.deviceId),
          isNotNull);

      await pairing.pendingPairing!.grpc.shutdown();
    });

    test(
        "confirmPin with the wrong code fails and surfaces the daemon's "
        'error without transitioning to connected', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final verified = await pairing.confirmPin('000000');

      expect(verified, isFalse);
      expect(pairing.lastError, isNotNull);
      expect(pairing.connected, isFalse);
    });

    test(
        'confirmPin with the correct PIN activates the session '
        '(pending -> connected) and records the peer as paired', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;

      final verified = await pairing.confirmPin(pin);

      expect(verified, isTrue);
      expect(pairing.connected, isTrue);
      expect(pairing.pendingPairing, isNull);
      expect(r.delegate.paired.map((i) => i.deviceId),
          contains(pairing.localIdentity.deviceId));
    });

    test(
        'an expired PIN window is reported as a pairing-timeout error, not a '
        'silent failure', () async {
      // Uses PairingManager's injectable clock (same technique as
      // pairing_manager_test.dart's expiry test) so this is a real expiry,
      // not a 30-second real-time sleep.
      var currentMs = 1000000;
      final delegate =
          _RespondingDelegate(pb.Identity(deviceId: 'desk-2', deviceName: 'Desk'));
      final pairingManager = PairingManager(now: () => currentMs);
      final server = ConnectibleServer(delegate, pairingManager);
      final port = await server.start(identity, port: 0);
      addTearDown(() => server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(NearbyDevice(
        deviceId: 'desk-2',
        deviceName: 'Desk',
        platform: 'PLATFORM_LINUX_X11',
        host: 'localhost',
        port: port,
      ));
      final pin = pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      currentMs += PairingManager.pinTtl.inMilliseconds + 1;

      final verified = await pairing.confirmPin(pin);

      expect(verified, isFalse);
      expect(pairing.lastError, isNotNull);
      expect(pairing.connected, isFalse);
    });

    test(
        'an unexpected drop of the active session marks the connection lost '
        'and schedules a reconnect (connected -> reconnecting)', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      await pairing.confirmPin(pin);
      expect(pairing.connected, isTrue);

      // Close the responder's outbound half of the stream out from under
      // the active session (server-side hangup) -- mirrors a desktop peer
      // crashing/network dropping mid-session, without tearing down the
      // whole TLS server (keeping this deterministic rather than racing a
      // full connection teardown).
      await r.delegate.inboundOuts.single.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(pairing.connected, isFalse);
      expect(pairing.reconnecting, isTrue);
    });

    test(
        'user-initiated disconnect stops reconnect attempts and clears '
        'session state (connected -> disconnected, no auto-reconnect)',
        () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      await pairing.confirmPin(pin);
      expect(pairing.connected, isTrue);

      await pairing.disconnect();

      expect(pairing.connected, isFalse);
      expect(pairing.reconnecting, isFalse);

      // Confirm no reconnect got scheduled behind disconnect()'s back: if
      // it had, connected would flip back to true shortly after.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(pairing.connected, isFalse);
    });

    test('cancelPairing tears down a pending (unconfirmed) connection cleanly',
        () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      expect(pairing.pendingPairing, isNotNull);

      pairing.cancelPairing();

      expect(pairing.pendingPairing, isNull);
      expect(pairing.connected, isFalse);
    });
  });
}
