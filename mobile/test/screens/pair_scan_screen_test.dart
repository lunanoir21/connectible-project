import 'package:connectible_mobile/src/screens/pair_scan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure unit tests for [ScannedPairingCode.tryParse] -- the parser for a
/// scanned `connectible://pair?...` QR payload (mirrors the desktop-side
/// encoder at desktop/src/lib/pairingCode.ts). This alone would have
/// caught the audit finding that a real-but-unparseable QR code was
/// silently dropped with no user feedback: a null return here is the
/// signal pair_scan_screen.dart's `_onDetect` uses to show that message.
void main() {
  group('ScannedPairingCode.tryParse', () {
    test('a valid full URI parses every field correctly', () {
      final code = ScannedPairingCode.tryParse(
        'connectible://pair?host=192.168.1.42&port=58231&pin=123456&id=desk-1&name=My+Desktop',
      );

      expect(code, isNotNull);
      expect(code!.host, '192.168.1.42');
      expect(code.port, 58231);
      expect(code.pin, '123456');
      expect(code.deviceId, 'desk-1');
      expect(code.deviceName, 'My Desktop');
    });

    test('name is optional and falls back to the host', () {
      final code = ScannedPairingCode.tryParse(
        'connectible://pair?host=192.168.1.42&port=58231&pin=123456&id=desk-1',
      );

      expect(code, isNotNull);
      expect(code!.deviceName, '192.168.1.42');
    });

    test('a non-connectible://pair URI returns null', () {
      expect(
        ScannedPairingCode.tryParse(
          'https://example.com/pair?host=h&port=1&pin=123456&id=x',
        ),
        isNull,
      );
      expect(
        ScannedPairingCode.tryParse(
          'connectible://other?host=h&port=1&pin=123456&id=x',
        ),
        isNull,
      );
      expect(ScannedPairingCode.tryParse('not a uri at all'), isNull);
      expect(ScannedPairingCode.tryParse(''), isNull);
    });

    test('missing a required param (host/port/pin/id) returns null', () {
      const base = 'connectible://pair?host=h&port=1&pin=123456&id=x';

      expect(
        ScannedPairingCode.tryParse(
            'connectible://pair?port=1&pin=123456&id=x'),
        isNull,
        reason: 'missing host',
      );
      expect(
        ScannedPairingCode.tryParse('connectible://pair?host=h&pin=123456&id=x'),
        isNull,
        reason: 'missing port',
      );
      expect(
        ScannedPairingCode.tryParse('connectible://pair?host=h&port=1&id=x'),
        isNull,
        reason: 'missing pin',
      );
      expect(
        ScannedPairingCode.tryParse(
            'connectible://pair?host=h&port=1&pin=123456'),
        isNull,
        reason: 'missing id',
      );
      // Sanity check: the fully-populated version of the same URI does
      // parse, so the above failures are really about the missing param.
      expect(ScannedPairingCode.tryParse(base), isNotNull);
    });

    test('a malformed port returns null', () {
      expect(
        ScannedPairingCode.tryParse(
            'connectible://pair?host=h&port=not-a-number&pin=123456&id=x'),
        isNull,
      );
      expect(
        ScannedPairingCode.tryParse('connectible://pair?host=h&port=&pin=123456&id=x'),
        isNull,
      );
    });

    test('a PIN that is not exactly 6 digits returns null', () {
      expect(
        ScannedPairingCode.tryParse(
            'connectible://pair?host=h&port=1&pin=12345&id=x'),
        isNull,
      );
      expect(
        ScannedPairingCode.tryParse(
            'connectible://pair?host=h&port=1&pin=1234567&id=x'),
        isNull,
      );
    });
  });
}
