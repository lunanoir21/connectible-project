# Glossary — project-specific terms

| Term | Meaning here |
|---|---|
| **SyncStream** | The long-lived bidirectional gRPC stream carrying `SyncFrame`s (identity, clipboard, input, notifications). NOT used for file bytes anymore. |
| **Dedicated upload path** | `PrepareUpload` + `UploadFile` RPCs — the only file-transfer mechanism (resume + streaming SHA-256). |
| **Legacy chunk path** | The removed FileChunk-over-SyncStream transfer (Phase I). Its proto field numbers 3/4/9 are `reserved`. |
| **TOFU** | Trust-On-First-Use: pin the peer's cert fingerprint at first pairing, reject changes later. Bidirectional since Phase G (with the mobile inbound asymmetry). |
| **Fingerprint / pin** | SHA-256 hex of a peer's TLS cert, stored in the daemon's `devices.cert_fingerprint` (encrypted) or mobile's paired store. |
| **Requester / responder** | Pairing roles: requester initiates `Pair` and enters the PIN shown on the responder. Both platforms can play both roles. |
| **Pre-arm(ed PIN)** | `PreArmPairingCode`: daemon mints a PIN before any requester exists so the desktop can embed it in a pairing QR. Mobile deliberately does not implement it. |
| **Ticket / token** | Upload bookkeeping: `PrepareUpload` mints an opaque token per accepted file; the `UploadFile` header must echo it. Ticket = server-side record behind the token. |
| **`.part` file** | Partial upload on disk under the transfers dir; its length is the resume offset. |
| **LocalEvent / local event stream** | `SubscribeLocalEvents` — loopback-only stream feeding the desktop UI (pairing prompts, battery, notifications, clipboard history, transfer progress). |
| **Loopback-gated / `require_loopback`** | RPCs only the local UI may call; non-loopback callers get PERMISSION_DENIED. |
| **PeerRegistry** | Daemon-side registry of open SyncStream senders, used for broadcast + online attribution. |
| **Tie / star / constellation** | The UI visual language: devices as stars, connections/transfers as hairline "ties" with endpoint dots. |
| **Phase letters** | `docs/TASKS.md`: G (TOFU), H (DB encryption), I (legacy-path removal), J (transfer history), K-N (planned). A-F belong to the archived filetransfer task file. `X*` = audit-fix campaign. |
| **T-XXn ids** | Task ids inside the task files (e.g. `T-J4`, `T-X12`). Stable references — code comments cite them. |
| **Doctor / System Doctor** | The shared diagnostics engine (daemon `diagnostics/` + `connectibled doctor` CLI + desktop panel + mobile checks). |
| **Echo guard** | Suppression that stops a device re-applying its own just-broadcast change (clipboard today; planned for notification dismiss). |
| **"Connect by address"** | Manual `addr:port` connection fallback on both platforms — mDNS is discovery-only. |
| **Received dir** | Where finalized incoming files land: desktop = OS Downloads (overridable); mobile = app-private `documents/received/` (exported per-file via "Save to..."). |
