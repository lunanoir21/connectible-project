import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:connectible_mobile/src/i18n/strings.dart';
import 'package:connectible_mobile/src/theme/app_theme.dart';

/// Wraps [child] with the palette/strings scopes every screen reads via
/// `context.palette`/`context.strings`, plus whatever ChangeNotifier
/// [providers] the screen under test depends on. Mirrors the
/// MaterialApp.builder pattern the real app (`app.dart`) and the existing
/// widget_test.dart/pairing_countdown_urgency_test.dart tests use, so the
/// scopes sit above the Navigator the same way they do for real.
Widget wrapScreen(
  Widget child, {
  List<SingleChildWidget> providers = const [],
  AppPalette palette = AppPalette.charcoal,
  AppLocale locale = AppLocale.en,
  // Forces reduced motion for the subtree. Screens with an ambient
  // (perpetually repeating) animation would otherwise make pumpAndSettle
  // hang forever, since it waits for a frame-idle that never comes.
  bool disableAnimations = false,
}) {
  final app = MaterialApp(
    builder: (context, navigatorChild) {
      Widget tree = AppPaletteScope(
        palette: palette,
        child: AppStringsScope(
          strings: AppStrings(locale),
          child: navigatorChild ?? const SizedBox.shrink(),
        ),
      );
      if (disableAnimations) {
        tree = MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: tree,
        );
      }
      return tree;
    },
    home: Scaffold(body: child),
  );
  // `Nested` (MultiProvider's guts) asserts a non-empty provider list, so a
  // screen with no ChangeNotifier dependencies (e.g. PairLandingScreen)
  // skips the wrapper entirely rather than passing it an empty list.
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}
