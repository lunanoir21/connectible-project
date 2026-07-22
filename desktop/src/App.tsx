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
import { useDaemon } from "./hooks/useDaemon";
import { useT, type TranslationKey } from "./i18n";
import { useTheme } from "./theme";
import { ipc } from "./lib/ipc";
import type { NearbyDevice, DaemonStatusDto } from "./lib/types";

type RequesterPairing = { device: NearbyDevice; pinExpiresAtMs: number };

const APP_VERSION = "0.1.0";

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
  const daemon = useDaemon();
  const { theme, setTheme } = useTheme();
  const [panel, setPanel] = useState<PanelId>("home");
  const [requesterPairing, setRequesterPairing] = useState<RequesterPairing | null>(null);
  const [daemonStatus, setDaemonStatus] = useState<DaemonStatusDto | null>(null);

  // Fetch daemon status periodically
  useEffect(() => {
    let mounted = true;
    const fetchStatus = async () => {
      const result = await ipc.daemonStatus();
      if (mounted && result.ok) setDaemonStatus(result.value);
    };
    fetchStatus();
    const interval = setInterval(fetchStatus, 10000);
    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, []);

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
              />
            )}
          </div>

          {!daemon.connected && <ConnectingOverlay />}
        </main>
      </div>

      {daemon.pairingPrompt && (
        <PairingDialog
          mode={{ role: "responder", prompt: daemon.pairingPrompt }}
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
