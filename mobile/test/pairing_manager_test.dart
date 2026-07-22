import 'dart:math';

import 'package:connectible_mobile/src/services/connectible_exception.dart';
import 'package:connectible_mobile/src/services/pairing_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingManager (responder)', () {
    test('generated PIN is 6 ASCII digits', () {
      final m = PairingManager();
      m.createPending('dev-a', 'Desk');
      final pin = m.peekPin('dev-a');
      expect(pin, isNotNull);
      expect(pin!.length, 6);
      expect(RegExp(r'^\d{6}$').hasMatch(pin), isTrue);
    });

    test('correct PIN within window verifies and clears the pending entry', () {
      final m = PairingManager();
      m.createPending('dev-b', 'Desk');
      final pin = m.peekPin('dev-b')!;
      expect(m.confirm('dev-b', pin), PinResult.ok);
      // Entry cleared: a second confirm finds nothing.
      expect(m.confirm('dev-b', pin), PinResult.noPending);
    });

    test('three wrong attempts lock out (timeout-equivalent)', () {
      final m = PairingManager();
      m.createPending('dev-c', 'Desk');
      expect(m.confirm('dev-c', '000000'), PinResult.invalid);
      expect(m.confirm('dev-c', '000000'), PinResult.invalid);
      expect(m.confirm('dev-c', '000000'), PinResult.timeout);
      // Pending gone; correct PIN no longer helps.
      expect(m.confirm('dev-c', '123456'), PinResult.noPending);
    });

    test('confirm with no pending pairing is rejected', () {
      final m = PairingManager();
      expect(m.confirm('unknown', '123456'), PinResult.noPending);
    });

    test('expired PIN reports timeout', () {
      // Injected clock lets us deterministically advance past the PIN's
      // 30-second TTL and submit the *correct* PIN, proving expiry is
      // actually checked (and checked before the code comparison) rather
      // than happy-pathing through to PinResult.ok.
      var currentMs = 1000000;
      final m = PairingManager(random: Random(1), now: () => currentMs);
      m.createPending('dev-d', 'Desk');
      final pin = m.peekPin('dev-d')!;

      currentMs += PairingManager.pinTtl.inMilliseconds + 1;

      expect(m.confirm('dev-d', pin), PinResult.timeout);
      // Pending gone; a fresh confirm with the same PIN finds nothing.
      expect(m.confirm('dev-d', pin), PinResult.noPending);
    });

    test('PIN still verifies right up until the moment it expires', () {
      var currentMs = 1000000;
      final m = PairingManager(random: Random(1), now: () => currentMs);
      m.createPending('dev-d2', 'Desk');
      final pin = m.peekPin('dev-d2')!;

      // Exactly at the expiry boundary is still valid (confirm only
      // times out once now() is strictly greater than expiresAtMs).
      currentMs += PairingManager.pinTtl.inMilliseconds;

      expect(m.confirm('dev-d2', pin), PinResult.ok);
    });

    test('createPending broadcasts an event carrying the accepted PIN',
        () async {
      final m = PairingManager();
      final future = m.events.first;
      m.createPending('dev-e', 'Desk Peer');
      final event = await future;
      expect(event.requesterDeviceId, 'dev-e');
      expect(event.requesterDeviceName, 'Desk Peer');
      expect(event.pinCode.length, 6);
      expect(m.confirm('dev-e', event.pinCode), PinResult.ok);
    });

    test('repeated createPending while pending is idempotent (T-403)', () {
      final m = PairingManager();
      final first = m.createPending('dev-f', 'Desk');
      final pinBefore = m.peekPin('dev-f');
      final second = m.createPending('dev-f', 'Desk');
      final pinAfter = m.peekPin('dev-f');
      expect(second, first);
      expect(pinAfter, pinBefore);
    });

    test('fresh createPending after lockout is rate limited within cooldown '
        '(T-403)', () {
      final m = PairingManager();
      m.createPending('dev-g', 'Desk');
      m.confirm('dev-g', '000000');
      m.confirm('dev-g', '000000');
      m.confirm('dev-g', '000000'); // lockout clears pending
      expect(
        () => m.createPending('dev-g', 'Desk'),
        throwsA(isA<RateLimitedException>()),
      );
    });

    test('createPending after a successful pair is not rate limited '
        '(T-403)', () {
      final m = PairingManager();
      m.createPending('dev-h', 'Desk');
      final pin = m.peekPin('dev-h')!;
      m.confirm('dev-h', pin);
      // A successful pairing clears the cooldown, so an immediate
      // re-pair (e.g. after being forgotten) is not throttled.
      expect(() => m.createPending('dev-h', 'Desk'), returnsNormally);
    });
  });
}
