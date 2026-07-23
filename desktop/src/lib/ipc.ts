// Typed wrappers over the Tauri command/event bridge. Every call the
// UI makes to the Rust core goes through here, so components never
// touch `invoke`/`listen` directly and the command contract lives in
// one place. Each wrapper returns a typed Result so a failed command
// (e.g. daemon not connected) surfaces as a handled state, not an
// uncaught promise rejection (RULES.md error-handling rule).

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { isErrorCode, type ErrorCode } from "./errors";
import type {
  DaemonStatus,
  DaemonStatusDto,
  Device,
  DiagnosticsReport,
  LocalAddresses,
  LocalEvent,
  LocalState,
  PairOutcome,
  PairingCode,
  TransferHistoryEntry,
  TransferProgress,
} from "./types";

// Structured error a failed IPC call resolves to (T-602): `code` is the
// wire ErrorCode (desktop/core's DesktopError::code_name(), threaded
// through the Tauri command boundary's CmdError), the key
// errorCodeMessage() looks a translated, actionable message up by.
// `message` is the daemon/Rust Display text, kept only for logs/dev
// tooling -- callers must not render it directly (RULES.md).
export interface IpcError {
  code: ErrorCode;
  message: string;
}

export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: IpcError };

// Tauri commands reject with whatever the Err arm serializes to. Every
// command in commands.rs now returns a CmdError ({ code, message }),
// but this stays defensive against any value shape (e.g. a raw string
// from a future command that hasn't been migrated, or a JS-level
// exception) rather than assuming the invariant always holds.
function toIpcError(e: unknown): IpcError {
  if (e && typeof e === "object" && "code" in e) {
    const rawCode = (e as { code: unknown }).code;
    const rawMessage = (e as { message?: unknown }).message;
    if (typeof rawCode === "string" && isErrorCode(rawCode)) {
      return { code: rawCode, message: typeof rawMessage === "string" ? rawMessage : "" };
    }
  }
  return { code: "UNSPECIFIED", message: typeof e === "string" ? e : String(e) };
}

async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<Result<T>> {
  try {
    const value = await invoke<T>(cmd, args);
    return { ok: true, value };
  } catch (e) {
    return { ok: false, error: toIpcError(e) };
  }
}

