import 'dart:async';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/state/battery_model.dart';
import 'package:connectible_mobile/src/state/sync_connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records outbound frames; drives the connected flag by hand.
class _FakeConnection implements SyncConnection {
  @override
  bool connected = true;
  @override
  String? get activePeerId => 'peer-1';
  @override
  pb.ConnectibleClient? get uploadClient => null;
  @override
  pb.Identity get localIdentity => pb.Identity(deviceId: 'this-device');
  final List<pb.SyncFrame> sent = [];
  @override
  void sendFrame(pb.SyncFrame frame) => sent.add(frame);

  List<pb.BatteryStatus> get batteryFrames => sent
      .where((f) => f.whichPayload() == pb.SyncFrame_Payload.batteryStatus)
      .map((f) => f.batteryStatus)
      .toList();
}

void main() {
  test('reports a BatteryStatus frame on construction when connected',
      () async {
    final connection = _FakeConnection();
    final model = BatteryModel(
      connection: connection,
      reader: () async => (percentage: 77, charging: true),
      changes: const Stream.empty(),
      interval: const Duration(hours: 1),
    );
    addTearDown(model.dispose);

    // The constructor kicks off an initial async report().
    await Future<void>.delayed(Duration.zero);

    expect(connection.batteryFrames, hasLength(1));
    final frame = connection.batteryFrames.single;
    expect(frame.percentage, 77);
    expect(frame.isCharging, isTrue);
    expect(frame.reportedAtMs.toInt(), greaterThan(0));
  });

  test('does not send anything while disconnected', () async {
    final connection = _FakeConnection()..connected = false;
    final model = BatteryModel(
      connection: connection,
      reader: () async => (percentage: 50, charging: false),
      changes: const Stream.empty(),
      interval: const Duration(hours: 1),
    );
    addTearDown(model.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(connection.sent, isEmpty);
  });

  test('a battery-state change triggers a fresh report', () async {
    final connection = _FakeConnection();
    final changes = StreamController<void>();
    var pct = 40;
    final model = BatteryModel(
      connection: connection,
      reader: () async => (percentage: pct, charging: false),
      changes: changes.stream,
      interval: const Duration(hours: 1),
    );
    addTearDown(() {
      model.dispose();
      changes.close();
    });

    await Future<void>.delayed(Duration.zero); // initial report -> 40
    pct = 41;
    changes.add(null); // state change -> new report
    await Future<void>.delayed(Duration.zero);

    final frames = connection.batteryFrames;
    expect(frames.length, greaterThanOrEqualTo(2));
    expect(frames.last.percentage, 41);
  });
}
