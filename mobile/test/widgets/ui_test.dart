import 'package:connectible_mobile/src/i18n/strings.dart';
import 'package:connectible_mobile/src/widgets/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('displayDeviceName (T-X32)', () {
    test('passes a non-empty name through unchanged', () {
      expect(displayDeviceName('Pixel', const AppStrings(AppLocale.en)),
          'Pixel');
    });

    test('falls back to the localized placeholder for an empty name', () {
      expect(displayDeviceName('', const AppStrings(AppLocale.en)),
          'Unknown device');
      expect(displayDeviceName('', const AppStrings(AppLocale.tr)),
          'Bilinmeyen cihaz');
    });
  });
}
