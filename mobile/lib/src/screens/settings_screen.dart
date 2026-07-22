import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import 'doctor_screen.dart';
import '../services/notification_listener.dart';
import '../state/clipboard_model.dart';
import '../state/notification_model.dart';
import '../state/pairing_model.dart';
import '../state/settings_model.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _themes = [
    (ThemeId.charcoal, 'settings.themeCharcoal'),
    (ThemeId.onyx, 'settings.themeOnyx'),
    (ThemeId.graphite, 'settings.themeGraphite'),
  ];

  Future<void> _setPairableEnabled(BuildContext context, bool enabled) async {
    context.read<SettingsModel>().setPairableEnabled(enabled);
    await context.read<PairingModel>().setPairableEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final settings = context.watch<SettingsModel>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Section(
          icon: Icons.palette_outlined,
          title: s.t('settings.appearance'),
          hint: s.t('settings.appearanceHint'),
          child: Row(
            children: [
              for (final (id, key) in _themes) ...[
                Expanded(
                  child: _ThemeCard(
                    id: id,
                    label: s.t(key),
                    active: settings.theme == id,
                    onTap: () => settings.setTheme(id),
                  ),
                ),
                if (id != _themes.last.$1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.language_outlined,
          title: s.t('settings.language'),
          child: Column(
            children: [
              _LanguageRow(
                  id: AppLocale.en,
                  label: 'English',
                  active: settings.locale == AppLocale.en,
                  onTap: () => settings.setLocale(AppLocale.en)),
              const SizedBox(height: 8),
              _LanguageRow(
                  id: AppLocale.tr,
                  label: 'Türkçe',
                  active: settings.locale == AppLocale.tr,
                  onTap: () => settings.setLocale(AppLocale.tr)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.podcasts_outlined,
          title: s.t('settings.discoverable'),
          hint: s.t('settings.discoverableHint'),
          child: _ToggleRow(
            label: settings.pairableEnabled
                ? s.t('settings.discoverableOn')
                : s.t('settings.discoverableOff'),
            value: settings.pairableEnabled,
            onChanged: (v) => _setPairableEnabled(context, v),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.content_paste_outlined,
          title: s.t('settings.clipboard'),
          hint: s.t('settings.clipboardHint'),
          child: const _ClipboardSyncRows(),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.notifications_none_outlined,
          title: s.t('settings.notifications'),
          hint: s.t('settings.notificationsHint'),
          child: const _NotificationsRow(),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.health_and_safety_outlined,
          title: s.t('settings.diagnostics'),
          hint: s.t('settings.diagnosticsHint'),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PillButton(
              label: s.t('settings.diagnosticsOpen'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DoctorScreen(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          icon: Icons.shield_outlined,
          title: s.t('settings.about'),
          child: Column(
            children: [
              _AboutRow(
                  label: s.t('settings.version'), value: '0.1.0', palette: p),
              Divider(color: p.line, height: 20),
              _AboutRow(
                  label: s.t('settings.security'),
                  value: s.t('settings.securityValue'),
                  palette: p),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.icon,
      required this.title,
      this.hint,
      required this.child});
  final IconData icon;
  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: p.surfaceOverlay,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.line)),
                child: Icon(icon, size: 18, color: p.inkMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    if (hint != null)
                      Text(hint!,
                          style: TextStyle(fontSize: 12, color: p.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(
      {required this.id,
      required this.label,
      required this.active,
      required this.onTap});
  final ThemeId id;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final swatch = AppPalette.of(id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? p.selectedFill : p.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? p.selectedBorder : p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                  color: swatch.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line)),
              padding: const EdgeInsets.all(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                      child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                              color: swatch.surfaceRaised,
                              borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Container(
                          height: 30,
                          decoration: BoxDecoration(
                              color: swatch.surfaceHover,
                              borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(width: 4),
                  Container(
                      width: 8,
                      height: 16,
                      decoration: BoxDecoration(
                          color: swatch.paper,
                          borderRadius: BorderRadius.circular(999))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: active ? p.ink : p.inkMuted))),
                if (active) Icon(Icons.check_circle, size: 14, color: p.paper),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow(
      {required this.id,
      required this.label,
      required this.active,
      required this.onTap});
  final AppLocale id;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? p.selectedFill : p.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? p.selectedBorder : p.line),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: p.line)),
              child: Text(id.name.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: p.inkMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14, color: active ? p.ink : p.inkMuted))),
            if (active) Icon(Icons.check_circle, size: 16, color: p.paper),
          ],
        ),
      ),
    );
  }
}

/// Monochrome on/off row for the "allow this phone to be paired into"
/// setting (T-308). Explicit colors on [Switch] avoid Material's default
/// blue, matching the rest of the app's black/grey palette.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: value ? p.ink : p.inkMuted)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: p.paper,
          activeTrackColor: p.selectedFill,
          inactiveThumbColor: p.inkGhost,
          inactiveTrackColor: p.surfaceHover,
          trackOutlineColor:
              WidgetStateProperty.all(value ? p.selectedBorder : p.line),
        ),
      ],
    );
  }
}

/// Clipboard-sync opt-in toggles (T-B11). Each flips both the persisted
/// [SettingsModel] flag (so the choice survives a restart) and the live
/// [ClipboardModel] (so it takes effect immediately). Reads the live model
/// so the displayed state and the actual behavior can never drift.
class _ClipboardSyncRows extends StatelessWidget {
  const _ClipboardSyncRows();

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final clipboard = context.watch<ClipboardModel>();
    final settings = context.read<SettingsModel>();

    return Column(
      children: [
        _ToggleRow(
          label: s.t('settings.clipboardAutoMonitor'),
          value: clipboard.autoMonitor,
          onChanged: (v) {
            settings.setClipboardAutoMonitor(v);
            clipboard.setAutoMonitor(v);
          },
        ),
        const SizedBox(height: 12),
        _ToggleRow(
          label: s.t('settings.clipboardAutoApply'),
          value: clipboard.autoApply,
          onChanged: (v) {
            settings.setClipboardAutoApply(v);
            clipboard.setAutoApply(v);
          },
        ),
      ],
    );
  }
}

/// Notification-mirroring opt-in row (T-B5): reflects the system
/// "Notification access" grant state and deep-links to the settings page to
/// grant it (or manage/revoke it once granted). The grant itself is a
/// system-level toggle, so the app can only surface state + a shortcut, not
/// flip it directly.
class _NotificationsRow extends StatelessWidget {
  const _NotificationsRow();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final model = context.watch<NotificationModel>();
    final granted = model.access == NotificationAccessState.granted;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(
                granted ? Icons.check_circle_outline : Icons.remove_circle_outline,
                size: 16,
                color: granted ? p.ink : p.inkFaint,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  granted
                      ? s.t('settings.notificationsGranted')
                      : s.t('settings.notificationsDenied'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: granted ? p.ink : p.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _PillButton(
          label: granted
              ? s.t('settings.notificationsManage')
              : s.t('settings.notificationsGrant'),
          onTap: () => model.openAccessSettings(),
        ),
      ],
    );
  }
}

/// Small monochrome action pill matching the app's black/grey palette
/// (avoids Material's default accent buttons).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow(
      {required this.label, required this.value, required this.palette});
  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: palette.inkMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 14, color: palette.ink),
          ),
        ),
      ],
    );
  }
}
