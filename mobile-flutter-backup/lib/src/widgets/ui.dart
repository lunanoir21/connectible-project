import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String monogram(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

IconData platformIcon(String platform) {
  final p = platform.toUpperCase();
  if (p.contains('ANDROID') || p.contains('IOS')) {
    return Icons.smartphone_outlined;
  }
  if (p.contains('MACOS')) return Icons.laptop_mac_outlined;
  if (p.contains('WINDOWS')) return Icons.desktop_windows_outlined;
  if (p.contains('LINUX')) return Icons.dvr_outlined;
  return Icons.devices_other_outlined;
}

/// Small section eyebrow label (uppercase, tracked), matching desktop.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: context.palette.inkFaint,
      ),
    );
  }
}

/// Distinct empty state (icon + title + hint).
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, this.hint});
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: p.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.line),
              ),
              child: Icon(icon, size: 24, color: p.inkFaint),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: p.ink)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.5, color: p.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded monochrome card container.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: child,
    );
  }
}
