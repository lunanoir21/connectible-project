import { useEffect, useRef, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { ipc, type IpcError } from "../lib/ipc";
import type { Device, NearbyDevice, TransferProgress } from "../lib/types";
import { formatBytes, transferPercent } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { Icon } from "./Icon";
import { useT, type Translate } from "../i18n";

interface TransferPanelProps {
  transfers: Record<string, TransferProgress>;
  devices: Device[];
  nearby: NearbyDevice[];
  // True until the daemon's initial device list (transfer targets) has
  // loaded (T-601) -- mirrors DeviceListPanel's T-311 loading skeleton
  // so this panel doesn't briefly flash "No transfers yet" while the
  // rest of the app is still loading its first snapshot.
  loading?: boolean;
  // Set when that initial fetch failed outright, distinct from `error`
  // below which is local to this panel's own send-file action.
  loadError?: IpcError | null;
  onRefresh?: () => void;
}

/// Placeholder rows shown before the daemon's first snapshot has loaded
/// (T-601) -- same skeleton pattern DeviceListPanel established for
/// T-311, deliberately distinct from EmptyState's "nothing here yet"
/// copy since we simply don't know yet.
function TransferListSkeleton() {
  return (
    <div className="flex flex-col gap-2.5" data-testid="transfer-list-skeleton" aria-busy="true">
      {[0, 1].map((i) => (
        <div key={i} className="card px-4 py-3.5">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 shrink-0 animate-pulse rounded-lg bg-white/[0.06]" />
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <div className="h-3 w-1/3 animate-pulse rounded bg-white/[0.06]" />
              <div className="h-2.5 w-1/4 animate-pulse rounded bg-white/[0.04]" />
            </div>
          </div>
          <div className="mt-3 h-1.5 w-full animate-pulse rounded-full bg-white/[0.06]" />
        </div>
      ))}
    </div>
  );
}

/// File transfer panel (T-038), rebuilt: native picker + drag-and-drop
/// send, live incoming/outgoing progress rendered as constellation-style
/// "ties" (one endpoint per device), and native folder/file reveal that
/// actually works across Linux desktops (see commands::open_path).
export function TransferPanel({ transfers, nearby, loading, loadError, onRefresh }: TransferPanelProps) {
  const t = useT();
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [dragging, setDragging] = useState(false);

  // Every mDNS-visible peer is a candidate target: reachability (a live
  // addr:port) is what a send actually needs, which only nearby carries.
  const targets = nearby;
  const [targetId, setTargetId] = useState<string>(targets[0]?.deviceId ?? "");
  const target = targets.find((c) => c.deviceId === targetId) ?? targets[0] ?? null;

  // Local path of each file this session sent, keyed by the transfer_id
  // send_file returns, so a finished outgoing row can offer "Open file".
  // Received files aren't here -- the daemon writes those, so incoming
  // rows reveal the download folder instead.
  const sentPaths = useRef<Map<string, string>>(new Map());

  async function sendPaths(paths: string[]) {
    setError(null);
    if (!target) {
      setError(t("transfers.selectTarget"));
      return;
    }
    setSending(true);
    for (const path of paths) {
      const result = await ipc.sendFile(target.addr, target.port, path, target.deviceId);
      if (result.ok) {
        sentPaths.current.set(result.value, path);
      } else {
        setError(errorCodeMessage(result.error.code, t));
        break;
      }
    }
    setSending(false);
  }

  async function pickAndSend() {
    const selected = await open({ multiple: true, directory: false });
    if (selected == null) return;
    await sendPaths(Array.isArray(selected) ? selected : [selected]);
  }

  async function openReceivedFolder() {
    setError(null);
    const dir = await ipc.getDownloadDir();
    if (!dir.ok) {
      setError(errorCodeMessage(dir.error.code, t));
      return;
    }
    const opened = await ipc.openPath(dir.value);
    if (!opened.ok) setError(errorCodeMessage(opened.error.code, t));
  }

  async function openSentFile(transferId: string) {
    const path = sentPaths.current.get(transferId);
    if (!path) return;
    const opened = await ipc.openPath(path);
    if (!opened.ok) setError(errorCodeMessage(opened.error.code, t));
  }

  // Latest sender kept in a ref so the drag-drop listener (subscribed
  // once) always sends via the currently-selected target without
  // re-subscribing on every render.
  const sendPathsRef = useRef(sendPaths);
  sendPathsRef.current = sendPaths;

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    // Guarded: outside a Tauri webview (unit tests, storybook) there is
    // no window bridge, so getCurrentWebview() throws -- swallow it and
    // fall back to the click-to-browse path rather than crashing mount.
    try {
      void getCurrentWebview()
        .onDragDropEvent((event) => {
          const payload = event.payload;
          if (payload.type === "enter" || payload.type === "over") {
            setDragging(true);
          } else if (payload.type === "leave") {
            setDragging(false);
          } else if (payload.type === "drop") {
            setDragging(false);
            if (payload.paths.length > 0) void sendPathsRef.current(payload.paths);
          }
        })
        .then((un) => {
          if (disposed) un();
          else unlisten = un;
        })
        .catch(() => {});
    } catch {
      /* not running inside a Tauri webview */
    }
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  const rows = Object.values(transfers).sort((a, b) => b.transferId.localeCompare(a.transferId));
  const active = rows.filter((r) => !r.completed && !r.failed);
  const history = rows.filter((r) => r.completed || r.failed);

  return (
    <section className="relative flex h-full flex-col gap-5 animate-fade-in">
      <div className="flex items-center justify-between gap-3">
        <span className="eyebrow">{t("transfers.eyebrow")}</span>
        <button type="button" onClick={openReceivedFolder} className="btn-ghost text-sm" title={t("transfers.openFolder")}>
          <Icon name="folder" className="h-4 w-4" />
          {t("transfers.openFolder")}
        </button>
      </div>

      {/* Send composer: choose a target, then drop files anywhere on the
          panel or browse. */}
      <div className="card p-4">
        <div className="flex flex-wrap items-center gap-2.5">
          <span className="text-xs font-medium uppercase tracking-wide text-ink-faint">{t("transfers.to")}</span>
          <div className="relative min-w-0 flex-1">
            <select
              aria-label={t("transfers.selectTargetLabel")}
              value={target?.deviceId ?? ""}
              onChange={(e) => setTargetId(e.target.value)}
              className="field w-full appearance-none py-2 pr-8 text-sm"
            >
              {targets.length === 0 && <option value="">{t("transfers.noReachable")}</option>}
              {targets.map((opt) => (
                <option key={opt.deviceId} value={opt.deviceId}>
                  {opt.deviceName}
                </option>
              ))}
            </select>
            <Icon name="arrow-down" className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-faint" />
          </div>
          <button type="button" className="btn-primary" disabled={sending || targets.length === 0} onClick={pickAndSend}>
            <Icon name="arrow-up" className="h-4 w-4" strokeWidth={1.9} />
            {sending ? t("transfers.sending") : t("transfers.sendFile")}
          </button>
        </div>
        <p className="mt-2.5 text-xs text-ink-faint">{t("transfers.dropHint")}</p>
      </div>

      {error && (
        <p className="rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-danger" role="alert">
          {error}
        </p>
      )}

      {loading ? (
        <TransferListSkeleton />
      ) : loadError ? (
        <ErrorState
          title={t("errors.loadFailedTitle")}
          message={errorCodeMessage(loadError.code, t)}
          retryLabel={onRefresh ? t("common.refresh") : undefined}
          onRetry={onRefresh}
        />
      ) : rows.length === 0 ? (
        <EmptyState icon="transfer" title={t("transfers.emptyTitle")} hint={t("transfers.emptyHint")} />
      ) : (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto pr-1">
          {active.length > 0 && (
            <TransferGroup label={t("transfers.sectionActive")}>
              {active.map((row) => (
                <TransferRow key={row.transferId} row={row} t={t} onOpenFolder={openReceivedFolder} onOpenFile={openSentFile} canOpenFile={sentPaths.current.has(row.transferId)} />
              ))}
            </TransferGroup>
          )}
          {history.length > 0 && (
            <TransferGroup label={t("transfers.sectionHistory")}>
              {history.map((row) => (
                <TransferRow key={row.transferId} row={row} t={t} onOpenFolder={openReceivedFolder} onOpenFile={openSentFile} canOpenFile={sentPaths.current.has(row.transferId)} />
              ))}
            </TransferGroup>
          )}
        </div>
      )}

      {dragging && (
        <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center rounded-2xl border-2 border-dashed border-white/30 bg-black/70 backdrop-blur-sm">
          <div className="flex flex-col items-center gap-2 text-center">
            <Icon name="arrow-down" className="h-7 w-7 text-ink" />
            <p className="text-sm font-medium text-ink">
              {target ? t("transfers.dropTitle", { name: target.deviceName }) : t("transfers.dropNoTarget")}
            </p>
          </div>
        </div>
      )}
    </section>
  );
}

function TransferGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2.5">
      <span className="eyebrow px-0.5">{label}</span>
      {children}
    </div>
  );
}

