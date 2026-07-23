@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/services/connectible_server.dart';
import 'package:connectible_mobile/src/services/pairing_manager.dart';
import 'package:connectible_mobile/src/services/receiving_service.dart';
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
  // ownIdentityLoader (Phase G, T-G6) is injected the same way, for the
  // same reason: `startPair`/`reconnectToPeer` now also need this
  // device's own identity, and the real loader hits the same
  // unavailable path_provider dependency.
  final ownIdentity = ServerIdentity.generate();
  PairingModel buildPairing(
    DeviceListModel deviceList, {
    void Function(pb.ClipboardData)? onClipboardFrame,
    void Function(pb.NotificationData)? onNotificationFrame,
  }) =>
      PairingModel(
        deviceList: deviceList,
        onClipboardFrame: onClipboardFrame ?? (_) {},
        onNotificationFrame: onNotificationFrame,
        pairableEnabled: false,
        ownIdentityLoader: () async => ownIdentity,
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
        'dispatches a clipboard frame to its callback once the peer has '
        'identified itself as a paired device (Phase G, T-G6)', () async {
      final deviceList = await buildDeviceList();
      pb.ClipboardData? clip;
      final pairing = buildPairing(
        deviceList,
        onClipboardFrame: (c) => clip = c,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });
      deviceList.addPairedDevice(
          pb.Identity(deviceId: 'peer-1', deviceName: 'Peer One'));

      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      addTearDown(() {
        sub.cancel();
        inbound.close();
      });

      inbound.add(pb.SyncFrame(identity: pb.Identity(deviceId: 'peer-1')));
      inbound.add(
          pb.SyncFrame(clipboard: pb.ClipboardData(content: 'hi'.codeUnits)));
      await Future<void>.delayed(Duration.zero);

      expect(clip?.content, 'hi'.codeUnits);
    });

    test(
        'dispatches an inbound notification frame to its callback once the '
        'peer has identified itself (T-K4)', () async {
      final deviceList = await buildDeviceList();
      pb.NotificationData? notification;
      final pairing = buildPairing(
        deviceList,
        onNotificationFrame: (n) => notification = n,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });
      deviceList.addPairedDevice(
          pb.Identity(deviceId: 'peer-1', deviceName: 'Peer One'));

      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      addTearDown(() {
        sub.cancel();
        inbound.close();
      });

      inbound.add(pb.SyncFrame(identity: pb.Identity(deviceId: 'peer-1')));
      inbound.add(pb.SyncFrame(
          notification: pb.NotificationData(
              notificationId: 'n-1', isDismissal: true)));
      await Future<void>.delayed(Duration.zero);

      expect(notification?.notificationId, 'n-1');
      expect(notification?.isDismissal, isTrue);
    });

    test(
        'activePeerId falls back to the inbound peer once it has '
        'identified itself, for a session with no outbound dial (T-X24)',
        () async {
      final deviceList = await buildDeviceList();
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });
      deviceList.addPairedDevice(
          pb.Identity(deviceId: 'peer-1', deviceName: 'Peer One'));

      // Nothing set yet -- no outbound session, no inbound Identity frame.
      expect(pairing.activePeerId, isNull);

      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      addTearDown(() {
        sub.cancel();
        inbound.close();
      });

      inbound.add(pb.SyncFrame(identity: pb.Identity(deviceId: 'peer-1')));
      await Future<void>.delayed(Duration.zero);

      // This is what lets an inbound-only file push (e.g. a desktop
      // sending to this phone with no prior outbound dial from here)
      // record the real sender in transfer history instead of ''.
      expect(pairing.activePeerId, 'peer-1');
    });

    test(
        'drops inbound frames from an unidentified or unpaired peer '
        '(Phase G, T-G6)', () async {
      final deviceList = await buildDeviceList();
      pb.ClipboardData? clip;
      final pairing = buildPairing(deviceList, onClipboardFrame: (c) => clip = c);
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

      // No Identity frame sent yet: dropped, not attributed to anyone.
      inbound.add(
          pb.SyncFrame(clipboard: pb.ClipboardData(content: 'unattributed'.codeUnits)));
      await Future<void>.delayed(Duration.zero);
      expect(clip, isNull);

      // Identifies as a device that was never paired: still dropped.
      inbound.add(pb.SyncFrame(identity: pb.Identity(deviceId: 'stranger')));
      inbound.add(
          pb.SyncFrame(clipboard: pb.ClipboardData(content: 'unpaired'.codeUnits)));
      await Future<void>.delayed(Duration.zero);
      expect(clip, isNull);
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

    test(
        'confirmPin success persists the peer on the requester side so a '
        'phone-initiated pairing survives a restart (T-X1)', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final deviceList = DeviceListModel(prefs,
          deviceName: 'Test Phone', pairableEnabled: false);
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      expect(await pairing.confirmPin(pin), isTrue);

      // Persisted immediately, with the identity data discovery provided.
      final row =
          deviceList.knownDevices().singleWhere((d) => d.deviceId == 'desk-1');
      expect(row.deviceName, 'Desk');
      expect(row.platform, 'PLATFORM_LINUX_X11');

      // "Restart": a fresh DeviceListModel over the same prefs still has
      // the peer in its paired roster (the pre-fix behavior lost it here).
      final reloaded = DeviceListModel(prefs,
          deviceName: 'Test Phone', pairableEnabled: false);
      addTearDown(reloaded.dispose);
      final restored =
          reloaded.knownDevices().singleWhere((d) => d.deviceId == 'desk-1');
      expect(restored.deviceName, 'Desk');
      expect(restored.platform, 'PLATFORM_LINUX_X11');
      expect(reloaded.devices.map((d) => d.deviceId), contains('desk-1'));
    });

    test(
        'confirmPin success pins the observed TLS fingerprint, and the pin '
        'survives a restart (requester-side TOFU, T-X2)', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final deviceList = DeviceListModel(prefs,
          deviceName: 'Test Phone', pairableEnabled: false);
      final pairing = buildPairing(deviceList);
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      expect(await pairing.confirmPin(pin), isTrue);

      // The post-confirm pin attempt now lands (pre-fix it silently
      // no-opped because the peer was never in the paired store).
      final pinned = deviceList.pinnedFingerprint('desk-1');
      expect(pinned, isNotNull);

      final reloaded = DeviceListModel(prefs,
          deviceName: 'Test Phone', pairableEnabled: false);
      addTearDown(reloaded.dispose);
      expect(reloaded.pinnedFingerprint('desk-1'), pinned);
    });

    test(
        'a desktop push is accepted after a phone-initiated pair: '
        'prepareUpload passes the paired gate and an inbound clipboard '
        'frame is dispatched (T-X3)', () async {
      final r = await startResponder();
      addTearDown(() => r.server.stop());

      final deviceList = await buildDeviceList();
      pb.ClipboardData? clip;
      final pairing = PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (c) => clip = c,
        onPrepareUpload: (req) async => pb.PrepareUploadResponse(
          sessionId: req.sessionId,
          offers: [
            for (final f in req.files)
              pb.UploadFileOffer(fileId: f.fileId, accepted: true),
          ],
        ),
        pairableEnabled: false,
        ownIdentityLoader: () async => ownIdentity,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      pb.PrepareUploadRequest pushFrom(String senderId) =>
          pb.PrepareUploadRequest(
            sender: pb.Identity(deviceId: senderId),
            sessionId: 'sess-push',
            files: [
              pb.UploadFileMeta(
                fileId: 'file-push',
                fileName: 'push.bin',
                fileSizeBytes: Int64(3),
              ),
            ],
          );

      // Before pairing the gate rejects the (not yet paired) desktop.
      await expectLater(
          pairing.prepareUpload(pushFrom('desk-1')), throwsA(isA<GrpcError>()));

      await pairing.startPair(deviceFor(r.port));
      final pin = r.pairingManager.peekPin(pairing.localIdentity.deviceId)!;
      expect(await pairing.confirmPin(pin), isTrue);

      // After the phone-initiated pair the same push is accepted...
      final resp = await pairing.prepareUpload(pushFrom('desk-1'));
      expect(resp.offers.single.accepted, isTrue);

      // ...an unpaired stranger is still rejected...
      await expectLater(pairing.prepareUpload(pushFrom('stranger')),
          throwsA(isA<GrpcError>()));

      // ...and an inbound SyncStream clipboard frame from the paired peer
      // is dispatched instead of dropped.
      final inbound = StreamController<pb.SyncFrame>();
      final sub = pairing.onInboundSyncStream(inbound.stream).listen((_) {});
      addTearDown(() {
        sub.cancel();
        inbound.close();
      });
      inbound.add(pb.SyncFrame(identity: pb.Identity(deviceId: 'desk-1')));
      inbound.add(
          pb.SyncFrame(clipboard: pb.ClipboardData(content: 'push'.codeUnits)));
      await Future<void>.delayed(Duration.zero);
      expect(clip?.content, 'push'.codeUnits);
    });
  });

  group('PairingModel - receiving-role foreground service (T-X36)', () {
    test(
        'setPairableEnabled(true) starts the receiving service with the '
        'given strings; setPairableEnabled(false) stops it', () async {
      final deviceList = await buildDeviceList();
      final receiving = _FakeReceivingService();
      final pairing = PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        pairableEnabled: false,
        ownIdentityLoader: () async => ownIdentity,
        receivingService: receiving,
        serverPort: 0,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      expect(receiving.startCalls, isEmpty);

      await pairing.setPairableEnabled(true,
          notifTitle: 'Discoverable', notifText: 'Other devices can find this phone.');

      expect(receiving.startCalls, [
        ('Discoverable', 'Other devices can find this phone.'),
      ]);
      expect(receiving.stopCalls, 0);

      await pairing.setPairableEnabled(false);

      expect(receiving.stopCalls, 1);
    });

    test(
        'falls back to English defaults when no notification strings are '
        'given', () async {
      final deviceList = await buildDeviceList();
      final receiving = _FakeReceivingService();
      final pairing = PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        pairableEnabled: false,
        ownIdentityLoader: () async => ownIdentity,
        receivingService: receiving,
        serverPort: 0,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      await pairing.setPairableEnabled(true);

      expect(receiving.startCalls, [
        ('Discoverable', 'Other devices can find this phone and send it files.'),
      ]);
    });

    test(
        'refreshReceivingNotification re-posts with fresh strings only '
        'while the server is running', () async {
      final deviceList = await buildDeviceList();
      final receiving = _FakeReceivingService();
      final pairing = PairingModel(
        deviceList: deviceList,
        onClipboardFrame: (_) {},
        pairableEnabled: false,
        ownIdentityLoader: () async => ownIdentity,
        receivingService: receiving,
        serverPort: 0,
      );
      addTearDown(() {
        pairing.dispose();
        deviceList.dispose();
      });

      // Not running yet -- a no-op.
      pairing.refreshReceivingNotification('Keşfedilebilir', 'Metin');
      expect(receiving.startCalls, isEmpty);

      await pairing.setPairableEnabled(true,
          notifTitle: 'Discoverable', notifText: 'English text');
      expect(receiving.startCalls.length, 1);

      // Now running -- catches the notification up to the new strings.
      pairing.refreshReceivingNotification('Keşfedilebilir', 'Metin');
      expect(receiving.startCalls, [
        ('Discoverable', 'English text'),
        ('Keşfedilebilir', 'Metin'),
      ]);
    });
  });
}

/// Records every start/stop call instead of touching a real platform
/// channel (T-X36) -- mirrors the fake-injection pattern already used for
/// `ownIdentityLoader` in this same file.
class _FakeReceivingService implements ReceivingService {
  final startCalls = <(String, String)>[];
  var stopCalls = 0;

  @override
  Future<void> start(String title, String text) async {
    startCalls.add((title, text));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
