import { useState } from "react";
import { Icon } from "./Icon";
import { useT } from "../i18n";
import { ipc } from "../lib/ipc";
import { errorCodeMessage } from "../lib/errors";

interface RemoteInputPanelProps {
  capabilities: string[];
  // Whether incoming RemoteInputEvent frames are currently applied
  // (T-309), read from the daemon's GetLocalState snapshot.
  enabled: boolean;
  // Re-fetches local state after a successful toggle so `enabled`
  // reflects what the daemon actually applied.
  onRefresh: () => void;
  // True until the daemon's first GetLocalState snapshot (which carries
  // `capabilities`) has loaded (T-601). Without this, `capabilities`
  // defaults to `[]` and the status card would flash "Unavailable" --
  // a real, permanent-sounding claim -- during the loading window
  // instead of a neutral "checking" state.
  loading?: boolean;
}

/// Placeholder for the status card shown before the daemon's first
/// snapshot has loaded (T-601): mirrors DeviceListPanel's T-311
/// skeleton pattern rather than presenting an unearned "Unavailable".
function RemoteInputStatusSkeleton() {
  return (
    <div className="card p-5" data-testid="remote-input-status-skeleton" aria-busy="true">
      <div className="flex items-start gap-4">
        <div className="h-11 w-11 shrink-0 animate-pulse rounded-xl bg-white/[0.06]" />
        <div className="flex-1">
          <div className="flex items-center justify-between gap-3">
            <div className="h-3 w-32 animate-pulse rounded bg-white/[0.06]" />
            <div className="h-5 w-16 animate-pulse rounded-full bg-white/[0.04]" />
          </div>
          <div className="mt-2.5 h-2.5 w-2/3 animate-pulse rounded bg-white/[0.04]" />
        </div>
      </div>
    </div>
  );
}

/// Remote input panel (T-039). The desktop is the receiver in the MVP
/// (a paired phone drives this machine), so this shows whether this
/// computer can accept remote input, which backend is active, and lets
/// the user turn dispatch on/off without disconnecting anything (T-309).
export function RemoteInputPanel({ capabilities, enabled, onRefresh, loading }: RemoteInputPanelProps) {
  const t = useT();
  const available = capabilities.includes("remote_input");
  const [toggling, setToggling] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleToggle() {
    if (!available || toggling) return;
    setToggling(true);
    setError(null);
    const result = await ipc.setRemoteInputEnabled(!enabled);
    setToggling(false);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    onRefresh();
  }

  return (
    <section className="flex h-full flex-col gap-5 animate-fade-in">
      <span className="eyebrow">{t("input.eyebrow")}</span>

      {error && (
        <p className="rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-danger" role="alert">
          {error}
        </p>
      )}

      {loading ? (
        <RemoteInputStatusSkeleton />
      ) : (
        <div className="card p-5">
          <div className="flex items-start gap-4">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-line bg-gradient-to-b from-white/[0.08] to-transparent">
              <Icon name="cursor" className="h-5 w-5 text-ink" />
            </div>
            <div className="flex-1">
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-medium text-ink">{t("input.acceptTitle")}</p>
                <span
                  className={`pill ${
                    available
                      ? "border-white/15 bg-white/[0.06] text-ink"
                      : "bg-surface-overlay text-ink-faint"
                  }`}
                >
                  <span className={`h-1.5 w-1.5 rounded-full ${available ? "bg-paper" : "bg-ink-ghost"}`} />
                  {available ? t("input.ready") : t("input.unavailable")}
                </span>
              </div>
              <p className="mt-1.5 text-xs leading-relaxed text-ink-faint">{t("input.acceptDesc")}</p>
            </div>
          </div>

          {available && (
            <div className="mt-4 flex items-center justify-between rounded-lg border border-line bg-black/20 px-3.5 py-3">
              <div>
                <p className="text-sm font-medium text-ink">
                  {enabled ? t("input.enabledTitle") : t("input.disabledTitle")}
                </p>
                <p className="mt-0.5 text-xs text-ink-faint">{t("input.toggleHint")}</p>
              </div>
              <button
                type="button"
                role="switch"
                aria-checked={enabled}
                aria-label={t("input.toggleLabel")}
                disabled={toggling}
                onClick={() => void handleToggle()}
                className={`relative h-6 w-11 shrink-0 rounded-full border transition-colors disabled:opacity-50 ${
                  enabled ? "border-white/25 bg-white/20" : "border-line bg-surface-overlay"
                }`}
              >
                <span
                  className={`absolute top-0.5 h-4 w-4 rounded-full bg-paper transition-transform ${
                    enabled ? "translate-x-[22px]" : "translate-x-0.5"
                  }`}
                />
              </button>
            </div>
          )}

          {!available && (
            <div className="mt-4 rounded-lg border border-line bg-black/30 px-3.5 py-3 text-xs leading-relaxed text-ink-faint">
              {t("input.noBackendPre")}{" "}
              <code className="rounded bg-white/[0.06] px-1 py-0.5 font-mono text-ink-muted">ydotoold</code>{" "}
              {t("input.noBackendPost")}
            </div>
          )}
        </div>
      )}

      <div className="card flex flex-1 flex-col items-center justify-center gap-3 border-dashed py-14 text-center">
        <div className="relative flex h-16 w-16 items-center justify-center">
          <span className="absolute inset-0 rounded-full border border-line" />
          <span className="absolute inset-2 rounded-full border border-line-faint" />
          <Icon name="cursor" className="h-6 w-6 text-ink-ghost" />
        </div>
        <p className="text-sm font-medium text-ink-muted">{t("input.waitingTitle")}</p>
        <p className="max-w-xs text-xs text-ink-faint">{t("input.waitingHint")}</p>
      </div>
    </section>
  );
}
