import 'package:connectible_mobile/src/services/notification_listener.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The T-B4 acceptance: the native listener surfaces posted/removed
/// callbacks and the grant state, decoded by [PlatformNotificationListener]
/// into typed Dart.
///
/// The Kotlin `NotificationPlugin` emits a fixed map shape over its event
/// channel; these tests pin down the contract the decoders must satisfy
/// against that exact shape. A change in the map keys or the type values is
/// a regression in the native contract. The non-Android short-circuit and
/// the PlatformException->notGranted fallback are exercised too.
void main() {
  group('decodeNotificationEvent', () {
    test('decodes a posted notification', () {
      final event = decodeNotificationEvent({
        'type': 'posted',
        'notification_id': 'com.example.app#tag#7',
        'package_name': 'com.example.app',
        'app_name': 'Example',
        'title': 'Hello',
        'body': 'World',
        'posted_at_ms': 1700000000000,
        'is_dismissal': false,
      });
      expect(event.id, 'com.example.app#tag#7');
      expect(event.packageName, 'com.example.app');
      expect(event.appName, 'Example');
      expect(event.title, 'Hello');
      expect(event.body, 'World');
      expect(event.postedAtMs, 1700000000000);
      expect(event.isRemoval, isFalse);
    });

    test('decodes a removal as a dismissal', () {
      final event = decodeNotificationEvent({
        'type': 'removed',
        'notification_id': 'com.example.app##7',
        'package_name': 'com.example.app',
        'app_name': 'Example',
        'title': '',
        'body': '',
        'posted_at_ms': 0,
      });
      expect(event.isRemoval, isTrue);
      expect(event.id, 'com.example.app##7');
    });

    test('tolerates a num posted_at_ms (JS-interop crossing)', () {
      final event = decodeNotificationEvent({
        'type': 'posted',
        'notification_id': 'k',
        'package_name': '',
        'app_name': '',
        'title': '',
        'body': '',
        // Some platform channels deliver this as a double.
        'posted_at_ms': 1700000000000.0,
      });
      expect(event.postedAtMs, 1700000000000);
    });

    test('tolerates missing fields with empty/zero defaults', () {
      final event = decodeNotificationEvent({
        'type': 'posted',
        'notification_id': 'k',
      });
      expect(event.title, isEmpty);
      expect(event.body, isEmpty);
      expect(event.appName, isEmpty);
      expect(event.postedAtMs, 0);
      expect(event.isRemoval, isFalse);
    });
  });

  group('isNotificationPayload', () {
    test('true for posted and removed', () {
      expect(isNotificationPayload({'type': 'posted'}), isTrue);
      expect(isNotificationPayload({'type': 'removed'}), isTrue);
    });

    test('false for lifecycle signals and junk', () {
      expect(isNotificationPayload({'type': 'connected'}), isFalse);
      expect(isNotificationPayload({'type': 'disconnected'}), isFalse);
      expect(isNotificationPayload(null), isFalse);
      expect(isNotificationPayload('not-a-map'), isFalse);
    });
  });

  group('decodeLifecycle', () {
    test('granted when type == connected', () {
      expect(decodeLifecycle({'type': 'connected'}).granted, isTrue);
    });

    test('not granted for disconnected or anything else', () {
      expect(decodeLifecycle({'type': 'disconnected'}).granted, isFalse);
      expect(decodeLifecycle(null).granted, isFalse);
      expect(decodeLifecycle({}).granted, isFalse);
    });
  });

  group('decodeAccessState', () {
    test('true -> granted', () {
      expect(decodeAccessState(true), NotificationAccessState.granted);
    });

    test('false -> notGranted', () {
      expect(decodeAccessState(false), NotificationAccessState.notGranted);
    });
  });

  group('PlatformNotificationListener (non-android host)', () {
    // `flutter_test` reports `defaultTargetPlatform == android` by default,
    // so to exercise the off-Android no-op guard we must override the
    // reported platform; otherwise the production paths hit real platform
    // channels (which have no handler under test and hang). This both
    // verifies the platform guard and documents that notification mirroring
    // is Android-only.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('accessState is notGranted off-Android', () async {
      const listener = PlatformNotificationListener();
      expect(await listener.accessState, NotificationAccessState.notGranted);
    });

    test('openAccessSettings returns false off-Android', () async {
      const listener = PlatformNotificationListener();
      expect(await listener.openAccessSettings(), isFalse);
    });

    test('events stream is empty off-Android', () async {
      const listener = PlatformNotificationListener();
      expect(await listener.events.isEmpty, isTrue);
    });

    test('lifecycle stream is empty off-Android', () async {
      const listener = PlatformNotificationListener();
      expect(await listener.lifecycle.isEmpty, isTrue);
    });
  });
}
