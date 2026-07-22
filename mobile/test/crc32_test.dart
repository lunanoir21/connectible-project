import 'dart:convert';

import 'package:connectible_mobile/src/services/crc32.dart';
import 'package:flutter_test/flutter_test.dart';

// CRC32 (IEEE, reflected) must match Rust's crc32fast on the daemon, or
// every chunk is rejected. These are the canonical published vectors.
void main() {
  group('Crc32.compute', () {
    test('empty input is 0', () {
      expect(Crc32.compute(const []), 0);
    });

    test('"123456789" matches the standard check value 0xCBF43926', () {
      expect(Crc32.compute(utf8.encode('123456789')), 0xCBF43926);
    });

    test('classic pangram vector', () {
      expect(
        Crc32.compute(utf8.encode('The quick brown fox jumps over the lazy dog')),
        0x414FA339,
      );
    });

    test('single zero byte', () {
      expect(Crc32.compute(const [0]), 0xD202EF8D);
    });

    test('result always fits in 32 bits', () {
      final crc = Crc32.compute(List<int>.generate(1000, (i) => (i * 37) & 0xFF));
      expect(crc, inInclusiveRange(0, 0xFFFFFFFF));
    });
  });
}
