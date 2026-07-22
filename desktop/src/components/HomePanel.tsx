import { useState, useCallback, useEffect, memo } from "react";
import { ipc, type IpcError } from "../lib/ipc";
import type { Device, LocalAddresses, NearbyDevice } from "../lib/types";
import { formatRelativeTime } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { ErrorState } from "./ErrorState";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { Icon, type IconName } from "./Icon";
import { useT, useI18n, type Translate } from "../i18n";
import type { PanelId } from "./Sidebar";

interface HomePanelProps {
  deviceName: string;
  devices: Device[];
  nearby: NearbyDevice[];
  onPairStarted: (device: NearbyDevice, pinExpiresAtMs: number) => void;
  // Switches the app's active panel (T-101): lets Quick Actions actually
  // navigate instead of being comment-only no-ops. Mirrors the callback
  // Sidebar already receives from App.tsx.
  onNavigate: (panel: PanelId) => void;
  // Re-fetches devices/local state (T-102): called after a disconnect/
  // forget so the just-updated roster is reflected without the user
  // having to manually leave and re-enter the panel.
  onRefresh: () => void;
  // True until the daemon's first ListDevices response completes
  // (T-311/T-601), so the constellation shows a loading placeholder
  // instead of conflating "still loading" with "genuinely no devices".
  loading?: boolean;
  loadError?: IpcError | null;
}

