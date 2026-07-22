import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One row in a [DeviceActionSheet].
class DeviceAction {
  const DeviceAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// Bottom-sheet action menu shown when a device on the Home radar is
/// long-pressed: a device header plus a list of context actions
/// (connect, refresh, info, disconnect). Monochrome, matching the app.
class DeviceActionSheet extends StatelessWidget {
  const DeviceActionSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
  });

  final String title;
  final String? subtitle;
  final List<DeviceAction> actions;

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<DeviceAction> actions,
  }) {
    final p = context.palette;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) =>
          DeviceActionSheet(title: title, subtitle: subtitle, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.lineStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(fontSize: 12, color: p.inkFaint)),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            for (final action in actions)
              InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: () {
                  Navigator.of(context).pop();
                  action.onTap();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Row(
                    children: [
                      Icon(action.icon,
                          size: 20,
                          color: action.danger ? p.danger : p.inkMuted),
                      const SizedBox(width: 14),
                      Text(
                        action.label,
                        style: TextStyle(
                          fontSize: 15,
                          color: action.danger ? p.danger : p.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}