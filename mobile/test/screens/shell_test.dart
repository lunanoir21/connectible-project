import 'package:connectible_mobile/src/i18n/strings.dart';
import 'package:connectible_mobile/src/screens/shell.dart';
import 'package:connectible_mobile/src/state/app_providers.dart';
import 'package:connectible_mobile/src/state/settings_model.dart';
import 'package:connectible_mobile/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'bottom navigation switches the visible screen and app-bar title',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Real wiring (T-905): pairableEnabled: false keeps this from binding
    // a real inbound TLS server / mDNS advertisement, but otherwise this
    // is exactly how main.dart assembles the providers AppShell depends
    // on -- SettingsModel plus the four ChangeNotifier providers from
    // buildAppStateProviders. IndexedStack builds every tab's screen
    // eagerly (including SettingsScreen), so SettingsModel must be
    // provided here too or that build throws ProviderNotFoundException.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: SettingsModel(prefs)),
          ...buildAppStateProviders(prefs,
              deviceName: 'Test Phone', pairableEnabled: false),
        ],
        child: MaterialApp(
          builder: (context, navigatorChild) => AppPaletteScope(
            palette: AppPalette.charcoal,
            child: AppStringsScope(
              strings: const AppStrings(AppLocale.en),
              child: navigatorChild ?? const SizedBox.shrink(),
            ),
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();

    // AppBar title starts on the Home tab. IndexedStack (deliberately,
    // per shell.dart's docs) keeps every tab's screen built and mounted
    // at once so state survives switching, so the title text -- not
    // content presence -- is what actually proves which tab is active.
    // shell.dart builds a custom PreferredSize app bar (not Flutter's
    // AppBar widget), so the title is found by key rather than by type.
    Text appBarTitle() =>
        tester.widget<Text>(find.byKey(const Key('shellAppBarTitle')));
    expect(appBarTitle().data, 'Home');
    // IndexedStack (per its actual Flutter implementation) wraps each
    // non-active child in Visibility(visible: false, maintainState: true)
    // -- the child stays built/mounted (proving state survives tab
    // switches), but default finders treat it as "offstage" and skip it.
    // skipOffstage: false is required to see it, exactly because it's
    // offstage rather than absent.
    expect(
        find.text('Nothing copied yet', skipOffstage: false), findsOneWidget,
        reason: 'ClipboardScreen is already built inside the IndexedStack, '
            'just offstage while the Home tab is active');

    await tester.tap(find.text('Clipboard'));
    await tester.pump();
    expect(appBarTitle().data, 'Clipboard');

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(appBarTitle().data, 'Settings');
    expect(find.text('Appearance'), findsOneWidget);
    // "About" is the last section in SettingsScreen's ListView, below the
    // fold at the default test viewport size -- a real ListView (not
    // .builder) still only realizes sliver children near the current
    // viewport, so it must actually be scrolled into view first.
    await tester.scrollUntilVisible(find.text('About'), 200);
    await tester.pump();
    expect(find.text('About'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
