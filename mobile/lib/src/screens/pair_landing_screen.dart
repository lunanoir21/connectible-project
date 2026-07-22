import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'pair_scan_screen.dart';
import 'settings_screen.dart';

/// Pairing landing screen (Orca-style reference): a single QR-pairing CTA
/// plus a "how it works" list. This is an additional entry point into the
/// existing [PairingSheet]/[startPair] flow -- it does not replace the
/// tap-a-star or manual-connect paths already on [HomeScreen].
class PairLandingScreen extends StatelessWidget {
  const PairLandingScreen({super.key});

  static const _steps = [
    ('pairing.landing.step1Title', 'pairing.landing.step1Body'),
    ('pairing.landing.step2Title', 'pairing.landing.step2Body'),
    ('pairing.landing.step3Title', 'pairing.landing.step3Body'),
  ];

  void _openScan(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PairScanScreen()));
  }

  void _openSettings(BuildContext context) {
    // SettingsScreen has no Scaffold of its own -- it normally relies on
    // AppShell's single Scaffold for a Material ancestor (Switch etc.
    // require one). Pushing it standalone needs the same wrapper
    // DoctorScreen uses.
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) {
      final p = context.palette;
      final s = context.strings;
      return Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          backgroundColor: p.canvas,
          elevation: 0,
          iconTheme: IconThemeData(color: p.ink),
          title: Text(s.t('settings.title'),
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        body: const SettingsScreen(),
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                BackButton(color: p.inkMuted),
                Icon(Icons.hub_outlined, size: 18, color: p.ink),
                const SizedBox(width: 8),
                Text('Connectible',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.ink)),
                const Spacer(),
                IconButton(
                  onPressed: () => _openSettings(context),
                  icon: Icon(Icons.settings_outlined, color: p.inkMuted),
                  tooltip: s.t('nav.settings'),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              s.t('pairing.landing.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: p.ink),
            ),
            const SizedBox(height: 12),
            Text(
              s.t('pairing.landing.subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: p.inkMuted),
            ),
            const SizedBox(height: 36),
            Center(
              child: _PairDesktopButton(
                label: s.t('pairing.landing.cta'),
                onTap: () => _openScan(context),
              ),
            ),
            const SizedBox(height: 48),
            Eyebrow(s.t('pairing.landing.howItWorks')),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final (i, step) in _steps.indexed) ...[
                    if (i != 0) Divider(color: p.line, height: 1),
                    _StepRow(
                      index: i + 1,
                      title: s.t(step.$1),
                      body: s.t(step.$2),
                      palette: p,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairDesktopButton extends StatelessWidget {
  const _PairDesktopButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, size: 18, color: Colors.black),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.title,
    required this.body,
    required this.palette,
  });
  final int index;
  final String title;
  final String body;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surfaceOverlay,
              shape: BoxShape.circle,
              border: Border.all(color: p.line),
            ),
            child: Text('$index',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.inkMuted)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.ink)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: p.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
