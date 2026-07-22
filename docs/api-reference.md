# Connectible — Protocol / API Reference (T-E9)

The wire contract is `proto/connectible.proto` (gRPC over TLS 1.3). This
summarizes the RPCs, their request/response shape, and error handling.
Inline proto comments are authoritative; this is the orientation layer.

## Transport & trust

- TLS 1.3 only. Each device has a long-lived self-signed cert (no CA).
- **TOFU pinning (Phase C):** the *client* pins the *server*'s cert
  fingerprint (`sha256(cert_der)`, lowercase hex) on first connect and
  rejects a changed fingerprint thereafter. The daemon server uses
  `no_client_auth`; only the dialing side pins.
- Some RPCs are **loopback-only** (local UI / TOFU store / diagnostics);
  the daemon rejects non-loopback callers with `PERMISSION_DENIED`.

## RPC groups

### Real-time sync
- `SyncStream(stream SyncFrame) -> stream SyncFrame` — bidirectional stream
  carrying clipboard, battery, notifications, and remote-input frames. Each
  `SyncFrame` is a `oneof` payload; peers send `Identity` first.

### Pairing
- `Pair(PairRequest{Identity requester}) -> PairResponse{accepted,
  pin_expires_at_ms, Error?}` — asks the responder to show a PIN. Idempotent
  while a PIN is pending; subject to a per-requester cooldown
  (`RATE_LIMITED`).
- `ConfirmPin(ConfirmPinRequest{device_id, pin_code}) ->
  ConfirmPinResponse{verified, Error?}` — submits the PIN. `device_id` is
  the *requester's own* id. Wrong/expired PIN → `verified=false` + an
  `Error` (`PAIRING_REJECTED`/`PAIRING_TIMEOUT`).

### File upload (Phase A — streamed, resumable)
- `PrepareUpload(PrepareUploadRequest{Identity sender, session_id,
  repeated UploadFileMeta}) -> PrepareUploadResponse{session_id, repeated
  UploadFileOffer}` — per file, returns a `token` + `resume_offset_bytes`
  (how many bytes the receiver already holds). Unpaired sender →
  `UNAUTHENTICATED`; a per-peer flood → `RESOURCE_EXHAUSTED`.
- `UploadFile(stream UploadFilePart) -> UploadFileResult{completed,
  bytes_received, hash_ok}` — first part is the `UploadFileHeader`
  (session/file/token/offset), then raw `chunk` bytes. The receiver streams
  to a `.part`, folds a running SHA-256, and finalizes on match; a bad hash
  → not finalized (`CHECKSUM_MISMATCH`). A dropped stream leaves a
  resumable partial.

### Devices
- `ListDevices(ListDevicesRequest{online_only}) -> ListDevicesResponse`.
- `Ping(PingRequest{sent_at_ms}) -> PongRequest` — liveness/RTT.

### Loopback-only (local UI)
- `SubscribeLocalEvents(...) -> stream LocalEvent` — pairing prompts (incl.
  the PIN to display), battery/notification forwards, clipboard history,
  transfer progress.
- `GetLocalState(...) -> GetLocalStateResponse` — one-shot snapshot for UI
  startup.
- `DisconnectDevice` / `ForgetDevice` — drop a session / permanently unpair.
- `SetRemoteInputEnabled` / `SetClipboardSyncEnabled` — feature gates
  (`FAILED_PRECONDITION` if the backend is absent).

### Loopback-only (TOFU store, Phase C)
- `GetPinnedFingerprint(device_id) -> {fingerprint}` — empty = no pin yet.
- `RecordFingerprint(device_id, fingerprint) -> {recorded}` — record-on-
  first-use / backfill; `recorded=false` for an unknown device.

### Loopback-only (System Doctor, Phase F)
- `RunDiagnostics(RunDiagnosticsRequest{check_id}) ->
  RunDiagnosticsResponse{repeated DiagnosticCheck, worst}` — runs the shared
  diagnostics engine in-process (empty `check_id` = all). Each
  `DiagnosticCheck` has `status` ∈ {ok,warn,error}, `summary`, `detail`,
  `remediation`, `data`. Mirrors `connectibled doctor`.

## Error handling (`ErrorCode`)

Peers return failures as an `Error{code, message}` envelope where the proto
has one; otherwise a `tonic::Status` code is mapped. Clients should key
user-facing messages off the **code**, never the raw text.

| ErrorCode | Meaning | Typical remediation |
|---|---|---|
| `UNAUTHENTICATED` | caller not paired | pair first |
| `PAIRING_REJECTED` | wrong PIN / declined | re-enter the PIN |
| `PAIRING_TIMEOUT` | PIN window elapsed | start pairing again |
| `DEVICE_NOT_FOUND` | unknown device id | refresh the device list |
| `FILE_TRANSFER_FAILED` | transfer aborted | retry (resumes) |
| `CHECKSUM_MISMATCH` | received bytes corrupt | retry the transfer |
| `UNSUPPORTED_PLATFORM` | feature backend absent | install the backend (e.g. ydotool) |
| `PROTOCOL_VERSION_MISMATCH` | incompatible peer versions | update both apps |
| `RATE_LIMITED` | too many attempts | wait, then retry |
| `FINGERPRINT_CHANGED` | peer cert changed since pairing (TOFU) | forget + re-pair the device |
| `INTERNAL` / `UNSPECIFIED` | unexpected | check `connectibled doctor` / logs |

Mapping is implemented once per side: daemon `error.rs`/`grpc/service.rs`
(`ErrorCode` ↔ `tonic::Code`), desktop `desktop/core` `DesktopError::code()`
+ frontend `errors.ts` (`errorCodeMessage`), mobile
`ConnectibleException`/model error strings.
