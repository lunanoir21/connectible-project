import 'package:connectible_mobile/src/i18n/strings.dart';
import 'package:connectible_mobile/src/state/device_list_model.dart';
import 'package:connectible_mobile/src/theme/app_theme.dart';
import 'package:connectible_mobile/src/widgets/pairing_sheet.dart';
import 'package:connectible_mobile/src/widgets/responder_pairing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] with the palette/strings scopes the sheets read via
/// `context.palette`/`context.strings`, following the same
/// MaterialApp.builder pattern widget_test.dart's "modal route can read
/// context.palette" test uses (the scopes must sit above the sheet, not
/// as `home` itself, since a real `.show()` would push it as a sibling
/// route -- but wrapping it directly as `home` content here is enough to
/// drive its own build()/AnimationController without a Navigator).
Widget _scoped(Widget child) {
  return MaterialApp(
    builder: (context, navigatorChild) => AppPaletteScope(
      palette: AppPalette.charcoal,
      child: AppStringsScope(
        strings: const AppStrings(AppLocale.en),
        child: navigatorChild ?? const SizedBox.shrink(),
      ),
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PIN countdown urgency (T-703)', () {
    testWidgets(
        'PairingSheet: countdown label stays neutral, then shifts to '
        'the danger color once <=10s remain', (tester) async {
      final expiresAt = DateTime.now().millisecondsSinceEpoch + 20000;

      await tester.pumpWidget(_scoped(
        PairingSheet(deviceName: 'Desk', pinExpiresAtMs: expiresAt),
      ));
      await tester.pump();

      AnimatedDefaultTextStyle label() => tester.widget<AnimatedDefaultTextStyle>(
          find.byKey(const Key('pairingCountdownLabel')));

      // ~15s remaining: comfortably above the urgency threshold.
      await tester.pump(const Duration(milliseconds: 5000));
      expect(label().style.color, AppPalette.charcoal.inkFaint,
          reason: 'countdown should stay neutral above the 10s threshold');

      // ~8-9s remaining: past the threshold, should read as urgent.
      await tester.pump(const Duration(milliseconds: 6500));
      expect(label().style.color, AppPalette.charcoal.danger,
          reason: 'countdown should shift to the danger color at <=10s');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'ResponderPairingSheet: countdown label stays neutral, then '
        'shifts to the danger color once <=10s remain', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final deviceList = DeviceListModel(prefs, deviceName: 'Test Phone');
      addTearDown(deviceList.dispose);

      final expiresAt = DateTime.now().millisecondsSinceEpoch + 20000;

      await tester.pumpWidget(_scoped(
        ChangeNotifierProvider<DeviceListModel>.value(
          value: deviceList,
          child: ResponderPairingSheet(
            requesterDeviceId: 'peer-1',
            requesterDeviceName: 'Desk',
            pinCode: '123456',
            pinExpiresAtMs: expiresAt,
          ),
        ),
      ));
      await tester.pump();

      AnimatedDefaultTextStyle label() => tester.widget<AnimatedDefaultTextStyle>(
          find.byKey(const Key('pairingCountdownLabel')));

      await tester.pump(const Duration(milliseconds: 5000));
      expect(label().style.color, AppPalette.charcoal.inkFaint,
          reason: 'countdown should stay neutral above the 10s threshold');

      await tester.pump(const Duration(milliseconds: 6500));
      expect(label().style.color, AppPalette.charcoal.danger,
          reason: 'countdown should shift to the danger color at <=10s');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
