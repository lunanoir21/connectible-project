import { Icon } from "./Icon";
import { useT } from "../i18n";
import type { Battery, DaemonStatusDto } from "../lib/types";

interface StatusBarProps {
  connected: boolean;
  deviceName: string;
  battery: Battery | null;
  title: string;
  daemonStatus?: DaemonStatusDto | null;
}

/// Top bar: current panel title on the left, live daemon health + paired
/// device battery on the right. Doubles as a window drag region.
export function StatusBar({ connected, deviceName, battery, title, daemonStatus }: StatusBarProps) {
  const t = useT();
  
  // Determine daemon status: running but not reachable = warning, not running = error
  const daemonRunning = daemonStatus?.running ?? connected;
  const daemonReachable = daemonStatus?.reachable ?? connected;
  
  return (
    <header
      data-tauri-drag-region
      className="flex h-14 items-center justify-between border-b border-line px-6"
    >
      <div className="flex items-baseline gap-3">
        <h1 className="text-[15px] font-semibold tracking-tightest text-ink">{title}</h1>
        {deviceName && (
          <span className="text-xs text-ink-faint">
            {t("status.thisDevice")} -<span className="ml-1 text-ink-muted">{deviceName}</span>
          </span>
        )}
      </div>

      <div className="flex items-center gap-2.5">
        {battery && <BatteryChip battery={battery} />}
        <ConnectionChip connected={connected} />
        <DaemonStatusChip running={daemonRunning} reachable={daemonReachable} />
      </div>
    </header>
  );
}

function ConnectionChip({ connected }: { connected: boolean }) {
  const t = useT();
  return (
    <span
      className="pill bg-surface-raised text-ink-muted"
      role="status"
      aria-label={connected ? t("a11y.daemonConnected") : t("a11y.daemonDisconnected")}
    >
      <span className="relative flex h-2 w-2">
        {connected && (
          <span className="absolute inline-flex h-full w-full animate-pulse-ring rounded-full" />
        )}
        <span
          className={`inline-flex h-2 w-2 rounded-full ${
            connected ? "bg-paper" : "bg-ink-ghost"
          }`}
        />
      </span>
      {connected ? t("status.connected") : t("status.connecting")}
    </span>
  );
}

function DaemonStatusChip({ running, reachable }: { running: boolean; reachable: boolean }) {
  const t = useT();
  if (running && reachable) return null; // Same as connected, don't duplicate
  
  return (
    <span
      className="pill bg-surface-raised text-ink-muted"
      role="status"
      aria-label={t("a11y.daemonStatus")}
    >
      <span className="relative flex h-2 w-2">
        {!running && (
          <span className="absolute inline-flex h-full w-full animate-pulse-ring rounded-full bg-danger" />
        )}
        <span
          className={`inline-flex h-2 w-2 rounded-full ${
            running && !reachable ? "bg-ink-muted" : !running ? "bg-danger" : "bg-paper"
          }`}
        />
      </span>
      {!running ? t("status.daemonStopped") : t("status.daemonUnreachable")}
    </span>
  );
}

function BatteryChip({ battery }: { battery: Battery }) {
  const t = useT();
  return (
    <span className="pill bg-surface-raised text-ink-muted" aria-label={t("a11y.pairedDeviceBattery")}>
      <Icon name={battery.isCharging ? "bolt" : "battery"} className="h-3.5 w-3.5 text-ink-faint" />
      <span className="nums font-medium text-ink">{battery.percentage}%</span>
    </span>
  );
}
