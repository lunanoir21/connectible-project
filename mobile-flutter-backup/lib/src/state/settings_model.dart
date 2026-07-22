import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Persisted UI preferences: theme + language (T-042 area). Mirrors the
/// desktop's Settings behavior.
class SettingsModel extends ChangeNotifier {
  SettingsModel(this._prefs) {
    _theme = ThemeIdX.fromId(_prefs.getString(_kTheme));
    _locale = _localeFromId(_prefs.getString(_kLocale));
  }

  static const _kTheme = 'connectible.theme';
  static const _kLocale = 'connectible.locale';
  static const _kPairableEnabled = 'connectible.pairable_enabled';
  static const _kClipboardAutoMonitor = 'connectible.clipboard_auto_monitor';
  static const _kClipboardAutoApply = 'connectible.clipboard_auto_apply';

  final SharedPreferences _prefs;

  ThemeId _theme = ThemeId.charcoal;
  AppLocale _locale = AppLocale.en;

  ThemeId get theme => _theme;
  AppLocale get locale => _locale;

  /// Whether this phone allows other devices to pair into it (T-308):
  /// gates whether `PairingModel`'s inbound `ConnectibleServer` and
  /// `DeviceListModel`'s mDNS advertisement start at all. Read once at
  /// app launch (`main.dart` passes it into `buildAppStateProviders`) so
  /// the choice is honored from the next launch on if left off, and
  /// updated live by the Settings screen calling [setPairableEnabled]
  /// alongside `PairingModel.setPairableEnabled`/
  /// `DeviceListModel.setPairableEnabled`. Defaults to true, matching the
  /// server's previous unconditional-start behavior.
  bool get pairableEnabled => _prefs.getBool(_kPairableEnabled) ?? true;

  void setPairableEnabled(bool value) {
    if (value == pairableEnabled) return;
    _prefs.setBool(_kPairableEnabled, value);
    notifyListeners();
  }

  /// Whether this phone auto-sends its own clipboard changes to the paired
  /// peer (T-B11). The background poll (`ClipboardModel`) already shipped
  /// on in v0.1.0 (T-304); this makes it user-controllable. Defaults to
  /// true to preserve that behavior and match the desktop's automatic
  /// clipboard sync. `main.dart` reads it at launch to seed `ClipboardModel`;
  /// the Settings screen flips both this and the live model together.
  bool get clipboardAutoMonitor =>
      _prefs.getBool(_kClipboardAutoMonitor) ?? true;

  void setClipboardAutoMonitor(bool value) {
    if (value == clipboardAutoMonitor) return;
    _prefs.setBool(_kClipboardAutoMonitor, value);
    notifyListeners();
  }

  /// Whether incoming clipboard frames are auto-applied to this phone's OS
  /// clipboard (T-B11). Defaults to true (see [clipboardAutoMonitor]).
  bool get clipboardAutoApply => _prefs.getBool(_kClipboardAutoApply) ?? true;

  void setClipboardAutoApply(bool value) {
    if (value == clipboardAutoApply) return;
    _prefs.setBool(_kClipboardAutoApply, value);
    notifyListeners();
  }

  void setTheme(ThemeId theme) {
    if (theme == _theme) return;
    _theme = theme;
    _prefs.setString(_kTheme, theme.id);
    notifyListeners();
  }

  void setLocale(AppLocale locale) {
    if (locale == _locale) return;
    _locale = locale;
    _prefs.setString(_kLocale, locale.name);
    notifyListeners();
  }

  static AppLocale _localeFromId(String? id) {
    return id == 'tr' ? AppLocale.tr : AppLocale.en;
  }

  /// Picks an initial locale from the platform if none was saved.
  static AppLocale detectInitial(
      SharedPreferences prefs, String platformLocale) {
    final saved = prefs.getString(_kLocale);
    if (saved != null) return _localeFromId(saved);
    return platformLocale.toLowerCase().startsWith('tr')
        ? AppLocale.tr
        : AppLocale.en;
  }
}
