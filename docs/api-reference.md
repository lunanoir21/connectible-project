# Connectible — Protocol / API Reference (T-E9)

The wire contract is `proto/connectible.proto` (gRPC over TLS 1.3). This
summarizes the RPCs, their request/response shape, and error handling.
Inline proto comments are authoritative; this is the orientation layer.

## Transport & trust

- TLS 1.3 only. Each device has one long-lived self-signed cert (no
  CA), used as both its server identity and, since Phase G, its
  outbound client identity -- one identity per device, either role.
- **TOFU pinning, bidirectional (Phase C + Phase G):**
  - *Client pins server* (Phase C, original): the dialing side pins the
    fingerprint (`sha256(cert_der)`, lowercase hex) of the server cert
    it connects to, on first connect, and rejects a changed fingerprint
    thereafter.
  - *Server pins client* (Phase G, added 2026-07-19): the daemon now
    requests an optional client certificate (`AcceptAnyClientCert`;
    unpaired first contact still completes the handshake with nothing
    to check yet) and, on a successful `ConfirmPin`, pins the
    confirming connection's client-cert fingerprint the same way. Every
    paired-only RPC/frame (`SyncStream` frames other than `Identity`,
    `PrepareUpload`) then requires the connection's fingerprint to
    match what was pinned for the claimed `device_id`, closing the gap
    where a claimed `device_id` alone (no cryptographic binding to the
    connection) was previously enough to be treated as that peer. See
    `docs/tofu-trust-store.md`'s "Phase G" section for the full design.
  - Both directions share the same `devices.cert_fingerprint` column
    and the same `FINGERPRINT_CHANGED` error/remediation -- to the
    user, a mismatch means the same thing regardless of which
    direction caught it.
  - `UploadFile` is the one paired-only path that does **not** check
    the connection fingerprint: its authorization is an opaque,
    single-use bearer token from `PrepareUpload`, deliberately not
    connection-bound so a dropped stream can resume from a new one.
  - **Daemon-side only.** Mobile's own inbound server cannot offer the
    same `server pins client` half -- `dart:io` has no equivalent of
    rustls's fully-custom client-cert verifier, so it always rejects a
    self-signed client certificate outright. A desktop connecting into
    a phone is checked against the paired store by claimed `device_id`
    only, not a cryptographically bound connection fingerprint.
- Some RPCs are **loopback-only** (local UI / TOFU store / diagnostics);
  the daemon rejects non-loopback callers with `PERMISSION_DENIED`.

## RPC groups

### Real-time sync
- `SyncStream(stream SyncFrame) -> stream SyncFrame` — bidirectional stream
  carrying clipboard, battery, notifications, and remote-input frames. Each
  `SyncFrame` is a `oneof` payload; peers send `Identity` first.
  `NotificationData.is_dismissal=true` (title/body unset) represents a
  dismissal of a previously forwarded notification by `notification_id`,
  not a new post (Phase K).

### Pairing
- `Pair(PairRequest{Identity requester}) -> PairResponse{accepted,
  pin_expires_at_ms, Error?}` — asks the responder to show a PIN. Idempotent
  while a PIN is pending; subject to a per-requester cooldown
  (`RATE_LIMITED`).
- `ConfirmPin(ConfirmPinRequest{device_id, pin_code}) ->
  ConfirmPinResponse{verified, Error?}` — submits the PIN. `device_id` is
  the *requester's own* id. Wrong/expired PIN → `verified=false` + an
  `Error` (`PAIRING_REJECTED`/`PAIRING_TIMEOUT`).
- `PreArmPairingCode(PreArmPairingCodeRequest{}) ->
  PreArmPairingCodeResponse{pin_code, pin_expires_at_ms, Error?}` —
  loopback-only. Generates the same 6-digit PIN a subsequent `Pair` call
  will be checked against, so the local desktop UI can embed it in a QR
  code up front instead of waiting for a requester to trigger `Pair`
  first. Desktop-only today: mobile's `preArmPairingCode` handler is
  deliberately `unimplemented` (phone-shows-QR is a documented,
  decision-deferred asymmetry — see `docs/TASKS-audit-fixes.md` T-X39).

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

### Loopback-only (Transfer history, Phase J)
- `RecordTransferHistory(RecordTransferHistoryRequest{TransferHistoryEntry})
  -> RecordTransferHistoryResponse{}` — the local UI reports the outcome of
  an outgoing send it drove itself (the daemon never observes an
  RemoteDeviceClient-driven upload otherwise). Non-loopback →
  `PERMISSION_DENIED`.
- `ListTransferHistory(ListTransferHistoryRequest{limit}) ->
  ListTransferHistoryResponse{repeated TransferHistoryEntry}` — paginated
  read of persisted history (both directions), most recent first;
  `limit=0` uses a daemon-chosen default. Non-loopback → `PERMISSION_DENIED`.
  `TransferHistoryEntry.direction` ∈ {incoming,outgoing}, `.status` ∈
  {completed,failed,canceled}.

### Loopback-only (Notifications, Phase K)
- `DismissNotification(DismissNotificationRequest{notification_id}) ->
  DismissNotificationResponse{}` — the local UI dismissed a mirrored
  notification. Removes it from this daemon's own notification list
  (the same local-status path an incoming dismissal from a peer already
  takes, so this device's own UI reflects it immediately) and
  broadcasts an `is_dismissal=true` `NotificationData` frame to every
  currently-connected peer over `SyncStream`, so the originating device
  can clear the real system notification too. Broadcasting to every
  peer (not just the one this id came from) is deliberate, mirroring
  how the daemon already broadcasts local clipboard changes; a peer
  that never posted this id simply has nothing to match. Non-loopback →
  `PERMISSION_DENIED`.

### Loopback-only (System Doctor, Phase F)
- `RunDiagnostics(RunDiagnosticsRequest{check_id}) ->
  RunDiagnosticsResponse{repeated DiagnosticCheck, worst}` — runs the shared
  diagnostics engine in-process (empty `check_id` = all). Each
  `DiagnosticCheck` has `status` ∈ {ok,warn,error}, `summary`, `detail`,
  `remediation`, `data`, plus `summary_key`/`remediation_key` (T-X43):
  stable message ids for client-side localization of `summary`/
  `remediation`; empty = no stable template for that exact wording, and
  the client falls back to the raw `summary`/`remediation` text verbatim.
  Mirrors `connectibled doctor`.

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
