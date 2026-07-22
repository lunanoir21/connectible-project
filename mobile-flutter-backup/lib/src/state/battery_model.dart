import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../generated/connectible.pbgrpc.dart' as pb;
import 'sync_connection.dart';

/// One battery reading: level 0-100 and whether it is charging. A typedef
/// (not a hard `battery_plus` dependency in the model's logic) so tests
/// can inject a fake snapshot without a platform channel.
typedef BatterySnapshot = ({int percentage, bool charging});
typedef BatteryReader = Future<BatterySnapshot> Function();

/// Reports this phone's battery to the paired peer (Phase B / T-B1-B3).
///
/// The wire format (`BatteryStatus`) and the daemon+desktop display
/// pipeline already existed; the mobile client just never sent anything
/// (the `battery` capability was dropped). This closes that gap: it polls
/// on an interval and on every battery-state change, and pushes a
/// `BatteryStatus` frame onto the active session -- but only while
/// connected (no peer means nothing to report to).
///
/// It deliberately never calls `notifyListeners`: the phone doesn't
/// display its own battery in-app, so this is a pure background sender.
/// (That also keeps it from ever preventing a widget test's
/// `pumpAndSettle` from settling.)
class BatteryModel extends ChangeNotifier {
  BatteryModel({
    required SyncConnection connection,
    BatteryReader? reader,
    Stream<void>? changes,
    Duration interval = const Duration(seconds: 60),
  })  : _connection = connection,
        _reader = reader ?? _defaultReader,
        _interval = interval {
    _changesSub = (changes ?? _defaultChanges()).listen((_) => report());
    _timer = Timer.periodic(_interval, (_) => report());
    // Kick off an initial reading so a freshly-connected peer sees the
    // battery promptly rather than waiting a whole interval.
    unawaited(report());
  }

  final SyncConnection _connection;
  final BatteryReader _reader;
  final Duration _interval;
  Timer? _timer;
  StreamSubscription<void>? _changesSub;

  /// Reads the battery and, if connected, pushes a `BatteryStatus` frame.
  /// A no-op while disconnected. Read failures are swallowed (a missing
  /// battery API must not crash sync).
  Future<void> report() async {
    if (!_connection.connected) return;
    BatterySnapshot snap;
    try {
      snap = await _reader();
    } catch (e) {
      debugPrint('battery read failed: $e');
      return;
    }
    _connection.sendFrame(pb.SyncFrame(
      batteryStatus: pb.BatteryStatus(
        percentage: snap.percentage,
        isCharging: snap.charging,
        // The platform API exposes no time-remaining estimate; -1 marks
        // it unknown for the desktop display.
        minutesRemaining: -1,
        reportedAtMs: Int64(DateTime.now().millisecondsSinceEpoch),
      ),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_changesSub?.cancel());
    super.dispose();
  }
}

Future<BatterySnapshot> _defaultReader() async {
  final battery = Battery();
  final level = await battery.batteryLevel;
  final state = await battery.batteryState;
  final charging =
      state == BatteryState.charging || state == BatteryState.full;
  return (percentage: level, charging: charging);
}

Stream<void> _defaultChanges() =>
    Battery().onBatteryStateChanged.map((_) {});
