import { useCallback, useEffect, useState } from "react";
import { ipc, onDaemonStatus, onLocalEvent, onRequestRefresh, onTransferProgress, type IpcError } from "../lib/ipc";
import type {
  Battery,
  ClipboardEntry,
  Device,
  LocalState,
  NearbyDevice,
  Notification,
  PairingPrompt,
  TransferProgress,
} from "../lib/types";

const MAX_CLIPBOARD_HISTORY = 20;

// T-X9: cadence for the visibility-gated device/nearby poll below.
// Slightly tighter than App.tsx's 10s daemonStatus poll because this
// is what makes a just-appeared LAN device show up "automatically",
// as the Home empty-state copy promises.
const DEVICE_POLL_INTERVAL_MS = 5000;

// Functional-setState guard: keeps the previous reference when the
// freshly fetched value is content-identical, so a no-change poll tick
// (the common case at a 5s cadence) bails out of re-rendering instead
// of forcing a full app re-render -- the same hygiene as App.tsx's
// `sameDaemonStatus` for its daemonStatus interval. JSON comparison is
// stable here because every value comes from the same IPC
// serialization path, so key order never shifts.
function keepIfUnchanged<T>(next: T): (prev: T) => T {
  return (prev) => (JSON.stringify(prev) === JSON.stringify(next) ? prev : next);
}

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
  deviceId: string;
  deviceName: string;
  capabilities: string[];
  devices: Device[];
  nearby: NearbyDevice[];
  clipboard: ClipboardEntry[];
  battery: Battery | null;
  notifications: Notification[];
  transfers: Record<string, TransferProgress>;
  pairingPrompt: PairingPrompt | null;
  // True once the requester confirmed the PIN `pairingPrompt` is
  // showing -- lets the responder dialog show a success beat instead of
  // sitting on the code until the countdown expires. Reset whenever a
  // new prompt arrives or the current one is dismissed.
  pairingJustCompleted: boolean;
  dismissPairingPrompt: () => void;
  refresh: () => Promise<void>;
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
  const [pairingJustCompleted, setPairingJustCompleted] = useState(false);

  const refresh = useCallback(async () => {
    const stateResult = await ipc.getLocalState();
    if (stateResult.ok) {
      setState(keepIfUnchanged<LocalState | null>(stateResult.value));
      setClipboard(keepIfUnchanged(stateResult.value.clipboardHistory));
      setBattery(keepIfUnchanged(stateResult.value.latestBattery));
      setNotifications(keepIfUnchanged(stateResult.value.notifications));
    }
    const devicesResult = await ipc.listDevices();
    if (devicesResult.ok) {
      setDevices(keepIfUnchanged(devicesResult.value));
    }
    // Always flips loading off (T-311/T-601): even a failed fetch must
    // show a distinct error state, not spin the skeleton forever.
    setDevicesLoaded(true);
    // T-X17: `loadError` is one flag shared by both fetches, so it must
    // reflect the pair as a whole -- set it once from whichever failed
    // (state's error wins if both did) and clear it only when BOTH
    // succeeded. The old per-branch `setLoadError(null)` let a
    // succeeding second fetch wipe out a genuine failure from the first,
    // making the clipboard/notification panels look empty instead of
    // failed.
    setLoadError(
      !stateResult.ok ? stateResult.error : !devicesResult.ok ? devicesResult.error : null,
    );
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
          setPairingJustCompleted(false);
          break;
        case "pairingCompleted":
          setPairingJustCompleted(true);
          void refresh(); // pick up the newly paired device
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
          // Incoming transfers only: this rides the daemon's own
          // SubscribeLocalEvents stream (local.rs), which is how *this*
          // daemon reports progress on files it is receiving as the
          // upload target. Not redundant with the listener below.
          setTransfers((prev) => ({
            ...prev,
            [event.progress.transferId]: stampFinished(prev[event.progress.transferId], event.progress),
          }));
          break;
      }
    }).then((un) => unlisteners.push(un));

    // Outgoing transfers only: `send_file` (src-tauri/src/commands.rs)
    // drives the upload itself from this process, calling
    // `RemoteDeviceClient::upload_file` directly against the *remote*
    // peer's daemon -- it never goes through this machine's own daemon,
    // so the local daemon has no way to know about it and can't report
    // it on the LocalEvent stream above. The Tauri "transfer-progress"
    // event is the only source of progress for a send this app itself
    // initiated; deliberately a separate pipeline, not a duplicate.
    onTransferProgress((progress) => {
      setTransfers((prev) => ({
        ...prev,
        [progress.transferId]: stampFinished(prev[progress.transferId], progress),
      }));
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

  // T-X9: there is no push channel for device/nearby-list changes (the
  // daemon has no DeviceListChanged LocalEvent, deliberately -- proto
  // changes are out of scope), yet the Home empty-state copy promises
  // that a discovered device "will show up automatically". So poll
  // refresh() while the bridge is connected AND the document is
  // visible, mirroring App.tsx's daemonStatus interval convention.
  // Polling pauses while hidden -- this window spends long stretches
  // hidden in the tray (see tray.rs) and hammering the daemon from an
  // invisible webview would be pure waste; the tray's own show/refresh
  // event plus the immediate catch-up refresh below cover staleness on
  // re-show. Not gated on `connected` alone failing: when the bridge
  // drops, onDaemonStatus flips `connected` false and this effect
  // tears the interval down until it reconnects.
  useEffect(() => {
    if (!connected) return;
    let interval: ReturnType<typeof setInterval> | null = null;
    const start = () => {
      if (interval === null) {
        interval = setInterval(() => void refresh(), DEVICE_POLL_INTERVAL_MS);
      }
    };
    const stop = () => {
      if (interval !== null) {
        clearInterval(interval);
        interval = null;
      }
    };
    const onVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        stop();
      } else {
        // Catch up immediately: a device may have appeared while the
        // window was hidden; don't sit stale for another full interval.
        void refresh();
        start();
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    if (document.visibilityState !== "hidden") start();
    return () => {
      document.removeEventListener("visibilitychange", onVisibilityChange);
      stop();
    };
  }, [connected, refresh]);

  const dismissPairingPrompt = useCallback(() => {
    setPairingPrompt(null);
    setPairingJustCompleted(false);
  }, []);

  return {
    connected,
    loading: !devicesLoaded,
    loadError,
    deviceId: state?.deviceId ?? "",
    deviceName: state?.deviceName ?? "",
    capabilities: state?.capabilities ?? [],
    devices,
    nearby: state?.nearbyDevices ?? [],
    clipboard,
    battery,
    notifications,
    transfers,
    pairingPrompt,
    pairingJustCompleted,
    dismissPairingPrompt,
    refresh,
    remoteInputEnabled: state?.remoteInputEnabled ?? false,
    clipboardSyncEnabled: state?.clipboardSyncEnabled ?? false,
  };
}

// T-X16: stamp a client-side finish time the first time a transfer
// reaches a terminal state, so the history list can sort chronologically
// (the daemon's TransferProgress carries no finish timestamp, and an
// outgoing send never touches the daemon at all). Non-terminal updates
// pass through untouched; an already-stamped row keeps its first stamp.
function stampFinished(
  prev: TransferProgress | undefined,
  next: TransferProgress,
): TransferProgress {
  if (!next.completed && !next.failed) return next;
  return { ...next, finishedAtMs: prev?.finishedAtMs ?? Date.now() };
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
