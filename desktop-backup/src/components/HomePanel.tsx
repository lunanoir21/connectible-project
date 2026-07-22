import { useState, useCallback, useMemo, useEffect } from "react";
import { ipc, type IpcError } from "../lib/ipc";
import type { Device, LocalAddresses, NearbyDevice } from "../lib/types";
import { formatRelativeTime } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { ErrorState } from "./ErrorState";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { Icon, type IconName } from "./Icon";
import { useT, type Translate } from "../i18n";
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
            <Constellation
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
              <p className="mt-1 text-center text-xs text-ink-faint" data-testid="home-nearby-more">
                {t("home.nearbyMore", { count: hiddenNearby })}
              </p>
            )}

            <StatusStrip
              devices={devices}
              onlineCount={onlineDevices.length}
              nearbyCount={pairable.length}
              t={t}
            />

            <div className="mx-auto mt-7 w-full max-w-[560px]">
              <QuickActions actions={quickActions} />
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

// ===== Constellation =====
// The home's signature. This device sits at the center; every peer is a
// star held on an orbit by a tie back to you. State is legible in the
// structure itself: paired peers ride the inner orbit, nearby-but-not-
// paired ones the looser outer orbit. The tie carries the live/dead
// reading -- a solid welded line and a lit star for an online peer, a
// thin line and a hollow star when it's offline, a dashed detached tie
// for a device merely in range. Nothing here is a flat list; the roster
// *is* the picture of what you're connected to.

const VB_W = 760;
const VB_H = 480;
const CX = 380;
const CY = 232;
const RING_INNER = 140; // paired orbit
const RING_OUTER = 196; // nearby orbit
const NODE_R = 9;
const CENTER_R = 30;

