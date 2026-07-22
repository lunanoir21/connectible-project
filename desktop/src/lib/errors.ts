// ErrorCode -> user-facing message mapping (T-602), implementing the
// design in design-docs/error-code-mapping.md. Mirrors
// proto/connectible.proto's `ErrorCode` enum as a hand-written string
// union rather than generated code -- the enum is small and stable, so
// per the design doc it is kept in sync by hand across desktop/mobile.
//
// The Rust side threads this same set of names through `DesktopError`
// (`desktop/core/src/lib.rs`'s `code()`/`code_name()`) and the Tauri
// command boundary (`desktop/src-tauri/src/commands.rs`'s `CmdError`),
// so a value received here always matches one of these variants -- but
// `isErrorCode` still guards the untrusted boundary (`ipc.ts`) rather
// than assuming that invariant holds forever.

import type { Translate, TranslationKey } from "../i18n";

export type ErrorCode =
  | "UNSPECIFIED"
  | "UNAUTHENTICATED"
  | "PAIRING_REJECTED"
  | "PAIRING_TIMEOUT"
  | "DEVICE_NOT_FOUND"
  | "FILE_TRANSFER_FAILED"
  | "CHECKSUM_MISMATCH"
  | "UNSUPPORTED_PLATFORM"
  | "INTERNAL"
  | "PROTOCOL_VERSION_MISMATCH"
  | "RATE_LIMITED"
  | "FINGERPRINT_CHANGED";

const MESSAGE_KEYS: Record<ErrorCode, TranslationKey> = {
  UNSPECIFIED: "errors.unspecified",
  UNAUTHENTICATED: "errors.unauthenticated",
  PAIRING_REJECTED: "errors.pairingRejected",
  PAIRING_TIMEOUT: "errors.pairingTimeout",
  DEVICE_NOT_FOUND: "errors.deviceNotFound",
  FILE_TRANSFER_FAILED: "errors.fileTransferFailed",
  CHECKSUM_MISMATCH: "errors.checksumMismatch",
  UNSUPPORTED_PLATFORM: "errors.unsupportedPlatform",
  INTERNAL: "errors.internal",
  PROTOCOL_VERSION_MISMATCH: "errors.protocolVersionMismatch",
  RATE_LIMITED: "errors.rateLimited",
  FINGERPRINT_CHANGED: "errors.fingerprintChanged",
};

/// True for any string that is a valid wire `ErrorCode` name. Used to
/// validate values crossing the Tauri IPC boundary (`ipc.ts`) before
/// trusting them -- an unrecognized code (e.g. a future `ErrorCode`
/// added to the proto without a matching row here yet) falls back to
/// UNSPECIFIED instead of indexing `MESSAGE_KEYS` with an unknown key.
export function isErrorCode(value: string): value is ErrorCode {
  return Object.prototype.hasOwnProperty.call(MESSAGE_KEYS, value);
}

/// Maps a wire `ErrorCode` to a specific, translated, actionable
/// message (T-602). Takes `t` explicitly rather than importing a hook
/// directly, matching this codebase's existing convention for label
/// helpers called from outside a component body (e.g. TransferPanel's
/// `statusLabel(row, t)`), which keeps this function trivially testable
/// without rendering React.
export function errorCodeMessage(code: ErrorCode, t: Translate): string {
  return t(MESSAGE_KEYS[code]);
}
