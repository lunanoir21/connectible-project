# Changelog

All notable changes to Connectible are documented here. This is the
first tracked release; the entries below summarize the full 12-phase
stabilization pass recorded in `TASKS.md` (see that file for the
complete, task-by-task record with file references and acceptance
criteria).

## [Unreleased]

Work since 0.1.0 spans two tracks: the roadmap phases in
`docs/TASKS.md` (G through L below; N is real-device battery
measurement and stays parked until requested) and a seven-phase
audit-fix campaign in `docs/TASKS-audit-fixes.md` (X1-X7). Both files
have the complete task-by-task record with file references and
acceptance criteria. No version bump yet -- the owner decides when to
cut the next tagged release. Listed newest first.

### Phase L — Clipboard rich content (images) (2026-07-24)

**Added**

- Clipboard sync now carries `image/png` payloads (new `mime_type` /
  binary `payload` fields on `ClipboardData`) alongside text, captured
  and applied on the daemon (Wayland `wlr-data-control-unstable-v1`
  and X11), rendered as thumbnails with a "copy image" action on
  desktop, and round-tripped on mobile via `super_clipboard`.
- A 10MB hard cap on clipboard payload size, enforced identically on
  all three platforms; an oversized copy records a metadata-only
  history entry with a clear "too large" message instead of a silent
  drop or partial send.

**Known gap:** mobile's manual "Send" button still only reads the OS
text clipboard when auto-monitor is off -- only the always-on
background poll captures images (see T-L7 in `docs/TASKS.md`).

### Phase K — Notification dismiss-sync (2026-07-23)

**Added**

- Dismissing a mirrored notification on desktop now clears the real
  notification on the paired phone (new loopback `DismissNotification`
  RPC on the daemon, `NotificationListenerService.cancelNotification`
  on Android). The phone-to-desktop direction already existed from an
  earlier phase; this closes the reverse one.
- A per-notification-id echo guard on mobile stops the OS's own
  removal callback (fired by the app's own `cancelNotification` call)
  from bouncing back out as a spurious second dismiss frame.

### Audit-fix campaign (2026-07-22/23)

Three parallel read-only audits (desktop, mobile, docs) against the
0.1.0 codebase turned into a seven-phase fix campaign; the full
task-by-task record with file references and acceptance criteria is
`docs/TASKS-audit-fixes.md`.

#### Fixed

- Phone-initiated (QR/scan) pairing now persists the requester-side
  peer and pins the observed TLS fingerprint on `ConfirmPin` success,
  so it survives a restart and a subsequent desktop-to-phone file push
  is no longer rejected as unpaired (TOFU previously never engaged in
  that direction).
- Received files on mobile are reliably reachable and no longer risk a
  crash on missing/renamed files; a UI-spawned desktop daemon no
  longer deadlocks once its stdout/stderr pipes fill past ~64KB.
- Several silent failure paths now surface actionable, localized
  errors instead of dropping them: pairing/connection failures on
  mobile's Home screen, a daemon-side `FINGERPRINT_CHANGED` rejection
  on `Pair`/`ConfirmPin`, restored transfer-history rows that were
  misreporting 0% failures as a full progress bar, and an
  externally-managed daemon's "stop" action (which previously did
  nothing silently) now shows a neutral notice pointing at `systemctl
  --user stop connectibled`.
- PIN generation, cert/key file permissions, and unbounded
  flood/queue paths hardened further across both platforms (rate
  limiting, capped registries, TOCTOU fixes) beyond what shipped in
  0.1.0.
- Mobile now acquires an Android `WifiManager` multicast lock while
  discovering and pauses mDNS sweeps while backgrounded, addressing
  reports of unreliable LAN discovery on some devices/ROMs (real-
  device confirmation still pending -- flagged for the owner).

#### Added

- `DiagnosticCheck.summary_key` / `.remediation_key` (proto field 9/10)
  give the System Doctor's `summary`/`remediation` text stable message
  ids for client-side localization, falling back to the raw string
  when empty.
- `RecordTransferHistory` / `ListTransferHistory` RPCs persist and
  paginate transfer history across daemon restarts.
- `PreArmPairingCode` RPC lets the desktop UI generate a pairing PIN
  up front to embed in a QR code, instead of waiting for a requester's
  `Pair` call.
