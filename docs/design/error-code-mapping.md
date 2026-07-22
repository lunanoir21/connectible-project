# ErrorCode -> user-facing message mapping (T-210)

Goal: neither desktop nor mobile should ever show a raw `tonic::Status`
or gRPC exception string to the user (FINDINGS.md flagged this as a
RULES.md violation on desktop; the same principle applies to mobile).
Every `proto/connectible.proto` `ErrorCode` value gets one canonical,
translated, actionable message, looked up by a small table on each
client, keyed by the enum value transmitted in the `Error` frame /
gRPC status.

## Table (English source strings; both platforms route through i18n)

| ErrorCode | Message | Suggested action shown to user |
|---|---|---|
| `UNSPECIFIED` | "Something went wrong." | Retry; if it persists, check the daemon logs. |
| `UNAUTHENTICATED` | "This device isn't paired yet." | Start pairing again. |
| `PAIRING_REJECTED` | "Pairing was rejected." | Confirm the PIN on both devices and try again. |
| `PAIRING_TIMEOUT` | "The pairing code expired." | Start pairing again from the beginning. |
| `DEVICE_NOT_FOUND` | "That device is no longer available." | Refresh the device list. |
| `FILE_TRANSFER_FAILED` | "The file transfer failed." | Retry the transfer. |
| `CHECKSUM_MISMATCH` | "The received file didn't match -- it may be corrupted." | Retry the transfer. |
| `UNSUPPORTED_PLATFORM` | "This feature isn't supported on that device." | No action; feature is unavailable there. |
| `INTERNAL` | "The daemon hit an internal error." | Retry; check daemon logs if it persists. |
| `PROTOCOL_VERSION_MISMATCH` | "These two apps are running incompatible versions." | Update both to the same version. |
| `RATE_LIMITED` | "Too many attempts -- please wait a moment." | Wait a few seconds before retrying. |

## Implementation shape

- **Desktop**: a `errorCodeMessage(code: ErrorCode): string` function
  in `desktop/src/lib/` (new module, e.g. `errors.ts`), consuming the
  i18n `t()` function so each row is a translation key
  (`errors.pairingTimeout`, etc.) rather than a hardcoded English
  literal. `ipc.ts`'s `Result` error variant should carry the
  structured `ErrorCode` (from `desktop/core`'s `DesktopError`) instead
  of only a display string, so components can look up the mapped
  message rather than rendering whatever `DesktopError::to_string()`
  produced. Implementation happens in T-602 (Phase 6).
- **Mobile**: the same table lives in `mobile/lib/src/i18n/strings.dart`
  keyed the same way, consumed by the `ConnectibleException` hierarchy
  from T-205 -- each exception variant carries the proto `ErrorCode`
  and a `.userMessage(AppStrings)` accessor.
- Both platforms must keep this table in sync by hand (the enum is
  small and stable; not worth codegen machinery for eleven entries).
  If `ErrorCode` gains a new variant in `connectible.proto`, add a row
  here first, then update both platforms in the same PR (per RULES.md
  proto-change discipline).
