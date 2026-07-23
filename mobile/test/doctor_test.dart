import 'dart:async';

import 'package:connectible_mobile/src/services/doctor/checks.dart';
import 'package:connectible_mobile/src/services/doctor/doctor.dart';
import 'package:connectible_mobile/src/services/notification_listener.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial check that returns a fixed status, for engine tests.
class _Fixed extends DoctorCheck {
  _Fixed(this._id, this._status);
  final String _id;
  final DoctorStatus _status;
  @override
  String get id => _id;
  @override
  String get title => _id;
  @override
  DoctorCategory get category => DoctorCategory.connectivity;
  @override
  Future<DoctorCheckResult> run() async => DoctorCheckResult(
        id: _id,
        title: _id,
        category: category,
        status: _status,
        summary: _status.name,
      );
}

/// A check whose `run` throws, to exercise the runner's error containment.
class _Throwing extends DoctorCheck {
  @override
  String get id => 'boom';
  @override
  String get title => 'Boom';
  @override
  DoctorCategory get category => DoctorCategory.connectivity;
  @override
  Future<DoctorCheckResult> run() async => throw StateError('nope');
}

/// Injectable notification listener with a settable access state.
class _FakeListener implements NotificationListener {
  _FakeListener(this._state);
  final NotificationAccessState _state;
  int openCalls = 0;

  @override
  Future<NotificationAccessState> get accessState async => _state;
  @override
  Future<bool> openAccessSettings() async {
    openCalls++;
    return true;
  }

  @override
  Stream<NotificationLifecycle> get lifecycle => const Stream.empty();
  @override
  Stream<NotificationEvent> get events => const Stream.empty();
  @override
  Future<bool> cancel(String notificationId) async => false;
}

void main() {
  group('worstStatus', () {
    test('picks the highest severity', () {
      expect(worstStatus([DoctorStatus.ok, DoctorStatus.ok]), DoctorStatus.ok);
      expect(
        worstStatus([DoctorStatus.ok, DoctorStatus.warn]),
        DoctorStatus.warn,
      );
      expect(
        worstStatus([DoctorStatus.warn, DoctorStatus.error, DoctorStatus.ok]),
        DoctorStatus.error,
      );
      expect(worstStatus(const <DoctorStatus>[]), DoctorStatus.ok);
    });
  });

  group('DoctorRunner', () {
    test('runAll rolls up the worst status', () async {
      final runner = DoctorRunner([
        _Fixed('a', DoctorStatus.ok),
        _Fixed('b', DoctorStatus.warn),
        _Fixed('c', DoctorStatus.error),
      ]);
      final report = await runner.runAll();
      expect(report.checks, hasLength(3));
      expect(report.worst, DoctorStatus.error);
    });

    test('runOne returns the matching check or null', () async {
      final runner = DoctorRunner([_Fixed('a', DoctorStatus.ok)]);
      expect((await runner.runOne('a'))?.status, DoctorStatus.ok);
      expect(await runner.runOne('missing'), isNull);
    });

    test('a throwing check is contained as an error result', () async {
      final runner = DoctorRunner([_Throwing()]);
      final report = await runner.runAll();
      expect(report.worst, DoctorStatus.error);
      expect(report.checks.single.status, DoctorStatus.error);
      expect(report.checks.single.detail, contains('nope'));
    });
  });

  group('NotificationPermissionCheck', () {
    test('granted -> ok with no action', () async {
      final check = NotificationPermissionCheck(
        notifications: _FakeListener(NotificationAccessState.granted),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.action, isNull);
    });

    test('not granted -> warn with a deep-link action', () async {
      final listener = _FakeListener(NotificationAccessState.notGranted);
      final check = NotificationPermissionCheck(notifications: listener);
      final result = await check.run();
      expect(result.status, DoctorStatus.warn);
      expect(result.action, isNotNull);
      await result.action!();
      expect(listener.openCalls, 1);
    });
  });

  group('informational permission/storage checks', () {
    test('clipboard + storage report ok, battery optimization warns', () async {
      expect((await ClipboardAccessCheck().run()).status, DoctorStatus.ok);
      expect((await StorageAccessCheck().run()).status, DoctorStatus.ok);
      expect(
        (await BatteryOptimizationCheck().run()).status,
        DoctorStatus.warn,
      );
    });
  });
}
