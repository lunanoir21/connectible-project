import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Best-effort bridge to the Android foreground service that keeps this
/// phone's inbound gRPC/TLS server + mDNS advertise + heartbeat alive under
/// Doze/OEM background kills while "receiving" (pairable) is enabled
/// (T-X36).
///
/// Injectable seam (mirrors [NotificationListener]/[SyncConnection]) so
/// [PairingModel] doesn't touch a platform channel directly and tests can
/// supply a fake. Every call is fire-and-forget: a failure here must never
/// block or fail the toggle itself, since the service is a reliability aid,
/// not a correctness requirement (see [ConnectibleServer]/mDNS advertise,
/// which work the same with or without it -- just less reliably in the
/// background).
abstract class ReceivingService {
  /// Starts (or updates, if already running) the foreground service with
  /// the given already-localized notification [title]/[text].
  Future<void> start(String title, String text);

  /// Stops the foreground service if running.
  Future<void> stop();
}

const _channel = MethodChannel('connectible/receiving_service');

/// Production [ReceivingService] backed by the native
/// `ReceivingForegroundService` (Android). On non-Android platforms every
/// call is a safe no-op.
class PlatformReceivingService implements ReceivingService {
  const PlatformReceivingService();

  @override
  Future<void> start(String title, String text) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start', {'title': title, 'text': text});
    } catch (e) {
      debugPrint('receiving service start failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('receiving service stop failed: $e');
    }
  }
}

bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
