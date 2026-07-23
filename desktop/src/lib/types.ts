// Frontend mirror of the Rust DTOs in desktop/core/src/dto.rs. Field
// names are camelCase on both sides (serde rename_all + Rust->TS
// convention), so these interfaces map 1:1 to the serialized payloads.

import type { ErrorCode } from "./errors";

export interface Device {
  deviceId: string;
  deviceName: string;
  platform: string;
  online: boolean;
  pairedAtMs: number;
  lastSeenMs: number;
}

// This machine's own LAN endpoint (commands.rs `local_addresses`), so
// the UI can show what a peer should type into *their* manual-connect
// dialog. `addresses` is empty when no usable LAN address was found.
export interface LocalAddresses {
  addresses: string[];
  port: number;
}

export interface NearbyDevice {
  deviceId: string;
  deviceName: string;
  platform: string;
  addr: string;
  port: number;
}

export interface ClipboardEntry {
  // Base64-encoded raw bytes (Phase L: may be an image); empty when
  // `oversized` is true. Decode as text for text mime types, or use
  // directly in a `data:` URI for image mime types.
  content: string;
  mimeType: string;
  capturedAtMs: number;
  source: string;
  oversized: boolean;
  byteSize: number;
}

export interface Battery {
  percentage: number;
  isCharging: boolean;
  minutesRemaining: number;
  reportedAtMs: number;
}

export interface Notification {
  notificationId: string;
  appName: string;
  title: string;
  body: string;
  postedAtMs: number;
  isDismissal: boolean;
}

export interface TransferProgress {
  transferId: string;
  fileName: string;
  bytesTransferred: number;
  totalBytes: number;
  completed: boolean;
  failed: boolean;
  canceled: boolean;
  direction: "incoming" | "outgoing";
  // Sender-declared content type, forwarded from the daemon (dedicated
  // upload path only -- see the daemon's TransferProgress proto comment
  // for why outgoing/legacy-path transfers leave this empty).
  mimeType: string;
  // T-X16 display aids, not part of the daemon DTO. `finishedAtMs` is
  // stamped client-side by useDaemon the moment a live transfer reaches
  // a terminal state, so the history list can sort chronologically;
  // `peerDeviceId` is only present on rows built from persisted history
  // (a live in-session TransferProgress doesn't carry a peer id).
  finishedAtMs?: number;
  peerDeviceId?: string;
}

// Phase J: one persisted transfer_history row (both directions).
export interface TransferHistoryEntry {
  transferId: string;
  peerDeviceId: string;
  fileName: string;
  totalBytes: number;
  direction: "incoming" | "outgoing";
  status: "completed" | "failed" | "canceled";
  startedAtMs: number;
  finishedAtMs: number;
}

export interface PairingPrompt {
  requesterDeviceId: string;
  requesterDeviceName: string;
  pinCode: string;
  pinExpiresAtMs: number;
}

export interface LocalState {
  deviceId: string;
  deviceName: string;
  capabilities: string[];
  clipboardHistory: ClipboardEntry[];
  latestBattery: Battery | null;
  notifications: Notification[];
  nearbyDevices: NearbyDevice[];
  remoteInputEnabled: boolean;
  clipboardSyncEnabled: boolean;
}

export interface PairOutcome {
  accepted: boolean;
  pinExpiresAtMs: number;
}

// A pre-generated pairing code for a QR (scan-to-pair). pinCode is
// exactly what a subsequent Pair/ConfirmPin exchange checks against.
export interface PairingCode {
  pinCode: string;
  pinExpiresAtMs: number;
}

// Fired once the requester confirms the PIN this device was showing
// (responder side) -- the dialog otherwise has no way to learn it
// succeeded and would sit on the code until the countdown expires.
export interface PairingCompletion {
  requesterDeviceId: string;
  requesterDeviceName: string;
}

// Discriminated union mirroring dto.rs LocalEventDto (serde tag="kind").
export type LocalEvent =
  | { kind: "pairingRequested"; prompt: PairingPrompt }
  | { kind: "battery"; battery: Battery }
  | { kind: "notification"; notification: Notification }
  | { kind: "clipboard"; entry: ClipboardEntry }
  | { kind: "transferProgress"; progress: TransferProgress }
  | { kind: "pairingCompleted"; completion: PairingCompletion };

export interface DaemonStatus {
  connected: boolean;
}

export interface DaemonStatusDto {
  running: boolean;
  reachable: boolean;
  rttMs: number | null;
  // T-602: the wire ErrorCode name (e.g. "UNSPECIFIED"), not raw daemon
  // text -- look up a translated message via errorCodeMessage() rather
  // than rendering this directly.
  errorCode: ErrorCode | null;
}

export type DiagnosticStatus = "ok" | "warn" | "error";

// System Doctor (T-F7/F8): one check result from the daemon's diagnostics
// engine, mirrored 1:1 from the wire so the panel and `connectibled doctor`
// render identical data.
export interface DiagnosticCheck {
  id: string;
  title: string;
  category: string; // "environment" | "network" | "pairing" | "features"
  status: DiagnosticStatus;
  summary: string;
  detail: string; // "" when absent
  remediation: string; // "" when absent
  data: Record<string, string>;
  summaryKey: string; // "" = no stable template; fall back to `summary`
  remediationKey: string; // "" = no stable template; fall back to `remediation`
}

export interface DiagnosticsReport {
  checks: DiagnosticCheck[];
  worst: DiagnosticStatus;
}
