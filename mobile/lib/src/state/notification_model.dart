import 'dart:async';
import 'dart:collection';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

import '../generated/connectible.pbgrpc.dart' as pb;
import '../services/notification_listener.dart';
import 'sync_connection.dart';

/// Mirrors this phone's system notifications to the paired peer
/// (Phase B / T-B5-B7).
///
/// The wire format (`NotificationData`) and the daemon+desktop display
/// pipeline already existed; the mobile client never sent anything (the
/// `notifications` capability was dropped and there was no listener). This
/// closes that gap on top of the native [NotificationListener] scaffold
/// (T-B4):
///
///  - it tracks the system "Notification access" grant state (surfaced to
///    the Settings UI, T-B5) from the listener's lifecycle stream, and
///    exposes [openAccessSettings] to deep-link the user into granting or
///    revoking it;
///  - once access is granted, it forwards each posted/updated notification
///    as a `NotificationData` frame (T-B6), and each dismissal as an
///    `is_dismissal` frame (T-B7) -- but only while connected to a peer.
///
/// Forwarding is best-effort by design: a missing peer, a dropped session,
/// or a listener error must never crash the app or grow memory unbounded.
class NotificationModel extends ChangeNotifier {
  NotificationModel({
    required SyncConnection connection,
    NotificationListener listener = const PlatformNotificationListener(),
  })  : _connection = connection,
        _listener = listener {
    _lifecycleSub = _listener.lifecycle.listen(_onLifecycle);
    _eventsSub = _listener.events.listen(_onEvent);
    // Seed the grant state so the UI reflects reality before the first
    // lifecycle tick (which the platform emits on listen anyway, but a
    // direct query avoids a visible flip on cold start).
    unawaited(_refreshAccess());
  }

  final SyncConnection _connection;
  final NotificationListener _listener;
  StreamSubscription<NotificationLifecycle>? _lifecycleSub;
  StreamSubscription<NotificationEvent>? _eventsSub;

  NotificationAccessState _access = NotificationAccessState.notGranted;

  /// Whether the user has granted system "Notification access" and the
  /// native listener is bound. Drives the Settings opt-in row (T-B5).
  NotificationAccessState get access => _access;
  bool get granted => _access == NotificationAccessState.granted;

  /// The notification ids we have forwarded a *post* for, so a later
  /// dismissal is only relayed for something the peer actually saw (a
  /// dismissal for an unknown id is noise). Bounded so a notification
  /// flood can never grow it without limit (RULES.md); insertion order is
  /// preserved so we evict the oldest.
  final LinkedHashSet<String> _forwarded = LinkedHashSet<String>();
  static const _maxForwarded = 512;

  /// Ids we just told the OS to cancel ourselves, in response to an
  /// inbound dismiss from the peer (T-K4/T-K7 echo guard): canceling a
  /// live notification fires [NotificationListener.events]' removal
  /// event again, indistinguishable on its own from the user swiping it
  /// away -- without this, that echo would be re-sent as a *new*
  /// outbound dismissal, bouncing the same one back and forth. Same cap/
  /// eviction shape as [_forwarded] for the same reason (RULES.md).
  final LinkedHashSet<String> _suppressNextRemoval = LinkedHashSet<String>();

  Future<void> _refreshAccess() async {
    final state = await _listener.accessState;
    _setAccess(state);
  }

  void _onLifecycle(NotificationLifecycle lifecycle) {
    _setAccess(lifecycle.granted
        ? NotificationAccessState.granted
        : NotificationAccessState.notGranted);
  }

  void _setAccess(NotificationAccessState state) {
    if (state == _access) return;
    _access = state;
    // A revoke invalidates every outstanding post: drop the sets so a
    // later re-grant starts clean rather than emitting stale dismissals
    // or misreading a fresh post's removal as one of ours.
    if (state == NotificationAccessState.notGranted) {
      _forwarded.clear();
      _suppressNextRemoval.clear();
    }
    notifyListeners();
  }

  void _onEvent(NotificationEvent event) {
    if (!_connection.connected) return;

    if (event.isRemoval) {
      if (_suppressNextRemoval.remove(event.id)) {
        // Our own handleInbound()-triggered cancel() -- already synced
        // from the peer's side, must not bounce back (T-K7).
        _forwarded.remove(event.id);
        return;
      }
      // Only relay a dismissal for a post the peer actually received.
      if (!_forwarded.remove(event.id)) return;
      _send(event, dismissal: true);
      return;
    }

    _remember(event.id);
    _send(event, dismissal: false);
  }

  /// Applies an inbound `NotificationData` frame from the paired peer
  /// (T-K4): the only meaningful direction is a dismissal -- mobile never
  /// receives a brand-new notification to *post* from the desktop side,
  /// only a command to clear one it already forwarded. Best-effort: a
  /// notification that's already gone (dismissed locally, listener
  /// rebound since) is not an error, just a no-op.
  void handleInbound(pb.NotificationData data) {
    if (!data.isDismissal) return;
    _rememberSuppressed(data.notificationId);
    unawaited(_listener.cancel(data.notificationId));
  }

  void _remember(String id) {
    // Re-inserting refreshes recency; cap by evicting the oldest.
    _forwarded.remove(id);
    _forwarded.add(id);
    while (_forwarded.length > _maxForwarded) {
      _forwarded.remove(_forwarded.first);
    }
  }

  void _rememberSuppressed(String id) {
    _suppressNextRemoval.remove(id);
    _suppressNextRemoval.add(id);
    while (_suppressNextRemoval.length > _maxForwarded) {
      _suppressNextRemoval.remove(_suppressNextRemoval.first);
    }
  }

  void _send(NotificationEvent event, {required bool dismissal}) {
    _connection.sendFrame(pb.SyncFrame(
      notification: pb.NotificationData(
        notificationId: event.id,
        appName: event.appName,
        // A dismissal carries no user-visible content by contract; leave
        // title/body empty so we never re-send text on a clear.
        title: dismissal ? '' : event.title,
        body: dismissal ? '' : event.body,
        postedAtMs: Int64(event.postedAtMs),
        isDismissal: dismissal,
      ),
    ));
  }

  /// Deep-links to the system Notification-access settings so the user can
  /// grant or revoke access. Returns false if the page is unavailable on
  /// this ROM (the caller can fall back to generic settings).
  Future<bool> openAccessSettings() => _listener.openAccessSettings();

  @override
  void dispose() {
    unawaited(_lifecycleSub?.cancel());
    unawaited(_eventsSub?.cancel());
    super.dispose();
  }
}
