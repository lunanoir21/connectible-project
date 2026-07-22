// Design-review harness. NOT part of the shipped Tauri app (which uses
// index.html -> main.tsx). Renders the real, production components with
// representative sample props so the monochrome UI can be seen and
// screenshotted without a running daemon. Sample data lives ONLY here.

import React, { useState } from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";

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
import { I18nProvider, useT, type TranslationKey } from "./i18n";
import { applyTheme, getInitialTheme, useTheme } from "./theme";
import type {
  Battery,
  ClipboardEntry,
  Device,
  NearbyDevice,
  Notification,
  TransferProgress,
} from "./lib/types";

const now = Date.now();

const devices: Device[] = [
  { deviceId: "d2", deviceName: "Anil's Pixel", platform: "PLATFORM_ANDROID", online: true, pairedAtMs: now, lastSeenMs: now - 8000 },
  { deviceId: "d4", deviceName: "Living Room TV", platform: "PLATFORM_ANDROID", online: true, pairedAtMs: now, lastSeenMs: now - 2000 },
  { deviceId: "d3", deviceName: "Work Laptop", platform: "PLATFORM_MACOS", online: false, pairedAtMs: now, lastSeenMs: now - 3_600_000 },
];

const nearby: NearbyDevice[] = [
  { deviceId: "d2", deviceName: "Anil's Pixel", platform: "PLATFORM_ANDROID", addr: "192.168.1.24", port: 58231 },
  { deviceId: "d9", deviceName: "Kitchen Tablet", platform: "PLATFORM_ANDROID", addr: "192.168.1.31", port: 58231 },
  { deviceId: "d7", deviceName: "MacBook Air", platform: "PLATFORM_MACOS", addr: "192.168.1.42", port: 58231 },
];

const clipboard: ClipboardEntry[] = [
  { content: "https://connectible.io/docs/pairing#tls-1.3", mimeType: "text/plain", capturedAtMs: now - 4000, source: "Anil's Pixel" },
  { content: "cargo build --release -p connectibled", mimeType: "text/plain", capturedAtMs: now - 60_000, source: "local" },
  { content: "The quick brown fox jumps over the lazy dog and keeps on running past the margin", mimeType: "text/plain", capturedAtMs: now - 5 * 60_000, source: "Living Room TV" },
];

const battery: Battery = { percentage: 82, isCharging: true, minutesRemaining: -1, reportedAtMs: now };

const notifications: Notification[] = [
  { notificationId: "n1", appName: "Signal", title: "Deniz", body: "Are we still on for tonight?", postedAtMs: now - 30_000, isDismissal: false },
  { notificationId: "n2", appName: "Calendar", title: "Standup in 10 min", body: "Daily sync - Meet link", postedAtMs: now - 9 * 60_000, isDismissal: false },
];

const transfers: Record<string, TransferProgress> = {
  t1: { transferId: "t1", fileName: "render-final.mp4", bytesTransferred: 61_000_000, totalBytes: 128_000_000, completed: false, failed: false, canceled: false, direction: "outgoing" },
  t0: { transferId: "t0", fileName: "contract.pdf", bytesTransferred: 2_400_000, totalBytes: 2_400_000, completed: true, failed: false, canceled: false, direction: "incoming" },
};

const samplePrompt = {
  requesterDeviceId: "d9",
  requesterDeviceName: "Kitchen Tablet",
  pinCode: "428170",
  pinExpiresAtMs: now + 24_000,
};

const TITLE_KEYS: Record<PanelId, TranslationKey> = {
  home: "nav.home",
  devices: "nav.devices",
  clipboard: "nav.clipboard",
  transfers: "nav.transfers",
  input: "nav.input",
  notifications: "nav.notifications",
  doctor: "doctor.title",
  settings: "nav.settings",
};

function Preview() {
  const t = useT();
  const { theme, setTheme } = useTheme();
  const [panel, setPanel] = useState<PanelId>("home");
  const [showDialog, setShowDialog] = useState(false);

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar
        active={panel}
        onSelect={setPanel}
        counts={{ home: 2, devices: 2, transfers: 1, notifications: 2 }}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <StatusBar connected deviceName="Studio Desktop" battery={battery} title={t(TITLE_KEYS[panel])} />
        <main className="min-h-0 flex-1 overflow-hidden px-6 py-5">
          {panel === "home" && (
            <HomePanel
              deviceName="Studio Desktop"
              devices={devices}
              nearby={nearby}
              onPairStarted={() => setShowDialog(true)}
              onNavigate={setPanel}
              onRefresh={() => {}}
            />
          )}
          {panel === "devices" && (
            <DeviceListPanel
              devices={devices}
              nearby={nearby}
              loading={false}
              onPairStarted={() => setShowDialog(true)}
              onRefresh={() => {}}
            />
          )}
          {panel === "clipboard" && <ClipboardPanel entries={clipboard} />}
          {panel === "transfers" && <TransferPanel transfers={transfers} devices={devices} nearby={nearby} />}
          {panel === "input" && (
            <RemoteInputPanel capabilities={["file_transfer", "clipboard"]} enabled onRefresh={() => {}} />
          )}
          {panel === "notifications" && <NotificationsPanel notifications={notifications} />}
          {panel === "doctor" && <ConnectionDoctorPanel />}
          {panel === "settings" && (
            <SettingsPanel theme={theme} onThemeChange={setTheme} deviceName="Studio Desktop" appVersion="0.1.0" />
          )}
        </main>
      </div>

      {showDialog && (
        <PairingDialog
          mode={{ role: "responder", prompt: samplePrompt }}
          onClose={() => setShowDialog(false)}
          onPaired={() => setShowDialog(false)}
        />
      )}

      <button
        type="button"
        onClick={() => setShowDialog((v) => !v)}
        className="btn-outline fixed bottom-4 right-4 z-[60]"
      >
        Toggle pairing dialog
      </button>
    </div>
  );
}

applyTheme(getInitialTheme());

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <I18nProvider>
      <Preview />
    </I18nProvider>
  </React.StrictMode>,
);
