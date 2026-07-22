# Changelog

All notable changes to Connectible are documented here. This is the
first tracked release; the entries below summarize the full 12-phase
stabilization pass recorded in `TASKS.md` (see that file for the
complete, task-by-task record with file references and acceptance
criteria).

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
  `design-docs/manual-test-log.md`, including real two-daemon pairing
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