- Android foreground service for the receiving/discoverable role: a
  persistent, low-importance notification keeps the inbound server +
  mDNS advertise + heartbeat alive under Doze/OEM background kills
  while "receiving" is on, mirroring KDE Connect's approach. Starts/
  stops in lockstep with the existing Home/Settings receiving toggle.

#### Changed

- Docs reorganized under `docs/` (context, design, archive, prompts);
  desktop and mobile "known limitations" sections rewritten to match
  current behavior (e.g. TOFU pinning, not "certs accepted without
  pinning"); GitHub Pages publishing now excludes `docs/archive/`.
- Dead code removed: desktop's pre-T-F8 doctor commands and unused
  `TransferPanel` prop, orphan `LanguageSwitcher.tsx`, and the
  UI-less "desktop drives the phone" `RemoteDeviceClient
  ::open_input_session` / `InputSession` path (git history preserves
  it for later revival).

#### Decision-deferred (owner-recorded, intentionally not changed)

- Phone-side QR pairing parity: mobile can scan a desktop-shown QR but
  not display one of its own (`preArmPairingCode` is deliberately
  unimplemented on mobile). Confirmed again in T-X39 (2026-07-22,
  Luna): not revisiting for v1.0.

### Phase J — Persisted transfer history

**Added**

- Daemon-owned `transfer_history` SQLite table serves both directions
  for desktop: incoming rows are written directly by the `upload_file`
  handler; outgoing rows are reported back via a new loopback
  `RecordTransferHistory` RPC, since an outgoing send bypasses the
  local daemon entirely (it connects straight from the UI process to
  the remote peer). A retention cap keeps the table bounded.
- Mobile persists its own transfer history independently via
  `shared_preferences` (no daemon involved, mirroring the paired-
  device-roster persistence pattern already used there).
- `TransferPanel` (desktop) and mobile's history screen now survive a
  daemon restart / app close instead of losing every completed/failed
  record.

### Phase I — Retired the legacy chunk-transfer path

**Removed**

- The original `SyncStream`-multiplexed `FileChunk` /
  `FileTransferStart` / `FileChunkRequest` frames and their daemon /
  desktop / mobile handling, superseded entirely by the dedicated
  `PrepareUpload` / `UploadFile` streaming path (resume, cancel,
  progress, and whole-file hash verification already had parity
  there). `SyncFrame` proto fields 3, 4, and 9 marked `reserved`.

**Accepted trade-off:** per-chunk corrupted-chunk resend (the old
CRC32-triggered targeted re-send) has no equivalent on the dedicated
path -- a whole-file SHA-256 mismatch now forces a full restart instead
of resending one chunk. TLS 1.3's AEAD already rules out transit
corruption, so this only affects recovery efficiency for a rare
sender-side disk/memory fault; judged an acceptable cost for removing a
second, independently-maintained transfer implementation.

### Phase H — SQLite at-rest encryption (2026-07-20)

**Security**

- `devices.cert_fingerprint` is now encrypted at rest with
  AES-256-GCM (chosen over SQLCipher to avoid a C dependency /
  static-linking risk). The key is sourced from a
  `CONNECTIBLE_DB_KEY_FILE` override, then the OS keyring (a pure-Rust
  Secret Service client, no `libdbus`), then a `0600` key-file fallback
  for headless hosts. Existing plaintext rows are migrated in place on
  daemon startup, each verified round-trip before being overwritten.
- New System Doctor check reports which key source (env override /
  keyring / fallback file) is active.

### Phase G — Bidirectional mTLS identity pinning (2026-07-20)

**Security**

- The daemon now requests (not requires) a client TLS certificate on
  every inbound connection and pins its fingerprint against the
  device_id on successful pairing -- closing a gap where anyone on the
  LAN who learned a paired device's `device_id` (visible in every mDNS
  TXT record) could impersonate it without presenting any credential.
  A later fingerprint mismatch is rejected the same way the existing
  client-side TOFU check already rejected a changed *server*
  fingerprint (`FINGERPRINT_CHANGED`).
- Desktop now presents its own long-lived identity as its outbound TLS
  client certificate too (reusing the same cert/key pair it already
  uses as a server). Mobile's outbound direction does the same.

**Known asymmetry:** a `dart:io` platform limitation (no custom
server-side client-cert verifier, unlike rustls) means mobile's own
*inbound* server can't yet perform the equivalent check -- a device
that learned a paired peer's device_id could still claim it inbound on
mobile. Documented, not silently dropped; flagged as a candidate for a
future application-layer challenge if it matters before v1.0.

## [0.1.0]

