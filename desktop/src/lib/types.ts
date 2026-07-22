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
  content: string;
  mimeType: string;
  capturedAtMs: number;
  source: string;
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

// Discriminated union mirroring dto.rs LocalEventDto (serde tag="kind").
export type LocalEvent =
  | { kind: "pairingRequested"; prompt: PairingPrompt }
  | { kind: "battery"; battery: Battery }
  | { kind: "notification"; notification: Notification }
  | { kind: "clipboard"; entry: ClipboardEntry }
  | { kind: "transferProgress"; progress: TransferProgress };

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
}

export interface DiagnosticsReport {
  checks: DiagnosticCheck[];
  worst: DiagnosticStatus;
}
