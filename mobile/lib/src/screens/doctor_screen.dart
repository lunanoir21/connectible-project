import 'package:flutter/material.dart' hide NotificationListener;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../services/doctor/checks.dart';
import '../services/doctor/doctor.dart';
import '../services/notification_listener.dart';
import '../state/pairing_model.dart';
import '../state/settings_model.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Mobile System Doctor (Phase F / T-F9/F10): runs mobile-native health +
/// permission checks in-process and renders them grouped by category, with
/// remediation and deep-link actions. Reached from Settings.
class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  DoctorReport? _report;
  bool _running = false;
  String? _rerunning;
  bool _copied = false;

  static const _categoryOrder = [
    DoctorCategory.connectivity,
    DoctorCategory.permissions,
    DoctorCategory.storage,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  DoctorRunner _buildRunner() {
    final pairing = context.read<PairingModel>();
    final settings = context.read<SettingsModel>();
    return DoctorRunner(buildMobileChecks(
      pairing: pairing,
      pairableEnabled: settings.pairableEnabled,
      notifications: const PlatformNotificationListener(),
    ));
  }

  Future<void> _runAll() async {
    setState(() => _running = true);
    final report = await _buildRunner().runAll();
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  Future<void> _rerun(String id) async {
    setState(() => _rerunning = id);
    final updated = await _buildRunner().runOne(id);
    if (!mounted) return;
    setState(() {
      _rerunning = null;
      final current = _report;
      if (updated != null && current != null) {
        final checks = current.checks
            .map((c) => c.id == id ? updated : c)
            .toList(growable: false);
        _report = DoctorReport(
          checks,
          worstStatus(checks.map((c) => c.status)),
        );
      }
    });
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    final lines = report.checks.map((c) {
      final base = '[${_statusLabel(c.status)}] ${c.title}: ${c.summary}';
      return c.remediation != null ? '$base\n    -> ${c.remediation}' : base;
    });
    await Clipboard.setData(ClipboardData(
      text: 'Connectible System Doctor '
          '(${_statusLabel(report.worst)})\n\n${lines.join('\n')}',
    ));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  static String _statusLabel(DoctorStatus s) => switch (s) {
        DoctorStatus.ok => 'OK',
        DoctorStatus.warn => 'WARN',
        DoctorStatus.error => 'FAIL',
      };

  String _categoryTitle(AppStrings s, DoctorCategory c) => switch (c) {
        DoctorCategory.connectivity => s.t('doctor.catConnectivity'),
        DoctorCategory.permissions => s.t('doctor.catPermissions'),
        DoctorCategory.storage => s.t('doctor.catStorage'),
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.strings;
    final report = _report;

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: p.ink),
        title: Text(s.t('doctor.title'),
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (report != null)
            TextButton(
              onPressed: _copyReport,
              child: Text(
                _copied ? s.t('doctor.copied') : s.t('doctor.copyReport'),
                style: TextStyle(color: p.inkMuted, fontSize: 13),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (report != null) _StatusBadge(status: report.worst, large: true),
              _PillButton(
                label: _running ? s.t('doctor.running') : s.t('doctor.runAll'),
                onTap: _running ? null : _runAll,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (report == null && _running)
            Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: p.inkMuted),
            )),
          for (final category in _categoryOrder)
            _CategorySection(
              title: _categoryTitle(s, category),
              checks: (report?.checks ?? [])
                  .where((c) => c.category == category)
                  .toList(growable: false),
              rerunning: _rerunning,
              onRerun: _rerun,
              rerunLabel: s.t('doctor.rerun'),
            ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.checks,
    required this.rerunning,
    required this.onRerun,
    required this.rerunLabel,
  });
  final String title;
  final List<DoctorCheckResult> checks;
  final String? rerunning;
  final void Function(String id) onRerun;
  final String rerunLabel;

  @override
  Widget build(BuildContext context) {
    if (checks.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: p.inkFaint)),
        ),
        for (final check in checks) ...[
          _CheckRow(
            check: check,
            rerunning: rerunning == check.id,
            onRerun: () => onRerun(check.id),
            rerunLabel: rerunLabel,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.check,
    required this.rerunning,
    required this.onRerun,
    required this.rerunLabel,
  });
  final DoctorCheckResult check;
  final bool rerunning;
  final VoidCallback onRerun;
  final String rerunLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBadge(status: check.status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(check.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink)),
                    Text(check.summary,
                        style: TextStyle(fontSize: 13, color: p.inkMuted)),
                    if (check.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(check.detail!,
                            style:
                                TextStyle(fontSize: 12, color: p.inkFaint)),
                      ),
                    if (check.remediation != null &&
                        check.status != DoctorStatus.ok)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('-> ${check.remediation!}',
                            style:
                                TextStyle(fontSize: 12, color: p.inkMuted)),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: rerunning ? null : onRerun,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(rerunLabel,
                      style: TextStyle(fontSize: 12, color: p.inkFaint)),
                ),
              ),
            ],
          ),
          if (check.action != null && check.actionLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PillButton(
                  label: check.actionLabel!,
                  onTap: () => check.action!(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.large = false});
  final DoctorStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Monochrome: differentiate by weight/border/opacity, not color.
    final (label, borderColor, textColor, weight) = switch (status) {
      DoctorStatus.ok => ('OK', p.line, p.inkFaint, FontWeight.w600),
      DoctorStatus.warn => ('WARN', p.inkMuted, p.inkMuted, FontWeight.w600),
      DoctorStatus.error => ('FAIL', p.ink, p.ink, FontWeight.w700),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: large ? 12 : 10,
              fontWeight: weight,
              fontFeatures: const [],
              color: textColor,
              letterSpacing: 0.5)),
    );
  }
}

/// Small monochrome action pill (mirrors the Settings screen's button).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? p.ink : p.inkFaint)),
      ),
    );
  }
}