export const ipc = {
  daemonConnected: () => call<boolean>("daemon_connected"),
  daemonStatus: () => call<DaemonStatusDto>("daemon_status"),
  startDaemon: () => call<DaemonStatusDto>("start_daemon"),
  stopDaemon: () => call<boolean>("stop_daemon"),
  getLocalState: () => call<LocalState>("get_local_state"),
  listDevices: () => call<Device[]>("list_devices"),

  // This machine's LAN IPv4 addresses + daemon port, so Home can show
  // its own "connect by address" endpoint (the reverse of manual
  // connect). `addresses` is empty when no usable LAN address exists.
  localAddresses: () => call<LocalAddresses>("local_addresses"),

  // Where received files are saved (resolved: user override -> OS
  // Downloads -> data dir). Settings displays this and lets the user
  // change it; the daemon writes finalized files there.
  getDownloadDir: () => call<string>("get_download_dir"),
  setDownloadDir: (path: string) => call<string>("set_download_dir", { path }),

  // Opens a file or folder in the OS's native handler (received-files
  // folder in the file manager, a sent file in its default app). Native
  // command, not the opener plugin -- it cascades through xdg-open / gio
  // / known file managers so it actually works across Linux desktops
  // instead of silently no-op'ing where the plugin's single mechanism
  // isn't present.
  openPath: (path: string) => call<null>("open_path", { path }),

  // Drops the local daemon's live-connection attribution for a paired
  // device (T-102's "Disconnect" action). Returns whether a live
  // connection was actually found; false is not an error.
  disconnectDevice: (deviceId: string) =>
    call<boolean>("disconnect_device", { deviceId }),

  // Permanently removes a paired device (T-307's "Forget" action).
  // Returns whether a matching device was actually found and removed;
  // false is not an error (already unpaired). Requires a fresh PIN
  // exchange to re-pair afterward.
  forgetDevice: (deviceId: string) =>
    call<boolean>("forget_device", { deviceId }),

  // Dismisses a mirrored notification (T-K5): removes it from this
  // device's own list and asks the daemon to relay the dismissal to the
  // peer it came from, so the real system notification clears there too.
  dismissNotification: (notificationId: string) =>
    call<null>("dismiss_notification", { notificationId }),

  // Gates whether incoming remote input is applied (T-309). Returns
  // the value now in effect.
  setRemoteInputEnabled: (enabled: boolean) =>
    call<boolean>("set_remote_input_enabled", { enabled }),

  // Gates clipboard sync (T-310), shared with the tray's toggle menu
  // item. Returns the value now in effect.
  setClipboardSyncEnabled: (enabled: boolean) =>
    call<boolean>("set_clipboard_sync_enabled", { enabled }),

  pairWithDevice: (addr: string, port: number) =>
    call<PairOutcome>("pair_with_device", { addr, port }),

  // The PIN is keyed daemon-side by the local requester id; deviceId is the
  // *target* peer's id, used to pin its cert on first pair (TOFU, T-C2).
  confirmPin: (addr: string, port: number, pinCode: string, deviceId: string) =>
    call<boolean>("confirm_pin", { addr, port, pinCode, deviceId }),

  // deviceId lets the daemon enforce the target's pinned cert (TOFU, T-C3).
  sendFile: (addr: string, port: number, filePath: string, deviceId: string) =>
    call<string>("send_file", { addr, port, filePath, deviceId }),

  // System Doctor (T-F8): run the daemon's diagnostics engine (all checks,
  // or one by id) -- the same engine `connectibled doctor` uses.
  runDiagnostics: (checkId?: string) =>
    call<DiagnosticsReport>("run_diagnostics", { checkId: checkId ?? null }),

  cancelTransfer: (transferId: string) =>
    call<null>("cancel_transfer", { transferId }),

  // Pre-generates a PIN with no requester known yet, for a pairing QR
  // code the desktop displays (scan-to-pair). The next Pair call from
  // anywhere consumes it, so ConfirmPin needs no separate wiring here.
  preArmPairingCode: () => call<PairingCode>("pre_arm_pairing_code"),

  // Phase J: persisted transfer history (both directions), most recent
  // first -- survives a daemon restart, unlike the live `transfers` map.
  listTransferHistory: () => call<TransferHistoryEntry[]>("list_transfer_history"),

  // T-X14: relabel the tray menu in the active language and sync the
  // clipboard-sync checkbox. Called on mount, on a language switch, and
  // whenever the clipboard-sync toggle changes. A no-op on a tray-less
  // host.
  updateTray: (
    labels: { show: string; hide: string; syncClipboard: string; quit: string },
    clipboardSyncEnabled: boolean,
  ) =>
    call<null>("update_tray", {
      show: labels.show,
      hide: labels.hide,
      syncClipboard: labels.syncClipboard,
      quit: labels.quit,
      clipboardSyncEnabled,
    }),
};

// Event subscriptions. Returned promise resolves to the unlisten fn so
// callers can clean up in a useEffect teardown.
export function onLocalEvent(handler: (event: LocalEvent) => void): Promise<UnlistenFn> {
  return listen<LocalEvent>("local-event", (e) => handler(e.payload));
}

export function onDaemonStatus(handler: (status: DaemonStatus) => void): Promise<UnlistenFn> {
  return listen<DaemonStatus>("daemon-status", (e) => handler(e.payload));
}

export function onTransferProgress(handler: (progress: TransferProgress) => void): Promise<UnlistenFn> {
  return listen<TransferProgress>("transfer-progress", (e) => handler(e.payload));
}

// Emitted by the Rust shell (tray.rs's "show" action and clipboard-sync
// toggle, T-310) when daemon-side state may have changed while this
// webview was hidden -- hide/show does not remount React, so this is
// the signal that triggers a fresh getLocalState()/listDevices() fetch.
export function onRequestRefresh(handler: () => void): Promise<UnlistenFn> {
  return listen<void>("request-refresh", () => handler());
}
