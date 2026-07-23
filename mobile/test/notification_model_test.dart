import 'dart:async';

import 'package:connectible_mobile/src/generated/connectible.pbgrpc.dart'
    as pb;
import 'package:connectible_mobile/src/services/notification_listener.dart';
import 'package:connectible_mobile/src/state/notification_model.dart';
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

  List<pb.NotificationData> get notifications => sent
      .where((f) => f.whichPayload() == pb.SyncFrame_Payload.notification)
      .map((f) => f.notification)
      .toList();
}

/// Injectable listener the model consumes; drive events/lifecycle by hand.
class _FakeListener implements NotificationListener {
  NotificationAccessState initialAccess = NotificationAccessState.notGranted;
  final lifecycleController =
      StreamController<NotificationLifecycle>.broadcast();
  final eventsController = StreamController<NotificationEvent>.broadcast();
  int openSettingsCalls = 0;
  final cancelCalls = <String>[];
  bool cancelResult = true;

  @override
  Future<NotificationAccessState> get accessState async => initialAccess;

  @override
  Future<bool> openAccessSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<bool> cancel(String notificationId) async {
    cancelCalls.add(notificationId);
    return cancelResult;
  }

  @override
  Stream<NotificationLifecycle> get lifecycle => lifecycleController.stream;

  @override
  Stream<NotificationEvent> get events => eventsController.stream;

  Future<void> dispose() async {
    await lifecycleController.close();
    await eventsController.close();
  }
}

NotificationEvent _event({
  required String id,
  String title = 'Title',
  String body = 'Body',
  bool isRemoval = false,
}) =>
    NotificationEvent(
      id: id,
      packageName: 'com.example',
      appName: 'Example',
      title: title,
      body: body,
      postedAtMs: 1000,
      isRemoval: isRemoval,
    );

void main() {
  test('forwards a posted notification as a NotificationData frame',
      () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    listener.eventsController.add(_event(id: 'a', title: 'Hi', body: 'There'));
    await Future<void>.delayed(Duration.zero);

    expect(connection.notifications, hasLength(1));
    final data = connection.notifications.single;
    expect(data.notificationId, 'a');
    expect(data.appName, 'Example');
    expect(data.title, 'Hi');
    expect(data.body, 'There');
    expect(data.isDismissal, isFalse);
    expect(data.postedAtMs.toInt(), 1000);
  });

  test('does not forward while disconnected', () async {
    final connection = _FakeConnection()..connected = false;
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    listener.eventsController.add(_event(id: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(connection.sent, isEmpty);
  });

  test('a dismissal is forwarded only for a previously posted notification',
      () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    // Removal for an unknown id -> ignored (noise suppression).
    listener.eventsController.add(_event(id: 'ghost', isRemoval: true));
    await Future<void>.delayed(Duration.zero);
    expect(connection.notifications, isEmpty);

    // Post then remove -> exactly one dismissal, with empty content.
    listener.eventsController.add(_event(id: 'x', title: 'Msg'));
    await Future<void>.delayed(Duration.zero);
    listener.eventsController.add(_event(id: 'x', isRemoval: true));
    await Future<void>.delayed(Duration.zero);

    final frames = connection.notifications;
    expect(frames, hasLength(2));
    expect(frames.first.isDismissal, isFalse);
    expect(frames.last.isDismissal, isTrue);
    expect(frames.last.notificationId, 'x');
    expect(frames.last.title, isEmpty);
    expect(frames.last.body, isEmpty);
  });

  test('tracks grant state from the lifecycle stream and notifies',
      () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    var notified = 0;
    model.addListener(() => notified++);

    expect(model.granted, isFalse);

    listener.lifecycleController.add(const NotificationLifecycle(granted: true));
    await Future<void>.delayed(Duration.zero);
    expect(model.granted, isTrue);
    expect(notified, greaterThanOrEqualTo(1));

    // A revoke flips it back.
    listener.lifecycleController
        .add(const NotificationLifecycle(granted: false));
    await Future<void>.delayed(Duration.zero);
    expect(model.granted, isFalse);
  });

  test('openAccessSettings delegates to the listener', () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    final ok = await model.openAccessSettings();
    expect(ok, isTrue);
    expect(listener.openSettingsCalls, 1);
  });

  test(
      'handleInbound cancels the matching live notification for a dismiss '
      'frame (T-K4)', () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    model.handleInbound(
        pb.NotificationData(notificationId: 'peer-said-dismiss', isDismissal: true));
    await Future<void>.delayed(Duration.zero);

    expect(listener.cancelCalls, ['peer-said-dismiss']);
  });

  test('handleInbound ignores a non-dismissal frame (mobile never receives '
      'a new notification to post)', () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    model.handleInbound(pb.NotificationData(
        notificationId: 'x', title: 'Should be ignored', isDismissal: false));
    await Future<void>.delayed(Duration.zero);

    expect(listener.cancelCalls, isEmpty);
  });

  test(
      "canceling a notification in response to an inbound dismiss doesn't "
      're-send it as a new outbound dismissal (T-K7 echo guard)', () async {
    final connection = _FakeConnection();
    final listener = _FakeListener();
    final model =
        NotificationModel(connection: connection, listener: listener);
    addTearDown(() async {
      model.dispose();
      await listener.dispose();
    });

    // A real notification this device posted and forwarded earlier.
    listener.eventsController.add(_event(id: 'x', title: 'Msg'));
    await Future<void>.delayed(Duration.zero);
    connection.sent.clear();

    // The peer dismissed it; we cancel our own copy...
    model.handleInbound(pb.NotificationData(notificationId: 'x', isDismissal: true));
    await Future<void>.delayed(Duration.zero);
    expect(listener.cancelCalls, ['x']);

    // ...which fires the OS's own removal callback, same as a real
    // cancelNotification() call would. Must not bounce back out.
    listener.eventsController.add(_event(id: 'x', isRemoval: true));
    await Future<void>.delayed(Duration.zero);
    expect(connection.notifications, isEmpty,
        reason: 'the echoed removal must not be re-sent as a fresh dismissal');

    // A *genuine* later removal of a different, unrelated id still sends
    // normally -- the guard is per-id and one-shot, not a global switch.
    listener.eventsController.add(_event(id: 'y', title: 'Other'));
    await Future<void>.delayed(Duration.zero);
    listener.eventsController.add(_event(id: 'y', isRemoval: true));
    await Future<void>.delayed(Duration.zero);
    expect(connection.notifications.where((n) => n.notificationId == 'y'),
        hasLength(2));
  });
}
