import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'i18n/strings.dart';
import 'screens/shell.dart';
import 'state/settings_model.dart';
import 'theme/app_theme.dart';

/// Root widget. Rebuilds the theme + string scope whenever the user
/// changes theme or language in Settings.
class ConnectibleApp extends StatelessWidget {
  const ConnectibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final palette = AppPalette.of(settings.theme);

    return MaterialApp(
      title: 'Connectible',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette),
      // Wrap via `builder` (not `home`) so the palette/strings scopes sit
      // *above* the Navigator. Otherwise modal routes -- bottom sheets,
      // dialogs, the pairing sheets -- are pushed as siblings of `home`
      // and cannot read `context.palette`, which crashes them (white
      // screen) with "AppPaletteScope missing from the widget tree".
      builder: (context, child) => AppPaletteScope(
        palette: palette,
        child: AppStringsScope(
          strings: AppStrings(settings.locale),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const AppShell(),
    );
  }
}
