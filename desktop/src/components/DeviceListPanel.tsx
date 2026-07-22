import { useState } from "react";
import { ipc, type IpcError } from "../lib/ipc";
import type { Device, NearbyDevice } from "../lib/types";
import { formatRelativeTime } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { Icon } from "./Icon";
import { useT } from "../i18n";

interface DeviceListPanelProps {
  devices: Device[];
  nearby: NearbyDevice[];
  // True until the first ListDevices response completes (T-311); shows
  // a loading skeleton distinct from a genuinely empty paired list.
  loading: boolean;
  // Set when the fetch behind `devices`/`nearby` itself failed (T-601),
  // distinct from `error` below which is local to this panel's own
  // pair/forget actions.
  loadError?: IpcError | null;
  onPairStarted: (device: NearbyDevice, pinExpiresAtMs: number) => void;
  onRefresh: () => void;
}

function monogram(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function Avatar({ name, online }: { name: string; online?: boolean }) {
  return (
    <div className="relative">
      <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-line bg-gradient-to-b from-white/[0.08] to-transparent text-xs font-semibold tracking-wide text-ink-muted">
        {monogram(name)}
      </div>
      {online !== undefined && (
        <span
          className={`absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-surface-raised ${
            online ? "bg-paper" : "bg-ink-ghost"
          }`}
        />
      )}
    </div>
  );
}

/// Placeholder rows shown before the first ListDevices response (T-311)
/// -- deliberately distinct from EmptyState (no icon/copy claiming
/// there are "no devices yet", since we simply don't know yet).
function DeviceListSkeleton() {
  return (
    <div className="flex flex-col gap-2" data-testid="device-list-skeleton" aria-busy="true">
      {[0, 1, 2].map((i) => (
        <div key={i} className="card flex items-center gap-3.5 px-4 py-3.5">
          <div className="h-10 w-10 shrink-0 animate-pulse rounded-xl bg-white/[0.06]" />
          <div className="flex min-w-0 flex-1 flex-col gap-2">
            <div className="h-3 w-1/3 animate-pulse rounded bg-white/[0.06]" />
            <div className="h-2.5 w-1/4 animate-pulse rounded bg-white/[0.04]" />
          </div>
          <div className="h-5 w-14 shrink-0 animate-pulse rounded-full bg-white/[0.04]" />
        </div>
      ))}
    </div>
  );
}

/// Paired + nearby (mDNS) devices with a pair action (T-035).
export function DeviceListPanel({ devices, nearby, loading, loadError, onPairStarted, onRefresh }: DeviceListPanelProps) {
  const t = useT();
  const [pairingId, setPairingId] = useState<string | null>(null);
  const [forgettingId, setForgettingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const pairedIds = new Set(devices.map((d) => d.deviceId));
  const unpaired = nearby.filter((n) => !pairedIds.has(n.deviceId));

  async function startPair(device: NearbyDevice) {
    setPairingId(device.deviceId);
    setError(null);
    const result = await ipc.pairWithDevice(device.addr, device.port);
    setPairingId(null);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    onPairStarted(device, result.value.pinExpiresAtMs);
  }

  /// T-307: permanently forgets a paired device. Unlike disconnect,
  /// this removes it from the paired-devices store entirely, so it
  /// disappears from `devices` on the next refresh and a future
  /// reconnect needs a fresh PIN exchange.
  async function forgetDevice(device: Device) {
    setForgettingId(device.deviceId);
    setError(null);
    const result = await ipc.forgetDevice(device.deviceId);
    setForgettingId(null);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    onRefresh();
  }

  const nothing = !loading && devices.length === 0 && unpaired.length === 0;

  return (
    <section className="flex h-full flex-col gap-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="eyebrow">{t("devices.connected")}</span>
          <span className="rounded-full bg-white/[0.06] px-2 text-[11px] font-semibold text-ink-muted nums">
            {devices.length}
          </span>
        </div>
        <button type="button" className="btn-ghost" onClick={onRefresh}>
          <Icon name="refresh" className="h-4 w-4" />
          {t("common.refresh")}
        </button>
      </div>

      {error && (
        <p className="rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-danger" role="alert">
          {error}
        </p>
      )}

      {loading ? (
        <DeviceListSkeleton />
      ) : loadError ? (
        <ErrorState
          title={t("errors.loadFailedTitle")}
          message={errorCodeMessage(loadError.code, t)}
          retryLabel={t("common.refresh")}
          onRetry={onRefresh}
        />
      ) : nothing ? (
        <EmptyState icon="devices" title={t("devices.emptyTitle")} hint={t("devices.emptyHint")} />
      ) : (
        <div className="flex flex-col gap-6 overflow-y-auto pr-1">
          {devices.length > 0 && (
            <div className="flex flex-col gap-2">
              {devices.map((device) => (
                <div key={device.deviceId} className="card card-hover flex items-center gap-3.5 px-4 py-3.5">
                  <Avatar name={device.deviceName} online={device.online} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-ink">{device.deviceName}</p>
                    <p className="text-xs text-ink-faint">
                      {device.online
                        ? t("devices.onlineNow")
                        : t("devices.lastSeen", { time: formatRelativeTime(device.lastSeenMs) })}
                    </p>
                  </div>
                  <span
                    className={`pill ${
                      device.online
                        ? "border-white/15 bg-white/[0.06] text-ink"
                        : "bg-surface-overlay text-ink-faint"
                    }`}
                  >
                    {device.online ? t("common.online") : t("common.offline")}
                  </span>
                  <button
                    type="button"
                    className="btn-ghost text-danger hover:bg-danger/10 disabled:opacity-40"
                    disabled={forgettingId === device.deviceId}
                    onClick={() => void forgetDevice(device)}
                    title={t("menu.forget")}
                    aria-label={t("menu.forget")}
                  >
                    <Icon name="close" className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          )}

          {unpaired.length > 0 && (
            <div className="flex flex-col gap-2">
              <span className="eyebrow px-1">{t("devices.nearby")}</span>
              {unpaired.map((device) => (
                <div key={device.deviceId} className="card card-hover flex items-center gap-3.5 px-4 py-3.5">
                  <Avatar name={device.deviceName} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-ink">{device.deviceName}</p>
                    <p className="nums text-xs text-ink-faint">
                      {device.addr}:{device.port}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={pairingId === device.deviceId}
                    onClick={() => startPair(device)}
                  >
                    {pairingId === device.deviceId ? t("common.pairing") : t("common.pair")}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </section>
  );
}
