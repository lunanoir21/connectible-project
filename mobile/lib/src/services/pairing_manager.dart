import 'dart:async';
import 'dart:math';

import 'connectible_exception.dart';

/// Outcome of a [PairingManager.confirm] call.
enum PinResult { ok, invalid, timeout, noPending }

/// Emitted the moment a remote peer calls Pair, so the mobile UI can show
/// the responder PIN dialog with a live countdown. Mirrors the daemon's
/// `PairingRequestedEvent` (daemon/src/pairing/mod.rs). Carries the
/// plaintext PIN because the local user must read it aloud to the peer;
/// this event never leaves the device.
class PairingRequestedEvent {
  const PairingRequestedEvent({
    required this.requesterDeviceId,
    required this.requesterDeviceName,
    required this.pinCode,
    required this.pinExpiresAtMs,
  });

  final String requesterDeviceId;
  final String requesterDeviceName;
  final String pinCode;
  final int pinExpiresAtMs;
}

class _PendingPin {
  _PendingPin({
    required this.code,
    required this.requesterDeviceName,
    required this.expiresAtMs,
  });

  final String code; // 6 ASCII digits
  final String requesterDeviceName;
  final int expiresAtMs;
  int attempts = 0;
}

/// Responder-side pairing state: mirrors the Rust daemon's
/// `PairingManager` so the phone behaves identically when a desktop
/// initiates pairing to it. PINs live only for [pinTtl] and are never
/// persisted; they are purged on success, expiry, or lockout.
class PairingManager {
  /// [now] injects the current time as epoch milliseconds, defaulting to
  /// the real system clock; tests use it to deterministically advance
  /// past a PIN's expiry without a real 30-second sleep (T-109).
  PairingManager({Random? random, int Function()? now})
      : _random = random ?? Random.secure(),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const Duration pinTtl = Duration(seconds: 30);
  static const int maxAttempts = 3;

  /// T-403: minimum interval between two *fresh* PINs for the same
  /// requester, mirroring the daemon's `PAIR_COOLDOWN`
  /// (daemon/src/pairing/mod.rs) -- a peer that keeps calling Pair
  /// can't keep re-popping this phone's PIN dialog.
  static const Duration pairCooldown = Duration(seconds: 5);

  /// T-X22: caps the number of *distinct* requester device_ids this
  /// manager will track bookkeeping for at once, mirroring the daemon's
  /// own `MAX_TRACKED_DEVICES` (daemon/src/pairing/mod.rs). Without this,
  /// a flood of Pair calls each using a fresh, never-reused device_id
  /// bypasses [pairCooldown] (which only throttles *repeated* use of the
  /// *same* id) and grows `_pending`/`_lastCreatedMs` without bound. An
  /// already-tracked device_id is never blocked by this -- only a
  /// brand-new one past the cap is.
  static const int maxTrackedDevices = 256;

  final Random _random;
  final int Function() _now;
  final Map<String, _PendingPin> _pending = {};
  final Map<String, int> _lastCreatedMs = {};
  final StreamController<PairingRequestedEvent> _events =
      StreamController<PairingRequestedEvent>.broadcast();

  Stream<PairingRequestedEvent> get events => _events.stream;

  int _nowMs() => _now();

  /// Generates a cryptographically random 6-digit PIN for [requesterDeviceId]
  /// with a 30-second expiry and broadcasts a [PairingRequestedEvent].
  /// Returns the expiry timestamp (epoch ms).
  ///
  /// T-403: idempotent while a PIN is already pending for this
  /// requester (returns the existing expiry, no new PIN or event).
  /// Once a pending entry is cleared (lockout/expiry), a fresh PIN is
  /// subject to [pairCooldown] -- throws [RateLimitedException] if
  /// called again too soon.
  int createPending(String requesterDeviceId, String requesterDeviceName) {
    final now = _nowMs();

    final existing = _pending[requesterDeviceId];
    if (existing != null && now <= existing.expiresAtMs) {
      return existing.expiresAtMs;
    }

    final lastMs = _lastCreatedMs[requesterDeviceId];
    if (lastMs != null && now - lastMs < pairCooldown.inMilliseconds) {
      throw RateLimitedException(
          'pairing requests from $requesterDeviceId are throttled');
    } else if (lastMs == null && _lastCreatedMs.length >= maxTrackedDevices) {
      // T-X22: a brand-new device_id past the cap, mirroring the
      // daemon's identical guard -- an already-tracked id (the branch
      // above) is never blocked by this.
      throw const RateLimitedException(
          'too many distinct devices are mid-pairing right now');
    }
    _lastCreatedMs[requesterDeviceId] = now;

    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(_random.nextInt(10));
    }
    final code = buf.toString();
    final expiresAtMs = now + pinTtl.inMilliseconds;

    _pending[requesterDeviceId] = _PendingPin(
      code: code,
      requesterDeviceName: requesterDeviceName,
      expiresAtMs: expiresAtMs,
    );

    _events.add(PairingRequestedEvent(
      requesterDeviceId: requesterDeviceId,
      requesterDeviceName: requesterDeviceName,
      pinCode: code,
      pinExpiresAtMs: expiresAtMs,
    ));

    return expiresAtMs;
  }

  /// Verifies a submitted PIN in constant time. On expiry, wrong-PIN
  /// lockout (3 attempts), or success the pending entry is removed, so a
  /// fresh Pair call is required to retry.
  PinResult confirm(String deviceId, String submitted) {
    final entry = _pending[deviceId];
    if (entry == null) return PinResult.noPending;

    if (_nowMs() > entry.expiresAtMs) {
      _pending.remove(deviceId);
      return PinResult.timeout;
    }

    if (_constantTimeEquals(submitted, entry.code)) {
      _pending.remove(deviceId);
      // A successful pairing means the cooldown concern is moot for
      // this device_id -- clear it so a legitimate later re-pair
      // (e.g. after being forgotten) isn't throttled by a leftover
      // cooldown from this successful attempt.
      _lastCreatedMs.remove(deviceId);
      return PinResult.ok;
    }

    entry.attempts += 1;
    if (entry.attempts >= maxAttempts) {
      _pending.remove(deviceId);
      return PinResult.timeout;
    }
    return PinResult.invalid;
  }

  /// Visible for tests: the current PIN for a pending pairing, so an
  /// integration test can drive the full flow without a human.
  String? peekPin(String deviceId) => _pending[deviceId]?.code;

  void dispose() {
    _pending.clear();
    _events.close();
  }

  /// Length-independent, early-return-free comparison to avoid leaking
  /// PIN content via timing.
  static bool _constantTimeEquals(String a, String b) {
    final ab = a.codeUnits;
    final bb = b.codeUnits;
    var diff = ab.length ^ bb.length;
    final n = ab.length < bb.length ? ab.length : bb.length;
    for (var i = 0; i < n; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }
}