Connectible reaches a desktop-environment-agnostic, security-hardened,
tested v0.1.0 across all three components (daemon, desktop, mobile),
each at version 0.1.0.

### Added

- Native Wayland clipboard (`wlr-data-control-unstable-v1`) and remote
  input (`wlr-virtual-pointer-unstable-v1` +
  `virtual-keyboard-unstable-v1`) backends, verified on Hyprland --
  the project no longer depends on XWayland for its core sync
  features, and advertises capabilities that reflect true native
  support rather than a blanket flag.
- A per-chunk re-request mechanism for corrupted file transfers,
  implemented end-to-end (daemon sender/receiver, desktop, and
  mobile), with fault-injection tests on both the daemon and mobile
  proving a corrupted chunk triggers a resend instead of aborting the
  transfer.
- Bidirectional pairing: the mobile app runs its own gRPC/TLS server
  and `PairingManager`, so either a desktop or a phone can initiate
  pairing.
- Forget/unpair device action, a pairable opt-out toggle, and the
  remote-input and clipboard-sync tray/panel toggles wired end-to-end
  on both platforms.
- Systemd user-service packaging for the daemon
  (`daemon/packaging/connectibled.service`, `make install-service`),
  documented for persistent background operation.
- Micro-interactions across both platforms: PIN countdown urgency,
  connect/disconnect state transitions, panel/tab switch animations --
  transform/opacity-only on desktop, implicit animations or a lean
  `AnimationController` on mobile.

### Changed

- Mobile's monolithic `AppModel` split into focused `ChangeNotifier`s
  (`DeviceListModel`, `PairingModel`, `ClipboardModel`,
  `FileTransferModel`), each with its own test coverage.
- Desktop and daemon errors now map through a shared `ErrorCode` ->
  user-facing-message scheme instead of surfacing raw `tonic::Status`
  text or collapsing every failure to a generic internal error.
- UI consistency pass on both platforms: no yellow/amber/ad-hoc accent
  colors outside the monochrome theme tokens, consistent pairing/
  connecting terminology, i18n bypasses fixed.

### Fixed

- Wayland clipboard backend deadlock and a daemon shutdown hang
  (mdns-sd's `spawn_blocking` task never returning after SIGTERM) --
  both found via manual verification during the testing pass, with
  regression tests added.
- Several dead/no-op UI affordances: HomePanel's Quick Actions,
  `handleDisconnect`, the RemoteInputPanel and tray clipboard-sync
  toggles, and the mobile Actions tab's dead cards.
- PIN generation's modulo bias (rejection sampling instead of `byte %
  10`), a cert/key file-permission TOCTOU window, and an unbounded
  input-event queue that let a flooding peer grow memory without
  limit.
- TLS 1.3 enforcement gap on the mobile server, and file-permission
  hardening for mobile's cert/key material matching the daemon.
- Mobile file-receive filename collisions (two same-named incoming
  transfers no longer overwrite each other).
- A production bug found while verifying mobile test coverage:
  `_ActionCard` was disabling every Actions-tab card while offline,
  including Clipboard and Settings, which don't need a live
  connection to be useful.

### Testing

- Daemon: fault-injection resume test, clock-skew warning assertions,
  discovery unit tests for malformed TXT records, and a fix for
  `grpc_smoke.rs`'s parallel-execution flakiness.
- Desktop: full panel test coverage (Clipboard, RemoteInput,
  Notifications, Settings, ConnectionDoctorPanel, Sidebar, StatusBar,
  `useDaemon`) covering real-data-render, empty, loading, and error
  states.
- Mobile: a widget test for every screen and state-transition tests
  (including error/timeout paths) for every model, plus a
  `PairingModel` test suite driving a real loopback TLS server.
- A manual cross-platform test pass recorded in
  `docs/design/manual-test-log.md`, including real two-daemon pairing
  and clipboard sync verified on Hyprland; Linux<->Android and
  true-X11 pairs are documented as open pending hardware access.

### Known limitations

- The manual cross-platform test matrix (T-907) and the final
  out-of-the-box verification (T-1203) are partially complete: both
  are blocked on hardware not available in this environment (a second
  machine, a true X11-only session, an Android device/emulator).
  Everything verifiable without that hardware -- fresh-clone builds
  of all three components, real-daemon pairing/clipboard sync on
  Hyprland -- passed clean.
- See `README.md`'s known-limitations section for the current TLS/
  security posture and any platform-specific caveats.
