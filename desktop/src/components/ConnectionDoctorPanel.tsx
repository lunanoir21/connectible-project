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

const CATEGORY_KEY: Record<string, Parameters<ReturnType<typeof useT>>[0]> = {
  environment: "doctor.catEnvironment",
  network: "doctor.catNetwork",
  pairing: "doctor.catPairing",
  features: "doctor.catFeatures",
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
    <div className="flex flex-col gap-4 p-5">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold text-ink">{t("doctor.title")}</h2>
          <p className="text-sm text-ink-muted">{t("doctor.subtitle")}</p>
        </div>
        <div className="flex items-center gap-2">
          {report && (
            <button
              onClick={copyReport}
              className="rounded-lg border border-line px-3 py-2 text-sm font-medium text-ink hover:bg-surface-hover"
            >
              {copied ? t("doctor.copied") : t("doctor.copyReport")}
            </button>
          )}
          <button
            onClick={runAll}
            disabled={running}
            className="rounded-lg border border-line bg-surface-raised px-3 py-2 text-sm font-semibold text-ink hover:bg-surface-hover disabled:opacity-50"
          >
            {running ? t("doctor.running") : t("doctor.runAll")}
          </button>
        </div>
      </header>

      {report && (
        <div className="flex items-center gap-3">
          <StatusBadge status={report.worst} large />
          <span className="text-sm text-ink-muted">
            {lastRun &&
              t("doctor.lastRun", { time: lastRun.toLocaleTimeString() })}
          </span>
        </div>
      )}

      {error && (
        <div className="rounded-lg border border-line bg-surface-raised p-4 text-sm text-ink-muted">
          {error}
        </div>
      )}

      {grouped.map((group) => (
        <section key={group.category} className="flex flex-col gap-2">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-ink-faint">
            {t(CATEGORY_KEY[group.category])}
          </h3>
          <div className="flex flex-col gap-2">
            {group.checks.map((check) => (
              <CheckRow
                key={check.id}
                check={check}
                rerunning={rerunning === check.id}
                onRerun={() => rerunOne(check.id)}
                rerunLabel={t("doctor.rerun")}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function CheckRow({
  check,
  rerunning,
  onRerun,
  rerunLabel,
}: {
  check: DiagnosticCheck;
  rerunning: boolean;
  onRerun: () => void;
  rerunLabel: string;
}) {
  return (
    <div className="rounded-lg border border-line bg-surface-raised p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <StatusBadge status={check.status} />
          <div>
            <div className="text-sm font-medium text-ink">{check.title}</div>
            <div className="text-sm text-ink-muted">{check.summary}</div>
            {check.detail && (
              <div className="mt-1 text-xs text-ink-faint">{check.detail}</div>
            )}
            {check.remediation && check.status !== "ok" && (
              <div className="mt-1 text-xs text-ink-muted">
                &rarr; {check.remediation}
              </div>
            )}
          </div>
        </div>
        <button
          onClick={onRerun}
          disabled={rerunning}
          className="shrink-0 rounded-md border border-line px-2 py-1 text-xs text-ink-muted hover:bg-surface-hover disabled:opacity-50"
        >
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
  const label =
    status === "ok" ? "OK" : status === "warn" ? "WARN" : "FAIL";
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

// Retained so an "open docs" remediation still has a real link if any check
// ever surfaces one via its data; unused links are harmless.
export const PROJECT_README_URL =
  "https://github.com/lunanoir21/connectible-project#readme";
export async function openDocs() {
  await openUrl(PROJECT_README_URL);
}
