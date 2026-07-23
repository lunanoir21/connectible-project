import { useMemo, useState, useEffect } from "react";
import { Sidebar, type PanelId } from "./components/Sidebar";
import { StatusBar } from "./components/StatusBar";
import { HomePanel } from "./components/HomePanel";
import { DeviceListPanel } from "./components/DeviceListPanel";
import { ClipboardPanel } from "./components/ClipboardPanel";
import { TransferPanel } from "./components/TransferPanel";
import { RemoteInputPanel } from "./components/RemoteInputPanel";
import { NotificationsPanel } from "./components/NotificationsPanel";
import { SettingsPanel } from "./components/SettingsPanel";
import { ConnectionDoctorPanel } from "./components/ConnectionDoctorPanel";
import { PairingDialog } from "./components/PairingDialog";
import { PairingQrDialog } from "./components/PairingQrDialog";
import { useDaemon } from "./hooks/useDaemon";
import { useT, useI18n, type TranslationKey } from "./i18n";
import { useTheme } from "./theme";
import { ipc } from "./lib/ipc";
import type { NearbyDevice, DaemonStatusDto } from "./lib/types";
import packageJson from "../package.json";

type RequesterPairing = { device: NearbyDevice; pinExpiresAtMs: number };

// T-X30: sourced from package.json (the release process's single source
// of truth for the version) instead of a hand-written duplicate that
// silently drifts on every bump.
const APP_VERSION = packageJson.version;

// rttMs is deliberately excluded: it's a live measurement that changes
// almost every poll, and StatusBar's daemon chip hides itself entirely
// once running && reachable (its one consumer) -- so a changed rttMs
// alone never actually changes what's on screen, but comparing it here
// would defeat the whole point of bailing out on a healthy connection,
// the case this matters most for.
function sameDaemonStatus(a: DaemonStatusDto | null, b: DaemonStatusDto): boolean {
  return (
    a !== null &&
    a.running === b.running &&
    a.reachable === b.reachable &&
    a.errorCode === b.errorCode
  );
}

const TITLE_KEYS: Record<PanelId, TranslationKey> = {
  home: "nav.home",
  devices: "nav.devices",
  clipboard: "nav.clipboard",
  transfers: "nav.transfers",
  input: "nav.input",
  notifications: "nav.notifications",
  doctor: "nav.doctor",
  settings: "nav.settings",
};

