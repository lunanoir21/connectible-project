import 'dart:async';

/// Mobile System Doctor engine (Phase F / T-F9/F10). Mirrors the daemon's
/// diagnostics model (`daemon/src/diagnostics/`) in Dart so the phone's
/// self-check feels like the same product as `connectibled doctor`, but
/// runs mobile-native checks in-process (no daemon RPC).

enum DoctorStatus { ok, warn, error }

/// Worst (highest-severity) status across a set; ok < warn < error.
DoctorStatus worstStatus(Iterable<DoctorStatus> statuses) {
  var worst = DoctorStatus.ok;
  for (final s in statuses) {
    if (s.index > worst.index) worst = s;
  }
  return worst;
}

enum DoctorCategory { connectivity, permissions, storage }

/// The outcome of one check, including an optional actionable fix (e.g. a
/// deep link into a system settings page) the UI renders as a button.
class DoctorCheckResult {
  const DoctorCheckResult({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.summary,
    this.detail,
    this.remediation,
    this.action,
    this.actionLabel,
  });

  final String id;
  final String title;
  final DoctorCategory category;
  final DoctorStatus status;
  final String summary;
  final String? detail;
  final String? remediation;

  /// Optional fix the user can trigger (deep-links to a settings page,
  /// re-runs a probe, ...). The UI shows [actionLabel] as a button.
  final Future<void> Function()? action;
  final String? actionLabel;
}

/// One diagnostic check. Concrete checks take their dependencies
/// (PairingModel, MdnsService, NotificationListener, ...) via the
/// constructor so they are unit-testable without platform channels.
abstract class DoctorCheck {
  String get id;
  String get title;
  DoctorCategory get category;
  Future<DoctorCheckResult> run();
}

/// A full run's results plus the worst-severity roll-up.
class DoctorReport {
  const DoctorReport(this.checks, this.worst);
  final List<DoctorCheckResult> checks;
  final DoctorStatus worst;
}

/// Runs the registered checks (all, or one by id) and rolls up the worst
/// severity. A check that throws is reported as an `error` result rather
/// than aborting the run.
class DoctorRunner {
  DoctorRunner(this.checks);
  final List<DoctorCheck> checks;

  Future<DoctorReport> runAll() async {
    final results = <DoctorCheckResult>[];
    for (final check in checks) {
      results.add(await _safeRun(check));
    }
    return DoctorReport(results, worstStatus(results.map((r) => r.status)));
  }

  Future<DoctorCheckResult?> runOne(String id) async {
    for (final check in checks) {
      if (check.id == id) return _safeRun(check);
    }
    return null;
  }

  Future<DoctorCheckResult> _safeRun(DoctorCheck check) async {
    try {
      return await check.run();
    } catch (e) {
      return DoctorCheckResult(
        id: check.id,
        title: check.title,
        category: check.category,
        status: DoctorStatus.error,
        summary: 'Check failed to run',
        detail: '$e',
      );
    }
  }
}
