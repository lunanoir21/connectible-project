import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One notification event surfaced from the native listener (T-B4).
///
/// Mirrors the minimal subset of Android's `StatusBarNotification` the
/// desktop mirror needs. `id` is package+tag+id (stable across
/// post/update/remove), and `isRemoval` distinguishes a dismissal from a
/// post/update. Foreground-service and group-summary notifications are
/// filtered out native-side already, so this only ever carries real
/// user-visible notifications.
@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.body,
    required this.postedAtMs,
    required this.isRemoval,
  });

  /// `package#tag#id` -- stable key for correlating a later dismissal.
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String body;
  final int postedAtMs;
  final bool isRemoval;
}

/// Grant-state of the system "Notification access" permission.
enum NotificationAccessState {
  /// The user has not yet granted access (or has revoked it).
  notGranted,

  /// Access granted and the native listener is connected.
  granted,
}

/// Lifecycle + grant-state signals from the native listener.
///
/// The native side emits three kinds of events over the event channel:
/// `connected` (permission granted, listener bound), `disconnected`
/// (permission revoked or listener unbound), plus the per-notification
/// posted/removed payloads. This type represents the former two; the latter
/// are decoded to [NotificationEvent].
@immutable
class NotificationLifecycle {
  const NotificationLifecycle({required this.granted});
  final bool granted;
}

/// Narrow native surface [NotificationModel] depends on, so unit tests can
/// inject a fake without touching platform channels. Mirrors the shape of
/// [SyncConnection] / [BatteryReader]: injectable seam, no hard plugin deps
/// in the model logic.
abstract class NotificationListener {
  /// Whether the user has granted system "Notification access" and the
  /// native service is currently connected.
  Future<NotificationAccessState> get accessState;

  /// Best-effort deep link to the system Notification-access settings.
  /// Falls back to this app's general settings page (T-X33) if that
  /// specific page doesn't resolve on this ROM, so the call always
  /// reaches *some* settings screen when one exists at all. Returns
  /// false only if neither resolved.
  Future<bool> openAccessSettings();

  /// Hot stream of grant/connect/disconnect lifecycle changes. Emits an
  /// initial state on listen so callers don't need a separate `accessState`
  /// round-trip on startup.
  Stream<NotificationLifecycle> get lifecycle;

  /// Hot stream of notification events (post/update/remove). Emits nothing
  /// until access is granted and the listener is bound.
  Stream<NotificationEvent> get events;

  /// Best-effort: clears the live system notification matching
  /// [notificationId] (T-K4), in response to a dismiss command that
  /// arrived from the paired peer. Returns false (not an error) if the
  /// notification is no longer tracked (already dismissed locally,
  /// system restarted the listener, ...) -- the caller has nothing
  /// actionable to do either way.
  Future<bool> cancel(String notificationId);
}

const _methodChannel = MethodChannel('connectible/notifications');
const _eventChannel = EventChannel('connectible/notification_events');

/// Production [NotificationListener] backed by the native method + event
/// channels registered by `NotificationPlugin` (Android). On non-Android
/// platforms every call is a safe no-op / empty stream -- notification
/// mirroring is an Android-only feature.
class PlatformNotificationListener implements NotificationListener {
  const PlatformNotificationListener();

  @override
  Future<NotificationAccessState> get accessState async {
    if (!isAndroid) return NotificationAccessState.notGranted;
    return decodeAccessState(
      await _invokeBool('isGranted'),
    );
  }

  @override
  Future<bool> openAccessSettings() async {
    if (!isAndroid) return false;
    if (await _invokeBool('openSettings')) return true;
    // T-X33: some OEM ROMs lack the dedicated notification-access page;
    // fall back to this app's own general settings, where the user can
    // still find the permission manually.
    return _invokeBool('openAppSettings');
  }

  @override
  Stream<NotificationLifecycle> get lifecycle {
    if (!isAndroid) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .map((raw) => decodeLifecycle(raw as Object?))
        .handleError((_) {});
  }

  @override
  Stream<NotificationEvent> get events {
    if (!isAndroid) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((raw) => isNotificationPayload(raw as Object?))
        .map((raw) => decodeNotificationEvent(raw as Object?))
        .handleError((_) {});
  }

  @override
  Future<bool> cancel(String notificationId) async {
    if (!isAndroid) return false;
    return _invokeBool('cancel', {'notification_id': notificationId});
  }

  Future<bool> _invokeBool(String method, [Map<String, dynamic>? arguments]) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(method, arguments);
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}

bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

// ---------------------------------------------------------------------------
// Pure decoders. Kept top-level (not instance methods) so they can be unit-
// tested directly against the exact map shape the Kotlin side emits, without
// needing a live platform channel. This is the contract the native
// NotificationPlugin must satisfy.
// ---------------------------------------------------------------------------

/// The map key the native side writes to mark an event's kind.
const kNotificationEventType = 'type';
const _kTypePosted = 'posted';
const _kTypeRemoved = 'removed';
const _kTypeConnected = 'connected';

/// True if a raw event payload carries a notification (posted/removed)
/// rather than a lifecycle signal (connected/disconnected).
bool isNotificationPayload(Object? raw) {
  final map = _asMap(raw);
  if (map == null) return false;
  final type = map[kNotificationEventType];
  return type == _kTypePosted || type == _kTypeRemoved;
}

/// Decodes a posted/removed payload into a [NotificationEvent]. Throws if
/// the payload is a lifecycle signal -- gate with [isNotificationPayload].
NotificationEvent decodeNotificationEvent(Object? raw) {
  final map = _asMap(raw)!;
  return NotificationEvent(
    id: _asString(map['notification_id']),
    packageName: _asString(map['package_name']),
    appName: _asString(map['app_name']),
    title: _asString(map['title']),
    body: _asString(map['body']),
    postedAtMs: _asInt(map['posted_at_ms']),
    isRemoval: map[kNotificationEventType] == _kTypeRemoved,
  );
}

/// Decodes a connected/disconnected payload into a lifecycle signal.
NotificationLifecycle decodeLifecycle(Object? raw) {
  final map = _asMap(raw);
  return NotificationLifecycle(
    granted: map != null && map[kNotificationEventType] == _kTypeConnected,
  );
}

/// Maps the `isGranted` bool into the access-state enum.
NotificationAccessState decodeAccessState(bool granted) => granted
    ? NotificationAccessState.granted
    : NotificationAccessState.notGranted;

Map<String, Object?>? _asMap(Object? raw) {
  if (raw is Map) return raw.cast<String, Object?>();
  return null;
}

String _asString(Object? v) => v is String ? v : '';
int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return 0;
}
