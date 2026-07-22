import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connectible_mobile/src/app.dart';
import 'package:connectible_mobile/src/state/app_providers.dart';
import 'package:connectible_mobile/src/state/settings_model.dart';
import 'package:connectible_mobile/src/theme/app_theme.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    // The app reads/writes SharedPreferences and depends on its
    // providers, so wire them all up the way main.dart does.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsModel(prefs)),
          ...buildAppStateProviders(prefs, deviceName: 'Test Phone'),
        ],
        child: const ConnectibleApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);

    // Tear the tree down so the providers dispose and DeviceListModel
    // cancels its discovery timer / mDNS handles (avoids "pending timer"
    // errors from the periodic network discovery the Home screen starts).
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Regression: modal routes (action sheets, dialogs, pairing sheets) are
  // pushed onto the app's Navigator, so the palette/strings scopes must
  // sit *above* it -- via MaterialApp.builder, not `home`. Otherwise
  // context.palette inside a modal throws "AppPaletteScope missing",
  // which the user saw as a white screen on long-press.
  testWidgets('modal route can read context.palette', (tester) async {
    const palette = AppPalette.charcoal;
    late BuildContext sheetContext;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppPaletteScope(
          palette: palette,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetCtx) {
                    sheetContext = sheetCtx;
                    // Would throw pre-fix: the sheet is a Navigator sibling
                    // of `home`, not a descendant of AppPaletteScope.
                    return SizedBox(
                        height: 40,
                        child: ColoredBox(color: sheetCtx.palette.surface));
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sheetContext.palette.surface, palette.surface);
  });
}
