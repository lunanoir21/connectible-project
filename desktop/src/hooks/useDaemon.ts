import { useCallback, useEffect, useRef, useState } from "react";
import { ipc, onDaemonStatus, onLocalEvent, onRequestRefresh, onTransferProgress, type IpcError } from "../lib/ipc";
import type {
  Battery,
  ClipboardEntry,
  DaemonStatusDto,
  Device,
  LocalState,
  NearbyDevice,
  Notification,
  PairingPrompt,
  TransferProgress,
} from "../lib/types";

const MAX_CLIPBOARD_HISTORY = 20;

export interface DaemonView {
  connected: boolean;
  // True until the first ListDevices response completes (T-311),
  // regardless of whether that response turns out to be empty. Lets
  // DeviceListPanel show a loading skeleton distinct from a genuinely
  // empty paired-devices list.
  loading: boolean;
  // Set when the initial GetLocalState/ListDevices round trip (the one
  // `loading` tracks) fails outright, cleared on the next successful
  // refresh (T-601). Devices/clipboard/notifications/transfers all
  // share this one refresh, so a single flag distinguishes "failed to
  // load" from "loaded and genuinely empty" for all of them.
  loadError: IpcError | null;
  deviceName: string;
  capabilities: string[];
  devices: Device[];
  nearby: NearbyDevice[];
  clipboard: ClipboardEntry[];
  battery: Battery | null;
  notifications: Notification[];
  transfers: Record<string, TransferProgress>;
  pairingPrompt: PairingPrompt | null;
  dismissPairingPrompt: () => void;
  refresh: () => Promise<void>;
  // Daemon management
  daemonStatus: DaemonStatusDto | null;
  checkDaemonStatus: () => Promise<void>;
  // T-309/T-310 toggles, read from the daemon's GetLocalState snapshot.
  remoteInputEnabled: boolean;
  clipboardSyncEnabled: boolean;
}

/// Central store hook (T-033/T-035): owns all live daemon-derived
/// state, wiring the Tauri event stream into React state and exposing a
/// refresh() for imperative reloads (e.g. after a successful pairing).
/// Kept as a single hook rather than Zustand because every consumer is
/// within one screen tree; per RULES.md, Zustand is only introduced
/// when prop/context drilling actually becomes unwieldy.
export function useDaemon(): DaemonView {
  const [connected, setConnected] = useState(false);
  const [devicesLoaded, setDevicesLoaded] = useState(false);
  const [loadError, setLoadError] = useState<IpcError | null>(null);
  const [state, setState] = useState<LocalState | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [clipboard, setClipboard] = useState<ClipboardEntry[]>([]);
  const [battery, setBattery] = useState<Battery | null>(null);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [transfers, setTransfers] = useState<Record<string, TransferProgress>>({});
  const [pairingPrompt, setPairingPrompt] = useState<PairingPrompt | null>(null);
  const [daemonStatus, setDaemonStatus] = useState<DaemonStatusDto | null>(null);

  // Ref mirror so event handlers registered once can read latest state
  // without re-subscribing on every render.
  const connectedRef = useRef(connected);
  connectedRef.current = connected;

  const refresh = useCallback(async () => {
    const stateResult = await ipc.getLocalState();
    if (stateResult.ok) {
      setState(stateResult.value);
      setClipboard(stateResult.value.clipboardHistory);
      setBattery(stateResult.value.latestBattery);
      setNotifications(stateResult.value.notifications);
      setLoadError(null);
    } else {
      setLoadError(stateResult.error);
    }
    const devicesResult = await ipc.listDevices();
    if (devicesResult.ok) {
      setDevices(devicesResult.value);
      setDevicesLoaded(true);
      setLoadError(null);
    } else {
      // Still flips loading off (T-311/T-601): a failed fetch must show
      // a distinct error state, not spin the loading skeleton forever.
      setDevicesLoaded(true);
      setLoadError(devicesResult.error);
    }
  }, []);

  const checkDaemonStatus = useCallback(async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const status = await invoke<DaemonStatusDto>("daemon_status");
      setDaemonStatus(status);
    } catch {
      setDaemonStatus({
        running: false,
        reachable: false,
        rttMs: null,
        errorCode: "UNSPECIFIED",
      });
    }
  }, []);

  useEffect(() => {
    let disposed = false;
    const unlisteners: Array<() => void> = [];

    ipc.daemonConnected().then((result) => {
      if (disposed || !result.ok) return;
      if (result.value) {
        setConnected(true);
        void refresh();
      } else {
        // Not connected on launch: best-effort start the local daemon so
        // a standalone app run doesn't require the user to start the
        // background service by hand. No-ops (returns the running status)
        // if a daemon is already up, so this never spawns a duplicate;
        // the bridge's own retry loop takes it from there once it binds.
        void ipc.startDaemon();
      }
    });

    onDaemonStatus((status) => {
      setConnected(status.connected);
      if (status.connected) void refresh();
    }).then((un) => unlisteners.push(un));

    onLocalEvent((event) => {
      switch (event.kind) {
        case "pairingRequested":
          setPairingPrompt(event.prompt);
          break;
        case "battery":
          setBattery(event.battery);
          break;
        case "notification":
          applyNotification(setNotifications, event.notification);
          break;
        case "clipboard":
          setClipboard((prev) => [event.entry, ...prev].slice(0, MAX_CLIPBOARD_HISTORY));
          break;
        case "transferProgress":
          setTransfers((prev) => ({ ...prev, [event.progress.transferId]: event.progress }));
          break;
      }
    }).then((un) => unlisteners.push(un));

    onTransferProgress((progress) => {
      setTransfers((prev) => ({ ...prev, [progress.transferId]: progress }));
    }).then((un) => unlisteners.push(un));

    // T-310: the tray's clipboard-sync toggle (and the "show" tray
    // action generally) can change daemon-side state while this
    // webview is hidden; since hide/show does not remount React, this
    // is the signal that nudges a re-fetch instead of showing stale
    // state indefinitely.
    onRequestRefresh(() => {
      void refresh();
    }).then((un) => unlisteners.push(un));

    return () => {
      disposed = true;
      unlisteners.forEach((un) => un());
    };
  }, [refresh]);

  const dismissPairingPrompt = useCallback(() => setPairingPrompt(null), []);

  return {
    connected,
    loading: !devicesLoaded,
    loadError,
    deviceName: state?.deviceName ?? "",
    capabilities: state?.capabilities ?? [],
    devices,
    nearby: state?.nearbyDevices ?? [],
    clipboard,
    battery,
    notifications,
    transfers,
    pairingPrompt,
    dismissPairingPrompt,
    refresh,
    daemonStatus,
    checkDaemonStatus,
    remoteInputEnabled: state?.remoteInputEnabled ?? false,
    clipboardSyncEnabled: state?.clipboardSyncEnabled ?? false,
  };
}

function applyNotification(
  setNotifications: React.Dispatch<React.SetStateAction<Notification[]>>,
  incoming: Notification,
) {
  setNotifications((prev) => {
    const withoutMatch = prev.filter((n) => n.notificationId !== incoming.notificationId);
    // A dismissal removes the matching notification; a normal one is
    // prepended (matching the daemon's StatusHub semantics).
    return incoming.isDismissal ? withoutMatch : [incoming, ...withoutMatch];
  });
}