function TransferRow({
  row,
  t,
  onOpenFolder,
  onOpenFile,
  canOpenFile,
}: {
  row: TransferProgress;
  t: Translate;
  onOpenFolder: () => void;
  onOpenFile: (transferId: string) => void;
  canOpenFile: boolean;
}) {
  const outgoing = row.direction === "outgoing";
  const done = row.completed && !row.failed;
  return (
    <div className="card px-4 py-3.5">
      <div className="flex items-center gap-3">
        <div
          className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-line ${
            done ? "bg-white/[0.08] text-ink" : row.failed ? "text-danger" : "bg-surface-overlay text-ink-faint"
          }`}
        >
          <Icon name={outgoing ? "arrow-up" : "arrow-down"} className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-ink">{row.fileName}</p>
          <p className="nums text-[11px] text-ink-faint">
            {statusLabel(row, t)} - {formatBytes(row.bytesTransferred)}
            {row.totalBytes > 0 && ` / ${formatBytes(row.totalBytes)}`}
          </p>
        </div>
        <span className="nums text-xs font-medium text-ink-muted">
          {transferPercent(row.bytesTransferred, row.totalBytes)}%
        </span>
        {outgoing && !row.completed && !row.failed && (
          <button
            type="button"
            onClick={() => void ipc.cancelTransfer(row.transferId)}
            aria-label={t("transfers.cancel")}
            title={t("transfers.cancel")}
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-faint transition-colors hover:bg-white/[0.06] hover:text-ink"
          >
            <Icon name="close" className="h-4 w-4" />
          </button>
        )}
      </div>
      <Tie transfer={row} />
      {done && (
        <div className="mt-2.5 flex justify-end">
          {outgoing ? (
            canOpenFile && (
              <button type="button" onClick={() => onOpenFile(row.transferId)} className="btn-ghost px-2.5 py-1 text-xs">
                <Icon name="file" className="h-3.5 w-3.5" />
                {t("transfers.openFile")}
              </button>
            )
          ) : (
            <button type="button" onClick={onOpenFolder} className="btn-ghost px-2.5 py-1 text-xs">
              <Icon name="folder" className="h-3.5 w-3.5" />
              {t("transfers.openFolder")}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

/// Progress as a constellation "tie": a hairline line strung between two
/// endpoint stars (this device and the peer), the bright segment growing
/// along it and the far star lighting up on completion. Reuses the Home
/// screen's tie language so a transfer reads as data crossing a tie.
function Tie({ transfer }: { transfer: TransferProgress }) {
  const pct = transferPercent(transfer.bytesTransferred, transfer.totalBytes);
  const active = !transfer.completed && !transfer.failed;
  const done = transfer.completed && !transfer.failed;
  const fill = transfer.failed ? "bg-danger" : "bg-paper";
  return (
    <div className="mt-3 flex items-center gap-2.5">
      <span className="h-2 w-2 shrink-0 rounded-full bg-paper/70" aria-hidden="true" />
      <div
        className="relative h-1.5 flex-1 overflow-hidden rounded-full bg-white/[0.06]"
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        {/* Fixed-width track, transform-scaled fill: avoids animating
            `width` (which forces reflow every tick). scaleX is
            compositor-only. */}
        <div
          className={`h-full w-full origin-left rounded-full ${fill} transition-transform duration-300 ease-out ${active ? "shimmer" : ""}`}
          style={{ transform: `scaleX(${pct / 100})` }}
        />
      </div>
      <span
        className={`h-2 w-2 shrink-0 rounded-full border transition-colors ${
          done ? "border-paper bg-paper" : transfer.failed ? "border-danger bg-transparent" : "border-line bg-transparent"
        }`}
        aria-hidden="true"
      />
    </div>
  );
}

function statusLabel(row: TransferProgress, t: Translate): string {
  if (row.canceled) return t("transfers.statusCanceled");
  if (row.failed) return t("transfers.statusFailed");
  if (row.completed) return t("transfers.statusCompleted");
  return row.direction === "outgoing" ? t("transfers.statusSending") : t("transfers.statusReceiving");
}
