import 'package:connectible_mobile/src/services/reconnect_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconnectBackoffSeconds', () {
    test('doubles each attempt then caps at 30s', () {
      expect(reconnectBackoffSeconds(0), 1);
      expect(reconnectBackoffSeconds(1), 2);
      expect(reconnectBackoffSeconds(2), 4);
      expect(reconnectBackoffSeconds(3), 8);
      expect(reconnectBackoffSeconds(4), 16);
      expect(reconnectBackoffSeconds(5), 30); // 32 clamped
      expect(reconnectBackoffSeconds(6), 30);
    });

    test('stays within [1, 30] for many attempts', () {
      for (var attempt = 0; attempt < 50; attempt++) {
        final delay = reconnectBackoffSeconds(attempt);
        expect(delay, inInclusiveRange(1, 30));
      }
    });
  });
}
