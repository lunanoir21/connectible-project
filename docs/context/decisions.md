# Settled Decisions (ADR-lite)

Do not re-litigate these in new sessions; if circumstances genuinely
changed, raise it with the owner instead of quietly diverging.
Format: decision — why — rejected alternative(s) — deeper doc.

1. **Rust daemon + Tauri/React desktop + Flutter mobile.**
   Always-on sync needs a UI-less daemon (systemd user service);
   Tauri reuses the Rust client core without shipping Chromium;
   Flutter gives the monochrome custom UI cheaply on Android.
   Rejected: Electron (footprint), single desktop app without daemon
   (dies with the window). See `docs/ARCHITECTURE.md`.

2. **gRPC over TLS 1.3, TLS 1.2 rejected on both ends.**
   One typed contract (`proto/connectible.proto`) for three stacks;
   HTTP/2 flow control doubles as file-transfer backpressure.
   Rejected: custom TCP framing, WebSockets+JSON (no typed contract,
   hand-rolled backpressure).

3. **Trust = PIN pairing + bidirectional TOFU pinning, not a CA.**
   Self-signed certs, fingerprint pinned on first use each direction;
   daemon-side client-cert pinning added Phase G. No PKI on a LAN
   tool. Exception documented: mobile's own inbound server cannot do
   the client-cert half (see decision 8). See `docs/tofu-trust-store.md`.

4. **Exactly one file-transfer path: PrepareUpload + UploadFile.**
   LocalSend-style dedicated client-streaming RPC with server-side
   resume offsets and streaming whole-file SHA-256. The legacy
   FileChunk-over-SyncStream path was REMOVED (Phase I) and its proto
   fields reserved — never reintroduce chunk framing on SyncStream.
   Accepted trade-off: no per-chunk CRC resend; a whole-file hash
   mismatch discards and retries (TLS AEAD already guarantees transit
   integrity). See `docs/TASKS.md` Phase I / T-I1.

5. **DB at-rest protection = application-level AES-256-GCM on the
   sensitive column, not SQLCipher.** Avoids musl+OpenSSL static-link
   risk in release builds; only `cert_fingerprint` is genuinely
   sensitive. Key chain: `CONNECTIBLE_DB_KEY_FILE` > OS keyring
   (Secret Service) > 0600 key file. See `docs/design/db-encryption.md`.

6. **Outgoing desktop sends bypass the local daemon.**
   `send_file` drives `RemoteDeviceClient::upload_file` straight to
   the remote peer; the local daemon never sees it. Consequence:
   outgoing transfer history is reported back via the loopback-only
   `RecordTransferHistory` RPC (Phase J). Do not "fix" this by
   proxying transfers through the local daemon.

7. **Mobile persistence = shared_preferences JSON blobs, no sqflite.**
   Small bounded datasets (paired roster, capped transfer history);
   an embedded SQL dependency is not justified. Follow
   `DeviceListModel`'s save/load pattern for new persisted state.

8. **Dart `dart:io` cannot accept self-signed CLIENT certs — tried
   and reverted.** `SecureServerSocket` chain-verifies unconditionally
   (`CERTIFICATE_VERIFY_FAILED`), no rustls-style custom verifier.
   Phone's inbound server therefore gates on paired-device-id at the
   app layer only. Do not attempt `requestClientCertificate: true`
   again (broke every pairing test; see known-issues.md).

9. **mDNS is discovery only.** Connections are always direct to
   `address:port`; both apps keep a manual connect-by-address
   fallback. Never make connectivity depend on multicast working.

10. **Loopback gating for UI-only RPCs.** Anything the local UI alone
    may call is `require_loopback`-gated in `service.rs` and returns
    PERMISSION_DENIED otherwise. Every new UI-facing RPC follows this.

11. **Monochrome black/grey UI on both platforms.** No colored
    accents beyond the existing danger red; "constellation/tie"
    visual language for connections/transfers. This is an owner
    aesthetic decision, not a placeholder.

12. **Docs layout (2026-07-22).** Root md = README/CHANGELOG/CLAUDE
    only; everything else under `docs/` (active at root of docs/,
    `design/`, `archive/`, `prompts/`, `context/`). GitHub Pages
    publishes all of `docs/`.
