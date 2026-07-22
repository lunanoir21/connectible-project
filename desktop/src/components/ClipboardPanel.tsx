import { useState } from "react";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import type { ClipboardEntry } from "../lib/types";
import type { IpcError } from "../lib/ipc";
import { formatRelativeTime, truncate } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { Icon } from "./Icon";
import { useT } from "../i18n";

interface ClipboardPanelProps {
  entries: ClipboardEntry[];
  // True until the daemon's first GetLocalState snapshot (which carries
  // clipboard history) has loaded (T-601) -- distinct from a genuinely
  // empty history, same skeleton pattern DeviceListPanel established
  // for T-311.
  loading?: boolean;
  // Set when that initial fetch failed outright, distinct from a
  // benign local copy-back failure (handled inline, see `copyBack`).
  loadError?: IpcError | null;
  onRefresh?: () => void;
}

/// Placeholder rows shown before the daemon's first snapshot has loaded
/// (T-601), matching DeviceListPanel's T-311 skeleton.
function ClipboardListSkeleton() {
  return (
    <div className="flex flex-col gap-2" data-testid="clipboard-list-skeleton" aria-busy="true">
      {[0, 1, 2].map((i) => (
        <div key={i} className="card px-4 py-3.5">
          <div className="h-3 w-2/3 animate-pulse rounded bg-white/[0.06]" />
          <div className="mt-2.5 h-2.5 w-1/4 animate-pulse rounded bg-white/[0.04]" />
        </div>
      ))}
    </div>
  );
}

/// Clipboard history (T-037): preview + source + time, with copy-back.
export function ClipboardPanel({ entries, loading, loadError, onRefresh }: ClipboardPanelProps) {
  const t = useT();
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);

  async function copyBack(entry: ClipboardEntry, index: number) {
    try {
      await writeText(entry.content);
      setCopiedIndex(index);
      setTimeout(() => setCopiedIndex((current) => (current === index ? null : current)), 1500);
    } catch {
      // Clipboard write can fail without permission; leave the label as-is.
    }
  }

  return (
    <section className="flex h-full flex-col gap-5 animate-fade-in">
      <span className="eyebrow">{t("clipboard.history")}</span>

      {loading ? (
        <ClipboardListSkeleton />
      ) : loadError ? (
        <ErrorState
          title={t("errors.loadFailedTitle")}
          message={errorCodeMessage(loadError.code, t)}
          retryLabel={onRefresh ? t("common.refresh") : undefined}
          onRetry={onRefresh}
        />
      ) : entries.length === 0 ? (
        <EmptyState icon="clipboard" title={t("clipboard.emptyTitle")} hint={t("clipboard.emptyHint")} />
      ) : (
        <ul className="flex flex-col gap-2 overflow-y-auto pr-1">
          {entries.map((entry, index) => {
            const local = entry.source === "local";
            return (
              <li key={`${entry.capturedAtMs}-${index}`} className="group card card-hover px-4 py-3.5">
                <div className="flex items-start justify-between gap-4">
                  <p className="break-words font-mono text-[13px] leading-relaxed text-ink">
                    {truncate(entry.content, 220)}
                  </p>
                  <button
                    type="button"
                    className="btn-ghost shrink-0 opacity-0 transition-opacity group-hover:opacity-100 focus-visible:opacity-100"
                    onClick={() => copyBack(entry, index)}
                  >
                    {copiedIndex === index ? (
                      <>
                        <Icon name="check" className="h-4 w-4" />
                        {t("clipboard.copied")}
                      </>
                    ) : (
                      t("clipboard.copy")
                    )}
                  </button>
                </div>
                <div className="mt-2.5 flex items-center gap-2 text-[11px] text-ink-faint">
                  <span
                    className={`h-1.5 w-1.5 rounded-full ${local ? "bg-ink-ghost" : "bg-paper"}`}
                  />
                  <span>{local ? t("clipboard.thisDevice") : entry.source}</span>
                  <span className="text-ink-ghost">-</span>
                  <span>{formatRelativeTime(entry.capturedAtMs)}</span>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
