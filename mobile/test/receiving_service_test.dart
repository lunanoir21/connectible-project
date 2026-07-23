import 'package:connectible_mobile/src/services/receiving_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformReceivingService (non-android host, T-X36)', () {
    // Same rationale as notification_listener_test.dart's off-Android
    // group: override the reported platform so start/stop take the no-op
    // guard instead of hitting a real platform channel with no handler
    // registered under test (which would hang/throw).
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('start is a no-op off-Android', () async {
      const service = PlatformReceivingService();
      await expectLater(service.start('title', 'text'), completes);
    });

    test('stop is a no-op off-Android', () async {
      const service = PlatformReceivingService();
      await expectLater(service.stop(), completes);
    });
  });
}