function monogram(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

// T-604: routed through t() so platform labels translate instead of
// hardcoding English literals -- WAYLAND is checked before the plain
// LINUX fallback since PLATFORM_LINUX_WAYLAND also contains "LINUX".
function platformLabel(platform: string, t: Translate): string {
  const p = platform.toUpperCase();
  if (p.includes("ANDROID")) return t("platform.android");
  if (p.includes("IOS")) return t("platform.ios");
  if (p.includes("MACOS")) return t("platform.macos");
  if (p.includes("WINDOWS")) return t("platform.windows");
  if (p.includes("WAYLAND")) return t("platform.linuxWayland");
  if (p.includes("LINUX")) return t("platform.linux");
  return platform;
}

// Bound the pairable/nearby list (T-E7): a crowded LAN can advertise many
// mDNS peers at once, and rendering every one would let the constellation --
// and the DOM node count -- grow without limit. We show at most this many and
// collapse the rest into a quiet "+X more" count. The overflow is expected to
// be rare (most networks have a handful of devices), so a hard cap plus a
// count is enough; there's no full "browse all" surface by design.
const MAX_PAIRABLE = 8;

interface QuickAction {
  id: string;
  label: string;
  icon: IconName;
  onClick: () => void;
  disabled?: boolean;
  // The one action given weight: the thing you actually reach for once a
  // peer is online. Everything else stays a quiet ghost chip.
  primary?: boolean;
}

type InfoTarget =
  | { kind: "paired"; device: Device }
  | { kind: "nearby"; device: NearbyDevice };

export function HomePanel({ deviceName, devices, nearby, onPairStarted, onNavigate, onRefresh, loading, loadError }: HomePanelProps) {
  const t = useT();
  const [pairingId, setPairingId] = useState<string | null>(null);
  const [forgettingId, setForgettingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<InfoTarget | null>(null);
  const [showManual, setShowManual] = useState(false);

  const pairedIds = new Set(devices.map((d) => d.deviceId));
  const pairable = nearby.filter((n) => !pairedIds.has(n.deviceId));
  // Only the first MAX_PAIRABLE are drawn as stars; the remainder are counted,
  // not rendered, so the constellation stays bounded no matter how many
  // advertisers appear (T-E7). StatusStrip still reports the true total below.
  const visiblePairable = pairable.slice(0, MAX_PAIRABLE);
  const hiddenNearby = pairable.length - visiblePairable.length;
  // The number of *paired peers currently online* is the real "am I
  // connected to something" signal -- unlike the daemon's own
  // local-liveness flag (previously misused here for this purpose, see
  // App.tsx's ConnectingOverlay for that separate concern), this
  // actually reflects whether a remote device is reachable right now.
  const onlineDevices = devices.filter((d) => d.online);

  const startPair = useCallback(async (device: NearbyDevice) => {
    setPairingId(device.deviceId);
    setError(null);
    const result = await ipc.pairWithDevice(device.addr, device.port);
    setPairingId(null);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    onPairStarted(device, result.value.pinExpiresAtMs);
  }, [onPairStarted, t]);

  // Manual pairing (no mDNS): the user types the peer's address, we
  // synthesize a NearbyDevice from it, and feed it straight into the
  // same connect-by-addr:port flow discovery would have produced. The
  // daemon dials addr:port over TLS directly -- multicast/mDNS is only
  // ever used to *find* that address, never to connect.
  const startManual = useCallback(async (host: string, port: number) => {
    setShowManual(false);
    await startPair({ deviceId: `manual:${host}:${port}`, deviceName: host, platform: "", addr: host, port });
  }, [startPair]);

  const handleDisconnect = useCallback(async (device: Device) => {
    setError(null);
    const result = await ipc.disconnectDevice(device.deviceId);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    setInfo(null);
    onRefresh();
  }, [onRefresh, t]);

  const handleForget = useCallback(async (device: Device) => {
    if (!window.confirm(t("menu.forgetConfirm"))) return;
    setForgettingId(device.deviceId);
    setError(null);
    const result = await ipc.forgetDevice(device.deviceId);
    setForgettingId(null);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      return;
    }
    setInfo(null);
    onRefresh();
  }, [onRefresh, t]);

  const quickActions: QuickAction[] = [
    {
      id: "send-file",
      label: t("transfers.sendFile"),
      icon: "transfer",
      onClick: () => onNavigate("transfers"),
      disabled: onlineDevices.length === 0,
      primary: true,
    },
    {
      id: "clipboard",
      label: t("clipboard.history"),
      icon: "clipboard",
      onClick: () => onNavigate("clipboard"),
    },
    {
      id: "remote-input",
      label: t("input.eyebrow"),
      icon: "cursor",
      onClick: () => onNavigate("input"),
      disabled: onlineDevices.length === 0,
    },
    {
      id: "notifications",
      label: t("notifications.eyebrow"),
      icon: "bell",
      onClick: () => onNavigate("notifications"),
    },
    {
      id: "settings",
      label: t("nav.settings"),
      icon: "settings",
      onClick: () => onNavigate("settings"),
    },
    {
      id: "doctor",
      label: t("doctor.title"),
      icon: "shield",
      onClick: () => onNavigate("doctor"),
    },
  ];

  return (
    <section className="flex h-full flex-col animate-fade-in">
      <header className="flex items-center justify-between gap-3">
        <p className="min-w-0 truncate text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-faint">
          {t("home.thisDevice")}
          <span className="mx-1.5 text-ink-ghost">/</span>
          <span className="text-ink-muted">{deviceName}</span>
        </p>
        <div className="flex shrink-0 items-center gap-1">
          <button type="button" className="btn-ghost text-xs" onClick={() => setShowManual(true)}>
            <Icon name="link" className="h-3.5 w-3.5" />
            {t("home.connectByAddress")}
          </button>
          <button type="button" className="btn-ghost text-xs" onClick={onRefresh}>
            <Icon name="refresh" className="h-3.5 w-3.5" />
            {t("common.refresh")}
          </button>
        </div>
      </header>

      {error && (
        <div className="mt-4 rounded-lg border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger" role="alert">
          {error}
        </div>
      )}

      <div className="mt-2 flex-1 overflow-y-auto pr-1">
        {loadError ? (
          <div className="mt-8">
            <ErrorState
              title={t("errors.loadFailedTitle")}
              message={errorCodeMessage(loadError.code, t)}
              retryLabel={t("common.refresh")}
              onRetry={onRefresh}
            />
          </div>
        ) : (
          <>
            <StatusStrip
              devices={devices}
              onlineCount={onlineDevices.length}
              nearbyCount={pairable.length}
              t={t}
            />

            <div className="mx-auto mt-6 w-full max-w-[560px]">
              <QuickActions actions={quickActions} />
            </div>

            <div className="mx-auto mt-7 w-full max-w-[560px]">
              <HomeDeviceList
                deviceName={deviceName}
                devices={devices}
                pairable={visiblePairable}
                pairingId={pairingId}
                loading={loading}
                onPair={startPair}
                onShowInfo={setInfo}
                t={t}
              />

              {hiddenNearby > 0 && (
                <p className="mt-2 text-center text-xs text-ink-faint" data-testid="home-nearby-more">
                  {t("home.nearbyMore", { count: hiddenNearby })}
                </p>
              )}
            </div>
          </>
        )}
      </div>

      {showManual && (
        <ManualConnectDialog onClose={() => setShowManual(false)} onConnect={startManual} t={t} />
      )}

      {info && (
        <DeviceInfoDialog
          target={info}
          onClose={() => setInfo(null)}
          onDisconnect={info.kind === "paired" ? () => void handleDisconnect(info.device) : undefined}
          onForget={info.kind === "paired" ? () => void handleForget(info.device) : undefined}
          forgetting={info.kind === "paired" && forgettingId === info.device.deviceId}
          t={t}
        />
      )}
    </section>
  );
}

// ===== Device list =====
// The home's device roster, replacing the former constellation/radar
// view (T-2.4): this device's own row, then a "Paired" section, then a
// "Nearby" section for unpaired mDNS advertisers -- same grouped-card,
// hairline-row language as Settings/Devices rather than a bespoke
// layout. Paired rows open the info dialog; nearby rows pair directly.

interface HomeDeviceListProps {
  deviceName: string;
  devices: Device[];
  pairable: NearbyDevice[];
  pairingId: string | null;
  loading?: boolean;
  onPair: (device: NearbyDevice) => void;
  onShowInfo: (target: InfoTarget) => void;
  t: Translate;
}

function HomeDeviceList({ deviceName, devices, pairable, pairingId, loading, onPair, onShowInfo, t }: HomeDeviceListProps) {
  if (loading) {
    return (
      <div className="flex flex-col gap-2" data-testid="home-devices-skeleton" aria-busy="true">
        {[0, 1].map((i) => (
          <div key={i} className="card flex items-center gap-3.5 px-4 py-3.5">
            <div className="h-10 w-10 shrink-0 animate-pulse rounded-xl bg-white/[0.06]" />
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <div className="h-3 w-1/3 animate-pulse rounded bg-white/[0.06]" />
              <div className="h-2.5 w-1/4 animate-pulse rounded bg-white/[0.04]" />
            </div>
          </div>
        ))}
      </div>
    );
  }

  const empty = devices.length === 0 && pairable.length === 0;

  return (
    <div className="flex flex-col gap-6">
      <div className="card flex items-center gap-3.5 px-4 py-3.5">
        <HomeAvatar name={deviceName || "Me"} online />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-ink">{deviceName || t("status.thisDevice")}</p>
          <p className="text-xs text-ink-faint">{t("status.thisDevice")}</p>
        </div>
      </div>

      {devices.length > 0 && (
        <div className="flex flex-col gap-2">
          <span className="eyebrow px-1">{t("home.paired")}</span>
          {devices.map((d) => (
            <PairedRow key={d.deviceId} device={d} onShowInfo={onShowInfo} t={t} />
          ))}
        </div>
      )}

      {pairable.length > 0 && (
        <div className="flex flex-col gap-2">
          <span className="eyebrow px-1">{t("devices.nearby")}</span>
          {pairable.map((d) => (
            <NearbyRow key={d.deviceId} device={d} pairing={pairingId === d.deviceId} onPair={onPair} t={t} />
          ))}
        </div>
      )}

      {empty && <p className="text-center text-sm text-ink-faint">{t("home.notPairedHint")}</p>}
    </div>
  );
}

// Memoized so a poll-driven HomePanel re-render (new `devices`/`nearby`
// array references on every refresh tick) doesn't force every row to
// re-render -- only rows whose own device object actually changed do.
const PairedRow = memo(function PairedRow({
  device: d,
  onShowInfo,
  t,
}: {
  device: Device;
  onShowInfo: (target: InfoTarget) => void;
  t: Translate;
}) {
  // Own hook rather than a prop: a locale change re-renders context
  // consumers even through memo, so the row's relative time follows the
  // language switch without HomePanel threading locale into every row.
  const { locale } = useI18n();
  return (
    <button
      type="button"
      onClick={() => onShowInfo({ kind: "paired", device: d })}
      aria-label={`${d.deviceName} - ${d.online ? t("common.online") : t("common.offline")}`}
      className="card card-hover flex items-center gap-3.5 px-4 py-3.5 text-left animate-fade-in"
    >
      <HomeAvatar name={d.deviceName} online={d.online} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-ink">{d.deviceName}</p>
        <p className="text-xs text-ink-faint">
          {d.online ? t("devices.onlineNow") : t("devices.lastSeen", { time: formatRelativeTime(d.lastSeenMs, locale) })}
        </p>
      </div>
      <span
        className={`pill ${d.online ? "border-white/15 bg-white/[0.06] text-ink" : "bg-surface-overlay text-ink-faint"}`}
      >
        {d.online ? t("common.online") : t("common.offline")}
      </span>
    </button>
  );
});

const NearbyRow = memo(function NearbyRow({
  device: d,
  pairing,
  onPair,
  t,
}: {
  device: NearbyDevice;
  pairing: boolean;
  onPair: (device: NearbyDevice) => void;
  t: Translate;
}) {
  return (
    <button
      type="button"
      onClick={() => !pairing && onPair(d)}
      disabled={pairing}
      aria-label={`${d.deviceName} - ${t("devices.nearby")}`}
      className="card card-hover flex items-center gap-3.5 px-4 py-3.5 text-left disabled:opacity-70 animate-fade-in"
    >
      <HomeAvatar name={d.deviceName} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-ink">{d.deviceName}</p>
        <p className="nums text-xs text-ink-faint">
          {d.addr}:{d.port}
        </p>
      </div>
      <span className="pill border-white/15 bg-white/[0.06] text-ink">
        {pairing ? t("common.pairing") : t("common.pair")}
      </span>
    </button>
  );
});

function HomeAvatar({ name, online }: { name: string; online?: boolean }) {
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

// ===== Status Strip =====
// One quiet line under the picture, answering in words what the
// constellation shows: who you're linked to, and the count breakdown.

function StatusStrip({
  devices,
  onlineCount,
  nearbyCount,
  t,
}: {
  devices: Device[];
  onlineCount: number;
  nearbyCount: number;
  t: Translate;
}) {
  let statusText: string;
  if (devices.length === 0) {
    statusText = t("home.notPairedYet");
  } else if (onlineCount === 0) {
    statusText = t("home.notConnected");
  } else if (onlineCount === 1) {
    const solo = devices.find((d) => d.online);
    statusText = t("home.connectedToOne", { name: solo?.deviceName ?? "" });
  } else {
    statusText = t("home.connectedToMany", { count: onlineCount });
  }
  const live = onlineCount > 0;

  return (
    <div className="mx-auto mt-1 flex w-full max-w-[560px] flex-col items-center gap-3">
      <div className="flex items-center gap-2.5">
        <span className="relative flex h-2 w-2">
          {live && <span className="absolute inset-0 animate-pulse-ring rounded-full" />}
          <span className={`h-2 w-2 rounded-full ${live ? "bg-paper" : "bg-ink-ghost"}`} />
        </span>
        <h1 className="text-center text-[19px] font-semibold leading-tight tracking-tightest text-ink">{statusText}</h1>
      </div>

      {devices.length > 0 && (
        <div className="flex items-center gap-2.5 text-xs">
          <MetaCount value={devices.length} label={t("home.statPaired")} />
          <span className="text-ink-ghost">&middot;</span>
          <MetaCount value={onlineCount} label={t("common.online")} />
          <span className="text-ink-ghost">&middot;</span>
          <MetaCount value={nearbyCount} label={t("devices.nearby")} />
        </div>
      )}
    </div>
  );
}

function MetaCount({ value, label }: { value: number; label: string }) {
  return (
    <span className="flex items-baseline gap-1.5">
      <span className={`nums text-sm font-semibold leading-none ${value > 0 ? "text-ink" : "text-ink-ghost"}`}>{value}</span>
      <span className="text-ink-faint">{label}</span>
    </span>
  );
}

// ===== Quick Actions =====
// A quiet wrapping row of chips -- deliberately not a tile grid, which
// gives six equal-weight destinations the same visual mass as the
// screen's real content. Only Send file (the thing you do once a peer is
// live) carries any emphasis.

function QuickActions({ actions }: { actions: QuickAction[] }) {
  return (
    <div className="flex flex-wrap justify-center gap-2">
      {actions.map((action, i) => (
        <button
          key={action.id}
          type="button"
          onClick={action.onClick}
          disabled={action.disabled}
          style={{ animationDelay: `${Math.min(i, 10) * 35}ms`, animationFillMode: "backwards" }}
          className={`group inline-flex animate-fade-in items-center gap-2 rounded-full border px-3.5 py-2 text-xs font-medium
            transition-all duration-150 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/25
            disabled:pointer-events-none disabled:opacity-40
            ${
              action.primary
                ? "border-line-strong bg-white/[0.06] text-ink hover:bg-white/[0.1]"
                : "border-line text-ink-muted hover:border-line-strong hover:bg-white/[0.04] hover:text-ink"
            }`}
        >
          <Icon
            name={action.icon}
            className={`h-4 w-4 transition-colors duration-150 ${
              action.primary ? "text-ink" : "text-ink-faint group-hover:text-ink"
            }`}
          />
          {action.label}
        </button>
      ))}
    </div>
  );
}

// ===== Manual Connect =====
// The escape hatch for networks where mDNS/multicast is blocked: type the
// peer's address instead of discovering it. Feeds the existing pair flow.

const DEFAULT_PORT = 58231;

function ManualConnectDialog({
  onClose,
  onConnect,
  t,
}: {
  onClose: () => void;
  onConnect: (host: string, port: number) => void;
  t: Translate;
}) {
  const [host, setHost] = useState("");
  const [port, setPort] = useState(String(DEFAULT_PORT));
  const [error, setError] = useState(false);
  // This device's own LAN endpoint, so the user can read it off to the
  // peer they want to reach them (the reverse of typing one in above).
  // Mirrors mobile's _YourAddress; the webview can't enumerate
  // interfaces, so the native `local_addresses` command does it.
  const [own, setOwn] = useState<LocalAddresses | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let alive = true;
    ipc.localAddresses().then((r) => {
      if (alive && r.ok) setOwn(r.value);
    });
    return () => {
      alive = false;
    };
  }, []);

  const ownAddress =
    own && own.addresses.length > 0 ? `${own.addresses[0]}:${own.port}` : null;

  const copyOwn = async () => {
    if (!ownAddress) return;
    try {
      await writeText(ownAddress);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      // Clipboard write can fail (permissions, headless); silently
      // ignore -- the address is still shown for the user to read off.
    }
  };

  const submit = () => {
    const h = host.trim();
    const p = Number(port);
    if (!h || !Number.isInteger(p) || p < 1 || p > 65535) {
      setError(true);
      return;
    }
    onConnect(h, p);
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-label={t("manual.title")}
      onClick={onClose}
    >
      <div className="card w-full max-w-sm p-6 shadow-pop animate-scale-in" onClick={(e) => e.stopPropagation()}>
        <div className="mb-4 flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-line-strong bg-gradient-to-b from-white/[0.1] to-transparent text-ink">
            <Icon name="link" className="h-4.5 w-4.5" strokeWidth={1.7} />
          </div>
          <div>
            <p className="text-sm font-semibold text-ink">{t("manual.title")}</p>
            <p className="text-xs text-ink-faint">{t("manual.subtitle")}</p>
          </div>
        </div>

        <div className="flex gap-2">
          <label className="flex-1">
            <span className="eyebrow">{t("manual.addressLabel")}</span>
            <input
              className="field mt-1 nums"
              value={host}
              autoFocus
              inputMode="decimal"
              placeholder={t("manual.addressPlaceholder")}
              onChange={(e) => {
                setHost(e.target.value);
                setError(false);
              }}
              onKeyDown={(e) => e.key === "Enter" && submit()}
            />
          </label>
          <label className="w-24">
            <span className="eyebrow">{t("manual.portLabel")}</span>
            <input
              className="field mt-1 nums"
              value={port}
              inputMode="numeric"
              onChange={(e) => {
                setPort(e.target.value.replace(/\D/g, "").slice(0, 5));
                setError(false);
              }}
              onKeyDown={(e) => e.key === "Enter" && submit()}
            />
          </label>
        </div>

        {error && (
          <p className="mt-2 text-xs text-danger" role="alert">
            {t("manual.invalid")}
          </p>
        )}

        <button
          type="button"
          className="mt-4 flex w-full items-center gap-3 rounded-xl border border-line px-3 py-2.5 text-left transition-colors hover:border-line-strong disabled:cursor-default disabled:hover:border-line"
          onClick={copyOwn}
          disabled={!ownAddress}
          aria-label={ownAddress ? `${t("manual.yourAddress")}: ${ownAddress}` : undefined}
        >
          <div className="min-w-0 flex-1">
            <p className="eyebrow">{t("manual.yourAddress")}</p>
            <p className={`nums mt-0.5 truncate text-sm ${ownAddress ? "text-ink" : "text-ink-faint"}`}>
              {ownAddress ?? t("manual.yourAddressUnknown")}
            </p>
          </div>
          {ownAddress && (
            <Icon
              name={copied ? "check" : "copy"}
              className={`h-4 w-4 shrink-0 ${copied ? "text-ink" : "text-ink-faint"}`}
            />
          )}
        </button>

        <div className="mt-5 flex justify-end gap-2">
          <button type="button" className="btn-ghost" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button type="button" className="btn-primary" onClick={submit}>
            <Icon name="link" className="h-4 w-4" />
            {t("manual.connect")}
          </button>
        </div>
      </div>
    </div>
  );
}

