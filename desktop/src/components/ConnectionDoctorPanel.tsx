import { useState, useEffect, useCallback } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useT } from "../i18n";
import { ipc } from "../lib/ipc";
import { errorCodeMessage } from "../lib/errors";
import type {
  DiagnosticCheck,
  DiagnosticStatus,
  DiagnosticsReport,
} from "../lib/types";

// System Doctor (T-F8). This panel is a thin renderer over the daemon's
// diagnostics engine (RunDiagnostics RPC), so it and `connectibled doctor`
// show identical results -- the daemon is the single source of truth.

const CATEGORY_ORDER = ["environment", "network", "pairing", "features"] as const;

type TKey = Parameters<ReturnType<typeof useT>>[0];

const CATEGORY_KEY: Record<string, TKey> = {
  environment: "doctor.catEnvironment",
  network: "doctor.catNetwork",
  pairing: "doctor.catPairing",
  features: "doctor.catFeatures",
};

// T-X13: localized title per daemon check id. Keyed by the daemon's
// actual kebab-case ids (daemon/src/diagnostics/*.rs `id()`), not the
// older camelCase names some stale keys were written for. An id with no
// entry here (a new/unknown check) falls back to the daemon-provided
// English title, so the panel never renders blank. Summaries and
// remediation stay daemon-provided: they are dynamic (embed counts,
// RTTs, error text) and cannot be localized client-side without the
// daemon emitting structured message ids -- see the Done note / follow-up.
const CHECK_TITLE_KEY: Record<string, TKey> = {
  "daemon-version": "doctor.checks.daemonVersion",
  "download-dir-writable": "doctor.checks.downloadDirWritable",
  "disk-space": "doctor.checks.diskSpace",
  "db-encryption-key-source": "doctor.checks.dbEncryptionKeySource",
  "data-dir-writable": "doctor.checks.dataDirWritable",
  "tls-dir-writable": "doctor.checks.tlsDirWritable",
  "transfers-dir-writable": "doctor.checks.transfersDirWritable",
  "lan-address": "doctor.checks.lanAddress",
  "daemon-port": "doctor.checks.daemonPort2",
  "tls-cert": "doctor.checks.tlsCert2",
  "paired-store": "doctor.checks.pairedStore",
  "recent-errors": "doctor.checks.recentErrors",
};

function worstOf(checks: DiagnosticCheck[]): DiagnosticStatus {
  if (checks.some((c) => c.status === "error")) return "error";
  if (checks.some((c) => c.status === "warn")) return "warn";
  return "ok";
}

