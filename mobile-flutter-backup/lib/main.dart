import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/state/app_providers.dart';
import 'src/state/settings_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  final prefs = await SharedPreferences.getInstance();

  final settings = SettingsModel(prefs);
  // First-run locale from the platform if nothing saved.
  final platformLocale = ui.PlatformDispatcher.instance.locale.languageCode;
  settings.setLocale(SettingsModel.detectInitial(prefs, platformLocale));

  final deviceName = _defaultDeviceName();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ...buildAppStateProviders(prefs,
            deviceName: deviceName,
            pairableEnabled: settings.pairableEnabled,
            clipboardAutoMonitor: settings.clipboardAutoMonitor,
            clipboardAutoApply: settings.clipboardAutoApply),
      ],
      child: const ConnectibleApp(),
    ),
  );
}

String _defaultDeviceName() {
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
  } catch (_) {
    // Fall through.
  }
  return 'Connectible Phone';
}