// ===== Device Info Dialog =====

function DeviceInfoDialog({
  target,
  onClose,
  onDisconnect,
  onForget,
  forgetting,
  t,
}: {
  target: InfoTarget;
  onClose: () => void;
  onDisconnect?: () => void;
  onForget?: () => void;
  forgetting?: boolean;
  t: Translate;
}) {
  const rows: Array<{ label: string; value: string }> = [];

  if (target.kind === "paired") {
    const d = target.device;
    rows.push({ label: t("home.infoName"), value: d.deviceName });
    rows.push({ label: t("home.infoStatus"), value: d.online ? t("common.online") : t("common.offline") });
    if (d.platform) rows.push({ label: t("home.infoPlatform"), value: platformLabel(d.platform, t) });
    rows.push({ label: t("home.infoDeviceId"), value: d.deviceId });
  } else {
    const d = target.device;
    rows.push({ label: t("home.infoName"), value: d.deviceName });
    rows.push({ label: t("home.infoPlatform"), value: platformLabel(d.platform, t) });
    rows.push({ label: t("home.infoAddress"), value: `${d.addr}:${d.port}` });
    rows.push({ label: t("home.infoDeviceId"), value: d.deviceId });
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-label={t("home.infoTitle")}
      onClick={onClose}
    >
      <div className="card w-full max-w-sm p-6 shadow-pop animate-scale-in" onClick={(e) => e.stopPropagation()}>
        <p className="mb-4 text-sm font-semibold text-ink">{t("home.infoTitle")}</p>
        <dl className="flex flex-col gap-3">
          {rows.map((row) => (
            <div key={row.label}>
              <dt className="eyebrow">{row.label}</dt>
              <dd className="mt-0.5 break-all text-sm text-ink">{row.value}</dd>
            </div>
          ))}
        </dl>
        {target.kind === "paired" ? (
          <p className="mt-4 text-xs text-ink-faint">{t("home.infoPairedHint")}</p>
        ) : (
          <p className="mt-4 text-xs text-ink-faint">{t("home.tapToPair")}</p>
        )}
        <div className="mt-5 flex justify-end gap-2">
          {onDisconnect && target.kind === "paired" && target.device.online && (
            <button type="button" className="btn-ghost text-danger hover:bg-danger/10" onClick={onDisconnect}>
              <Icon name="unlink" className="h-4 w-4" />
              {t("menu.disconnect")}
            </button>
          )}
          {onForget && (
            <button type="button" className="btn-ghost text-danger hover:bg-danger/10" disabled={forgetting} onClick={onForget}>
              <Icon name="close" className="h-4 w-4" />
              {t("menu.forget")}
            </button>
          )}
          <button type="button" className="btn-ghost" onClick={onClose}>
            {t("common.close")}
          </button>
        </div>
      </div>
    </div>
  );
}
