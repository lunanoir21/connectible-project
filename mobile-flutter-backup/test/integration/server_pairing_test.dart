@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart' as pb;
import 'package:connectible_mobile/src/models/models.dart';
import 'package:connectible_mobile/src/services/connectible_server.dart';
import 'package:connectible_mobile/src/services/pairing_manager.dart';
import 'package:connectible_mobile/src/services/server_identity.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

/// Records delegate calls and provides the minimal surface the server needs.
class _FakeDelegate implements ServerDelegate {
  final List<pb.Identity> paired = [];

  @override
  pb.Identity get localIdentity => pb.Identity(
        deviceId: 'phone-1',
        deviceName: 'Test Phone',
        platform: pb.Platform.PLATFORM_ANDROID,
        protocolVersion: 1,
      );

  @override
  void onPeerPaired(pb.Identity requester) => paired.add(requester);

  @override
  List<DeviceInfo> knownDevices() => const [];

  @override
  Stream<pb.SyncFrame> onInboundSyncStream(Stream<pb.SyncFrame> inbound) {
    // Echo the peer's own identity back, then mirror nothing else.
    final out = StreamController<pb.SyncFrame>();
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
  // The Dart gRPC server terminates real TLS 1.3 with a self-signed cert
  // that this device generates itself; the desktop peer accepts any such
  // cert (AcceptSelfSignedCert). This drives that whole server path with a
  // gRPC client, so pairing works byte-for-byte the way a desktop would.
  late ServerIdentity identity;

  setUpAll(() {
    identity = ServerIdentity.generate();
  });

  test('cert generation yields a usable PEM cert + key', () {
    expect(identity.certPem, contains('BEGIN CERTIFICATE'));
    expect(identity.keyPem, contains('PRIVATE KEY'));
  });

  test('server credentials enforce a TLS 1.3 floor (T-401)', () {
    final creds = Tls13OnlyServerCredentials(
      certificate: identity.certBytes,
      privateKey: identity.keyBytes,
    );
    expect(
      creds.securityContext.minimumTlsProtocolVersion,
      TlsProtocolVersion.tls1_3,
    );
  });

  test('desktop-style peer pairs to the phone over real TLS', () async {
    final pairing = PairingManager();
    final delegate = _FakeDelegate();
    final server = ConnectibleServer(delegate, pairing);
    final port = await server.start(identity, port: 0);

    final channel = ClientChannel(
      'localhost',
      port: port,
      options: ChannelOptions(
        credentials:
            ChannelCredentials.secure(onBadCertificate: (_, __) => true),
      ),
    );
    final client = pb.ConnectibleClient(channel);

    // Ping.
    final pong = await client.ping(pb.PingRequest(sentAtMs: Int64(1)));
    expect(pong.sentAtMs.toInt(), 1);
    expect(pong.repliedAtMs.toInt(), greaterThan(0));

    // Pair: the peer (desktop) initiates; the phone generates a PIN.
    final requester = pb.Identity(
      deviceId: 'desk-1',
      deviceName: "Anil's PC",
      platform: pb.Platform.PLATFORM_LINUX_X11,
      protocolVersion: 1,
    );
    final resp = await client.pair(pb.PairRequest(requester: requester));
    expect(resp.accepted, isTrue);
    expect(resp.pinExpiresAtMs.toInt(), greaterThan(0));

    // Read the PIN the phone would display and submit it, as the desktop
    // user would after reading it off the phone screen.
    final pin = pairing.peekPin('desk-1');
    expect(pin, isNotNull);
    final confirm = await client
        .confirmPin(pb.ConfirmPinRequest(deviceId: 'desk-1', pinCode: pin!));
    expect(confirm.verified, isTrue);
    expect(delegate.paired.single.deviceId, 'desk-1');

    await channel.shutdown();
    await server.stop();
  });

  test('wrong PIN is rejected', () async {
    final pairing = PairingManager();
    final server = ConnectibleServer(_FakeDelegate(), pairing);
    final port = await server.start(identity, port: 0);

    final channel = ClientChannel(
      'localhost',
      port: port,
      options: ChannelOptions(
        credentials:
            ChannelCredentials.secure(onBadCertificate: (_, __) => true),
      ),
    );
    final client = pb.ConnectibleClient(channel);

    await client.pair(pb.PairRequest(
        requester: pb.Identity(deviceId: 'desk-2', deviceName: 'PC')));
    final confirm = await client.confirmPin(
        pb.ConfirmPinRequest(deviceId: 'desk-2', pinCode: '000000'));
    expect(confirm.verified, isFalse);

    await channel.shutdown();
    await server.stop();
  });
}