export function App() {
  const t = useT();
  const { locale } = useI18n();
  const daemon = useDaemon();
  const { theme, setTheme } = useTheme();
  const [panel, setPanel] = useState<PanelId>("home");
  const [requesterPairing, setRequesterPairing] = useState<RequesterPairing | null>(null);
  const [showPairingQr, setShowPairingQr] = useState(false);
  const [daemonStatus, setDaemonStatus] = useState<DaemonStatusDto | null>(null);

  // Fetch daemon status periodically. Most polls report the exact same
  // status, so bail out (return the previous state reference unchanged)
  // instead of forcing a full app re-render every 10s for no visible
  // change -- the same class of jank as HomePanel's device-list polling.
  useEffect(() => {
    let mounted = true;
    const fetchStatus = async () => {
      const result = await ipc.daemonStatus();
      if (!mounted || !result.ok) return;
      setDaemonStatus((prev) => (sameDaemonStatus(prev, result.value) ? prev : result.value));
    };
    fetchStatus();
    const interval = setInterval(fetchStatus, 10000);
    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, []);

  // T-X14: keep the system tray in sync with the UI. The tray is built
  // in Rust with English placeholder labels and no knowledge of the
  // locale or the live clipboard-sync state; push both here whenever the
  // language or that toggle changes (and once on mount). No-op off Tauri
  // / on a tray-less host, so it is harmless in the browser dev shell.
  useEffect(() => {
    void ipc.updateTray(
      {
        show: t("tray.show"),
        hide: t("tray.hide"),
        syncClipboard: t("tray.syncClipboard"),
        quit: t("tray.quit"),
      },
      daemon.clipboardSyncEnabled,
    );
  }, [locale, daemon.clipboardSyncEnabled, t]);

  const counts = useMemo(
    () => ({
      devices: daemon.devices.filter((d) => d.online).length,
      transfers: Object.values(daemon.transfers).filter((tr) => !tr.completed && !tr.failed).length,
      notifications: daemon.notifications.length,
    }),
    [daemon.devices, daemon.transfers, daemon.notifications],
  );

  return (
    <div className="flex h-full overflow-hidden">
      <Sidebar active={panel} onSelect={setPanel} counts={counts} />

      <div className="flex min-w-0 flex-1 flex-col">
        <StatusBar
          connected={daemon.connected}
          deviceName={daemon.deviceName}
          battery={daemon.battery}
          title={t(TITLE_KEYS[panel])}
          daemonStatus={daemonStatus}
        />

        <main className="relative min-h-0 flex-1 overflow-hidden">
          <div className="h-full overflow-hidden px-6 py-5">
            {panel === "home" && (
              <HomePanel
                deviceName={daemon.deviceName}
                devices={daemon.devices}
                nearby={daemon.nearby}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onPairStarted={(device, pinExpiresAtMs) =>
                  setRequesterPairing({ device, pinExpiresAtMs })
                }
                onNavigate={setPanel}
                onRefresh={() => void daemon.refresh()}
              />
            )}
            {panel === "devices" && (
              <DeviceListPanel
                devices={daemon.devices}
                nearby={daemon.nearby}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onRefresh={() => void daemon.refresh()}
                onPairStarted={(device, pinExpiresAtMs) =>
                  setRequesterPairing({ device, pinExpiresAtMs })
                }
              />
            )}
            {panel === "clipboard" && (
              <ClipboardPanel
                entries={daemon.clipboard}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onRefresh={() => void daemon.refresh()}
              />
            )}
            {panel === "transfers" && (
              <TransferPanel
                transfers={daemon.transfers}
                devices={daemon.devices}
                nearby={daemon.nearby}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onRefresh={() => void daemon.refresh()}
              />
            )}
            {panel === "input" && (
              <RemoteInputPanel
                capabilities={daemon.capabilities}
                enabled={daemon.remoteInputEnabled}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onRefresh={() => void daemon.refresh()}
              />
            )}
            {panel === "notifications" && (
              <NotificationsPanel
                notifications={daemon.notifications}
                loading={daemon.loading}
                loadError={daemon.loadError}
                onRefresh={() => void daemon.refresh()}
              />
            )}
            {panel === "doctor" && <ConnectionDoctorPanel />}
            {panel === "settings" && (
              <SettingsPanel
                theme={theme}
                onThemeChange={setTheme}
                deviceName={daemon.deviceName}
                appVersion={APP_VERSION}
                onOpenPairingQr={() => setShowPairingQr(true)}
                clipboardSyncEnabled={daemon.clipboardSyncEnabled}
                onClipboardSyncRefresh={() => void daemon.refresh()}
              />
            )}
          </div>

          {!daemon.connected && <ConnectingOverlay />}
        </main>
      </div>

      {daemon.pairingPrompt && (
        <PairingDialog
          mode={{ role: "responder", prompt: daemon.pairingPrompt }}
          justCompleted={daemon.pairingJustCompleted}
          onClose={daemon.dismissPairingPrompt}
          onPaired={daemon.dismissPairingPrompt}
        />
      )}

      {requesterPairing && (
        <PairingDialog
          mode={{
            role: "requester",
            device: requesterPairing.device,
            pinExpiresAtMs: requesterPairing.pinExpiresAtMs,
          }}
          onClose={() => setRequesterPairing(null)}
          onPaired={() => {
            setRequesterPairing(null);
            void daemon.refresh();
          }}
        />
      )}

      {showPairingQr && (
        <PairingQrDialog
          deviceId={daemon.deviceId}
          deviceName={daemon.deviceName}
          onClose={() => setShowPairingQr(false)}
          consumed={daemon.pairingPrompt !== null}
        />
      )}
    </div>
  );
}

/// Non-blocking veil shown until the daemon connection is established.
function ConnectingOverlay() {
  const t = useT();
  return (
    <div className="pointer-events-none absolute inset-0 flex items-end justify-center pb-6">
      <div className="pointer-events-auto flex items-center gap-2.5 rounded-full border border-line bg-surface-overlay/90 px-4 py-2 text-xs text-ink-muted shadow-pop backdrop-blur">
        <span className="relative flex h-2 w-2">
          <span className="absolute inline-flex h-full w-full animate-pulse-ring rounded-full" />
          <span className="inline-flex h-2 w-2 rounded-full bg-ink-faint" />
        </span>
        {t("status.connectingToDaemon")}
      </div>
    </div>
  );
}