export function ConnectionDoctorPanel() {
  const t = useT();
  const [report, setReport] = useState<DiagnosticsReport | null>(null);
  const [running, setRunning] = useState(false);
  const [rerunning, setRerunning] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastRun, setLastRun] = useState<Date | null>(null);
  const [copied, setCopied] = useState(false);

  const runAll = useCallback(async () => {
    setRunning(true);
    setError(null);
    const res = await ipc.runDiagnostics();
    if (res.ok) {
      setReport(res.value);
      setLastRun(new Date());
    } else {
      setError(errorCodeMessage(res.error.code, t));
      setReport(null);
    }
    setRunning(false);
  }, [t]);

  useEffect(() => {
    void runAll();
  }, [runAll]);

  const rerunOne = useCallback(async (id: string) => {
    setRerunning(id);
    const res = await ipc.runDiagnostics(id);
    if (res.ok && res.value.checks[0]) {
      const updated = res.value.checks[0];
      setReport((prev) => {
        if (!prev) return prev;
        const checks = prev.checks.map((c) => (c.id === id ? updated : c));
        return { checks, worst: worstOf(checks) };
      });
    }
    setRerunning(null);
  }, []);

  const copyReport = useCallback(async () => {
    if (!report) return;
    const lines = report.checks.map((c) => {
      const base = `[${c.status.toUpperCase()}] ${c.title}: ${c.summary}`;
      return c.remediation ? `${base}\n    -> ${c.remediation}` : base;
    });
    const text = `Connectible System Doctor (${report.worst.toUpperCase()})\n\n${lines.join("\n")}`;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard denied -- nothing actionable to show.
    }
  }, [report]);

  const grouped = CATEGORY_ORDER.map((cat) => ({
    category: cat,
    checks: report?.checks.filter((c) => c.category === cat) ?? [],
  })).filter((g) => g.checks.length > 0);

  return (
    <section className="flex h-full flex-col gap-5 animate-fade-in">
      <div className="flex items-center justify-between gap-3">
        <span className="eyebrow">{t("doctor.title")}</span>
        <div className="flex items-center gap-2">
          <button type="button" onClick={() => void openDocs()} className="btn-ghost text-sm">
            {t("doctor.actions.openDocs")}
          </button>
          {report && (
            <button type="button" onClick={copyReport} className="btn-ghost text-sm">
              {copied ? t("doctor.copied") : t("doctor.copyReport")}
            </button>
          )}
          <button type="button" onClick={runAll} disabled={running} className="btn-primary text-sm">
            {running ? t("doctor.running") : t("doctor.runAll")}
          </button>
        </div>
      </div>

      {report && (
        <div className="flex items-center gap-3">
          <StatusBadge status={report.worst} large />
          <span className="text-sm text-ink-faint">
            {lastRun && t("doctor.lastRun", { time: lastRun.toLocaleTimeString() })}
          </span>
        </div>
      )}

      {error && (
        <p className="rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-danger" role="alert">
          {error}
        </p>
      )}

      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto pr-1">
        {grouped.map((group) => (
          <div key={group.category} className="flex flex-col gap-2.5">
            <span className="eyebrow px-0.5">{t(CATEGORY_KEY[group.category])}</span>
            <div className="flex flex-col gap-2">
              {group.checks.map((check) => (
                <CheckRow
                  key={check.id}
                  check={check}
                  title={CHECK_TITLE_KEY[check.id] ? t(CHECK_TITLE_KEY[check.id]) : check.title}
                  rerunning={rerunning === check.id}
                  onRerun={() => rerunOne(check.id)}
                  rerunLabel={t("doctor.rerun")}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function CheckRow({
  check,
  title,
  rerunning,
  onRerun,
  rerunLabel,
}: {
  check: DiagnosticCheck;
  title: string;
  rerunning: boolean;
  onRerun: () => void;
  rerunLabel: string;
}) {
  return (
    <div className="card px-4 py-3.5">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <StatusBadge status={check.status} />
          <div>
            <p className="text-sm font-medium text-ink">{title}</p>
            <p className="text-sm text-ink-muted">{check.summary}</p>
            {check.detail && <p className="mt-1 text-xs text-ink-faint">{check.detail}</p>}
            {check.remediation && check.status !== "ok" && (
              <p className="mt-1 text-xs text-ink-muted">&rarr; {check.remediation}</p>
            )}
          </div>
        </div>
        <button type="button" onClick={onRerun} disabled={rerunning} className="btn-ghost shrink-0 px-2.5 py-1 text-xs">
          {rerunLabel}
        </button>
      </div>
    </div>
  );
}

function StatusBadge({
  status,
  large,
}: {
  status: DiagnosticStatus;
  large?: boolean;
}) {
  const t = useT();
  // T-X13: badge text from i18n instead of hardcoded OK/WARN/FAIL.
  const label =
    status === "ok"
      ? t("doctor.statusSuccess")
      : status === "warn"
        ? t("doctor.statusWarning")
        : t("doctor.statusError");
  // Monochrome: differentiate by weight/border/opacity, not color.
  const tone =
    status === "ok"
      ? "border-line text-ink-faint"
      : status === "warn"
        ? "border-ink-muted text-ink-muted"
        : "border-ink text-ink font-semibold";
  return (
    <span
      className={`inline-flex items-center justify-center rounded-md border ${tone} ${
        large ? "px-2.5 py-1 text-xs" : "px-2 py-0.5 text-[10px]"
      } font-mono tracking-wide`}
    >
      {label}
    </span>
  );
}

// Wired to the panel header's "Open docs" button above -- a general
// escape hatch to the project docs, independent of any single check's
// own remediation text.
export const PROJECT_README_URL =
  "https://github.com/lunanoir21/connectible-project#readme";
export async function openDocs() {
  await openUrl(PROJECT_README_URL);
}