// Stable per-device angular/radial jitter so a given peer always lands
// in the same spot instead of jumping between renders -- the layout must
// read as a fixed sky, not a reshuffle on every poll. FNV-1a hash.
function hashSeed(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

type StarKind = "online" | "offline" | "nearby";

interface Star {
  id: string;
  name: string;
  kind: StarKind;
  device: Device | null;
  nearby: NearbyDevice | null;
  x: number;
  y: number;
  len: number;
  index: number;
}

function placeGroup<T extends { deviceId: string }>(
  items: T[],
  ring: number,
  startDeg: number,
  make: (item: T, x: number, y: number, len: number, index: number) => Star,
  indexOffset: number,
): Star[] {
  const n = items.length;
  return items.map((item, i) => {
    const step = n > 0 ? 360 / n : 0;
    // A lone peer hangs straight up from center -- a clean vertical tie
    // reads better than an off-axis one.
    const base = n === 1 ? -90 : startDeg + i * step;
    const seed = hashSeed(item.deviceId);
    const spread = n > 4 ? 8 : 15;
    const jitterA = ((seed % 1000) / 1000 - 0.5) * spread;
    const jitterR = (((seed >> 10) % 1000) / 1000 - 0.5) * 18;
    const ang = ((base + jitterA) * Math.PI) / 180;
    const rr = ring + jitterR;
    const x = CX + rr * Math.cos(ang);
    const y = CY + rr * Math.sin(ang);
    const len = Math.hypot(x - CX, y - CY);
    return make(item, x, y, len, indexOffset + i);
  });
}

// A fixed, deterministic scatter of faint background stars, generated
// once at module load (seeded) so it's stable and adds depth without
// competing with the live nodes. Kept off the center so the monogram
// stays clean.
function makeField(): { x: number; y: number; r: number; dur: number; delay: number }[] {
  let s = 0x9e3779b9;
  const rnd = () => {
    s = (Math.imul(s ^ (s >>> 15), s | 1) >>> 0) + 0x6d2b79f5;
    s >>>= 0;
    return ((s ^ (s >>> 14)) >>> 0) / 4294967296;
  };
  const out: { x: number; y: number; r: number; dur: number; delay: number }[] = [];
  let tries = 0;
  while (out.length < 26 && tries < 400) {
    tries++;
    const x = rnd() * VB_W;
    const y = rnd() * VB_H;
    if (Math.hypot(x - CX, y - CY) < RING_OUTER + 26) continue; // keep clear of the orbits
    out.push({ x, y, r: 0.7 + rnd() * 1.2, dur: 3 + rnd() * 3.5, delay: rnd() * 3 });
  }
  return out;
}
const STAR_FIELD = makeField();

interface ConstellationProps {
  deviceName: string;
  devices: Device[];
  pairable: NearbyDevice[];
  pairingId: string | null;
  loading?: boolean;
  onPair: (device: NearbyDevice) => void;
  onShowInfo: (target: InfoTarget) => void;
  t: Translate;
}

function Constellation({ deviceName, devices, pairable, pairingId, loading, onPair, onShowInfo, t }: ConstellationProps) {
  const [activeId, setActiveId] = useState<string | null>(null);

  const stars = useMemo<Star[]>(() => {
    const hasPaired = devices.length > 0;
    const paired = placeGroup(
      devices,
      RING_INNER,
      -90,
      (d, x, y, len, index) => ({
        id: d.deviceId,
        name: d.deviceName,
        kind: d.online ? "online" : "offline",
        device: d,
        nearby: null,
        x,
        y,
        len,
        index,
      }),
      0,
    );
    const near = placeGroup(
      pairable,
      hasPaired ? RING_OUTER : RING_INNER,
      -70,
      (d, x, y, len, index) => ({
        id: d.deviceId,
        name: d.deviceName,
        kind: "nearby",
        device: null,
        nearby: d,
        x,
        y,
        len,
        index,
      }),
      devices.length,
    );
    return [...paired, ...near];
  }, [devices, pairable]);

  const anyOnline = devices.some((d) => d.online);
  const empty = !loading && stars.length === 0;

  const onStarActivate = useCallback(
    (star: Star) => {
      if (star.kind === "nearby" && star.nearby) {
        if (pairingId === star.id) return;
        onPair(star.nearby);
      } else if (star.device) {
        onShowInfo({ kind: "paired", device: star.device });
      }
    },
    [onPair, onShowInfo, pairingId],
  );

  return (
    <div
      className="relative mx-auto w-full max-w-[560px]"
      data-testid={loading ? "home-devices-skeleton" : undefined}
      aria-busy={loading || undefined}
    >
      <svg viewBox={`0 0 ${VB_W} ${VB_H}`} className="h-auto w-full select-none" role="group" aria-label={t("nav.devices")}>
        <defs>
          <radialGradient id="cnstCenterFill" cx="50%" cy="32%" r="72%">
            <stop offset="0%" stopColor="rgba(255,255,255,0.18)" />
            <stop offset="100%" stopColor="rgba(255,255,255,0)" />
          </radialGradient>
        </defs>

        {/* Ambient starfield */}
        <g aria-hidden="true">
          {STAR_FIELD.map((f, i) => (
            <circle
              key={i}
              className="cnst-twinkle"
              cx={f.x}
              cy={f.y}
              r={f.r}
              fill="rgb(var(--ink-ghost))"
              style={{ ["--tw" as string]: `${f.dur}s`, animationDelay: `${f.delay}s` }}
            />
          ))}
        </g>

        {/* Orbit guides -- faint rings the stars ride on. The outer ring
            only shows once there's an outer orbit to hint at. */}
        <g aria-hidden="true" fill="none">
          <circle cx={CX} cy={CY} r={RING_INNER} stroke="rgba(255,255,255,0.05)" strokeWidth={1} />
          {devices.length > 0 && pairable.length > 0 && (
            <circle cx={CX} cy={CY} r={RING_OUTER} stroke="rgba(255,255,255,0.04)" strokeWidth={1} strokeDasharray="2 6" />
          )}
        </g>

        {/* Ties: drawn center -> star. */}
        <g aria-hidden="true" fill="none" strokeLinecap="round">
          {stars.map((star) => {
            const delay = `${120 + star.index * 70}ms`;
            if (star.kind === "nearby") {
              return (
                <line
                  key={star.id}
                  className="cnst-label"
                  x1={CX}
                  y1={CY}
                  x2={star.x}
                  y2={star.y}
                  stroke="rgba(255,255,255,0.12)"
                  strokeWidth={1}
                  strokeDasharray="4 5"
                  style={{ animationDelay: delay }}
                />
              );
            }
            const live = star.kind === "online";
            return (
              <g key={star.id}>
                <line
                  className="cnst-tie"
                  x1={CX}
                  y1={CY}
                  x2={star.x}
                  y2={star.y}
                  stroke={live ? "rgba(255,255,255,0.28)" : "rgba(255,255,255,0.08)"}
                  strokeWidth={live ? 1.75 : 1}
                  style={{ ["--len" as string]: star.len, animationDelay: delay }}
                />
                {live && (
                  // The heartbeat: a lit dash traveling out to a live peer.
                  <line
                    className="cnst-pulse"
                    x1={CX}
                    y1={CY}
                    x2={star.x}
                    y2={star.y}
                    stroke="rgb(var(--paper))"
                    strokeWidth={3}
                    strokeLinecap="round"
                    pathLength={100}
                    strokeDasharray="8 92"
                    style={{ animationDelay: `${900 + star.index * 140}ms`, filter: "drop-shadow(0 0 3px rgba(255,255,255,0.7))" }}
                  />
                )}
              </g>
            );
          })}
        </g>

        {/* Stars (peers) */}
        {stars.map((star) => {
          const active = activeId === star.id;
          const pairing = pairingId === star.id;
          const live = star.kind === "online";
          const delay = `${420 + star.index * 70}ms`;
          const labelY = NODE_R + 17;

          let sub: string | null = null;
          if (active) {
            if (pairing) sub = t("common.pairing");
            else if (star.kind === "online") sub = t("devices.onlineNow");
            else if (star.kind === "offline" && star.device)
              sub = t("devices.lastSeen", { time: formatRelativeTime(star.device.lastSeenMs) });
            else sub = t("home.tapToPair");
          }

          const aria =
            star.kind === "nearby"
              ? `${star.name} - ${t("devices.nearby")}`
              : `${star.name} - ${live ? t("common.online") : t("common.offline")}`;

          return (
            <g
              key={star.id}
              className="cnst-node"
              role="button"
              tabIndex={0}
              aria-label={aria}
              transform={`translate(${star.x},${star.y})`}
              onClick={() => onStarActivate(star)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  onStarActivate(star);
                }
              }}
              onMouseEnter={() => setActiveId(star.id)}
              onMouseLeave={() => setActiveId((cur) => (cur === star.id ? null : cur))}
              onFocus={() => setActiveId(star.id)}
              onBlur={() => setActiveId((cur) => (cur === star.id ? null : cur))}
            >
              {/* generous invisible hit target */}
              <circle r={22} fill="transparent" />
              <circle className="cnst-focus" r={17} fill="none" stroke="rgb(var(--paper))" strokeWidth={1.5} strokeOpacity={0.7} />
              <g className="cnst-star-in" style={{ animationDelay: delay }}>
                {(live || pairing) && (
                  <circle
                    className="cnst-halo"
                    r={NODE_R}
                    fill="none"
                    stroke="rgb(var(--paper))"
                    strokeWidth={1.5}
                    style={pairing ? { animationDuration: "1.4s" } : undefined}
                  />
                )}
                {star.kind === "online" ? (
                  <circle
                    r={NODE_R}
                    fill="rgb(var(--paper))"
                    style={{ filter: "drop-shadow(0 0 7px rgba(255,255,255,0.55))" }}
                  />
                ) : star.kind === "offline" ? (
                  <circle r={NODE_R} fill="rgb(var(--canvas))" stroke="rgba(255,255,255,0.22)" strokeWidth={1.5} />
                ) : (
                  <circle
                    r={NODE_R}
                    fill="rgb(var(--canvas))"
                    stroke="rgba(255,255,255,0.22)"
                    strokeWidth={1.5}
                    strokeDasharray="2.5 2.5"
                  />
                )}
              </g>
              <text
                className="cnst-label"
                x={0}
                y={labelY}
                textAnchor="middle"
                style={{ animationDelay: delay }}
                fontSize={13}
                fontWeight={500}
                fill={active ? "rgb(var(--ink))" : "rgb(var(--ink-muted))"}
              >
                {star.name.length > 16 ? star.name.slice(0, 15) + "…" : star.name}
              </text>
              {sub && (
                <text x={0} y={labelY + 15} textAnchor="middle" fontSize={10.5} fill="rgb(var(--ink-faint))">
                  {sub}
                </text>
              )}
            </g>
          );
        })}

        {/* Center: this device */}
        <g transform={`translate(${CX},${CY})`} aria-label={deviceName}>
          {anyOnline && (
            <circle className="cnst-halo" r={CENTER_R} fill="none" stroke="rgb(var(--paper))" strokeWidth={1.5} style={{ animationDuration: "2.9s" }} />
          )}
          <circle r={CENTER_R} fill="rgb(var(--surface-raised))" stroke="rgba(255,255,255,0.16)" strokeWidth={1.5} />
          <circle r={CENTER_R} fill="url(#cnstCenterFill)" />
          <text textAnchor="middle" dominantBaseline="central" fontSize={16} fontWeight={600} fill="rgb(var(--ink))">
            {monogram(deviceName || "Me")}
          </text>
        </g>
      </svg>

      {empty && (
        <p className="pointer-events-none absolute inset-x-0 bottom-1 text-center text-sm text-ink-faint">
          {t("home.notPairedHint")}
        </p>
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
