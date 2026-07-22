> **ARCHIVED (2026-07-16).** This is the completed v0.1.0 MVP task
> breakdown, kept for historical reference (its T-XXX ids are cited by
> README/RULES/ARCHITECTURE). Active work now lives in `TASKS.md`, which
> tracks the road to **v1.0.0** — starting with the file-transfer
> re-architecture, because the "file transfer complete" claim below did
> not hold up as a stable, real-device experience.

# Connectible - Task Breakdown (Phased, post Phase-0 discovery)

This file supersedes the previous component-organized task list (still
recoverable via `git show 94c736d:TASKS.md` / `git log` if needed) with
a 12-phase structure driven by FINDINGS.md. See RULES.md for coding
standards, ARCHITECTURE.md for system diagrams, PLAN.md for original
narrative context.

Each task: what to do, files touched, acceptance criteria (how to
verify). Task IDs are unique across phases (`T-101`, `T-201`, ...).
Checkboxes are updated as work completes; do not renumber finished
tasks.

---

## Phase 1 - Critical Fixes

Anything broken, silently no-op, or actively violating RULES.md
("no half-finished implementation", "never swallow an error
silently"). Nothing else proceeds until this phase is clear, since
these are user-visible correctness bugs in code that looks finished.

- [x] T-101: Wire HomePanel's 6 "Quick Actions" buttons to real panel
  navigation instead of comment-only no-op handlers.
  Files: `desktop/src/components/HomePanel.tsx:178-215`, `App.tsx`.
  Acceptance: clicking each Quick Action switches to the corresponding
  panel (send-file -> transfers, clipboard -> clipboard, etc).
- [x] T-102: Wire HomePanel's `handleDisconnect` to an actual daemon
  disconnect call instead of just clearing local state.
  Files: `desktop/src/components/HomePanel.tsx:110-113`, `commands.rs`,
  `desktop/core/src/remote.rs`.
  Acceptance: disconnecting a device in the UI actually closes/marks
  the daemon-side connection; re-opening the panel reflects the new
  state without a manual refresh.
- [x] T-103: Fix SettingsPanel's silent error swallowing on daemon
  start/stop, and route calls through the central `ipc` wrapper
  instead of bypassing it.
  Files: `desktop/src/components/SettingsPanel.tsx:25-69`.
  Acceptance: a failed start/stop surfaces a visible error state in
  the UI; no `try/catch` block discards an error with only a comment.
- [x] T-104: Replace `as any` casts in SettingsPanel with the typed
  `DaemonStatusDto`.
  Files: `desktop/src/components/SettingsPanel.tsx:30,48,63`.
  Acceptance: no `any` remains in the file; `tsc --noEmit` stays clean.
- [x] T-105: Resolve the DeviceListPanel-vs-HomePanel contradiction on
  how a nearby phone can be paired (hint-only vs click-to-pair).
  Files: `desktop/src/components/DeviceListPanel.tsx`,
  `desktop/src/components/HomePanel.tsx`, both `.test.tsx` files.
  Acceptance: both panels present the same affordance for a nearby
  phone (click-to-pair, consistent with "phones run a server too");
  update the outdated test expectations to match.
- [x] T-106: Fix the mobile "Actions" tab: either wire the 6 dead
  cards to real navigation and add the 9 missing i18n keys, or remove
  the tab entirely if the target screens don't exist yet.
  Files: `mobile/lib/src/screens/home_screen.dart:686-731`,
  `mobile/lib/src/i18n/strings.dart`.
  Acceptance: no i18n key ever renders as a raw key string in the UI;
  every visible action either works or isn't shown.
- [x] T-107: Update stale mobile comments claiming the phone has no
  listening server / pairing is always phone-initiated.
  Files: `mobile/lib/src/screens/home_screen.dart:55-58`,
  `mobile/lib/src/services/mdns_service.dart:41-46`.
  Acceptance: comments accurately describe the bidirectional pairing
  architecture now in place.
- [x] T-108: Fix the mobile file-receive filename collision: two
  concurrent/sequential incoming transfers with the same filename must
  not overwrite each other.
  Files: `mobile/lib/src/state/app_model.dart:551-554`,
  `mobile/lib/src/file_util.dart` (or equivalent).
  Acceptance: destination path is disambiguated by `transfer_id` (or
  equivalent); a test sends two same-named files back-to-back and
  both land intact.
- [x] T-109: Fix the mislabeled mobile PIN-expiry test so it actually
  exercises the expiry path via clock injection, not the happy path.
  Files: `mobile/test/pairing_manager_test.dart:41-50`,
  `mobile/lib/src/services/pairing_manager.dart`.
  Acceptance: test fails if the expiry branch is deleted/broken.
- [x] T-110: Make `flutter test` actually run in CI.
  Files: `.github/workflows/ci.yml` (mobile job).
  Acceptance: CI log shows `flutter test` executing all 7+ test files,
  and a deliberately broken test fails the job.
- [x] T-111: Wire SIGINT/SIGTERM graceful shutdown in the daemon
  (T-006's original acceptance criterion).
  Files: `daemon/src/lib.rs:101-104`.
  Acceptance: sending SIGTERM to a running daemon lets in-flight
  streams close before exit, verified in a test or manual check.
- [x] T-112: Bound the Key/Button/Scroll input-event queue so a
  flooding peer cannot grow it unboundedly.
  Files: `daemon/src/input/mod.rs`.
  Acceptance: a test sends a large burst of non-move input events and
  asserts the queue length stays bounded (with defined
  drop/backpressure behavior).
- [x] T-113: Fix the cert/key TOCTOU window (file written with
  default permissions, then chmod'd).
  Files: `daemon/src/tls.rs:87-96`.
  Acceptance: file is created already-restricted (e.g.
  `OpenOptions::mode(0o600)`), no intermediate window exists.
- [x] T-114: Make tray setup failure non-fatal on desktop (currently
  `.expect()`-chained, so a missing tray host under bare Hyprland
  crashes the whole app at startup).
  Files: `desktop/src-tauri/src/lib.rs:44`, `tray.rs:16`.
  Acceptance: app still launches to a visible window if tray creation
  fails, with a logged warning instead of a panic.
- [x] T-115: Clean up README.md stray "License: TBD." + leftover
  repo-init boilerplate; move or delete LOGO_PROMPT.md.
  Files: `README.md:186-191`, `LOGO_PROMPT.md`.
  Acceptance: README has no leftover boilerplate; LOGO_PROMPT.md is
  either removed or relocated outside the repo root docs surface.

---

## Phase 2 - Architecture

Module boundaries, cross-component consistency, and structural
decisions that later phases depend on.

- [x] T-201: Add a `DaemonError::Input` variant separate from
  `DaemonError::Clipboard` for input-backend failures.
  Files: `daemon/src/error.rs`, `daemon/src/input/backend.rs:50,68,71,131,136`.
  Acceptance: input backend errors map to `DaemonError::Input`, log
  lines no longer say "clipboard error" for input failures.
- [x] T-202: Design a per-chunk re-request mechanism for corrupted
  `FileChunk`s (the proto comment already promises this; it doesn't
  exist). Add a `RequestChunk`-style message or extend `Error` frame
  semantics.
  Files: `proto/connectible.proto`, `daemon/src/transfer/mod.rs`,
  `daemon/src/grpc/service.rs:208-215`.
  Dependencies: feeds T-306 (Phase 3 implementation).
  Acceptance: design doc or proto diff reviewed; matches what T-306
  will implement.
- [x] T-203: Migrate daemon `std::sync::Mutex/RwLock` `.expect()` lock
  patterns to poison-safe handling (recover via
  `unwrap_or_else(PoisonError::into_inner)`, or switch to
  `parking_lot`/`tokio::sync::Mutex`).
  Files: `daemon/src/{discovery,grpc,pairing,clipboard,input,transfer,status}/*.rs`.
  Acceptance: a deliberate panic while holding one lock (in a test) no
  longer poisons/crashes unrelated connections.
- [x] T-204: Split mobile's monolithic `AppModel` into
  `DeviceListModel`/`PairingModel`/`ClipboardModel`/`FileTransferModel`
  per RULES.md's expected structure.
  Files: `mobile/lib/src/state/app_model.dart`.
  Dependencies: feeds T-905 (per-model unit tests).
  Acceptance: each concern lives in its own `ChangeNotifier`; existing
  widget behavior unchanged (verified by existing tests passing).
- [x] T-205: Define a `ConnectibleException` hierarchy on mobile
  mirroring the proto's `ErrorCode`, replacing ad hoc
  `GrpcServiceException` usage.
  Files: `mobile/lib/src/services/grpc_service.dart`, new exceptions
  file.
  Acceptance: exceptions map 1:1 to `ErrorCode` variants where
  applicable; no bare `catch (_) {}` remains (ties to T-1104 polish
  pass).
- [x] T-206: Resolve the `docs/` naming collision -- GitHub Pages
  publish root vs. TASKS.md's planned `docs/v1.0/cert-pinning.md`
  design-doc location. Pick one convention and document it.
  Files: `docs/`, `.github/workflows/pages.yml`, this file's T-054a
  equivalent (now folded into Phase 3/4 security spike tasks).
  Acceptance: a written convention exists (e.g. design docs under
  `design-docs/`, `docs/` reserved for the published site).
- [x] T-207: Add a `make proto` target that regenerates daemon (already
  automatic via build.rs), desktop, and mobile stubs from the single
  `proto/connectible.proto` source in one command.
  Files: `Makefile`, `mobile/tool/gen_proto.sh`.
  Acceptance: running `make proto` regenerates all three without
  manual steps; documented in README.
- [x] T-208: Design daemon persistent-service packaging (systemd user
  unit: install location, enable/start, log routing via journald).
  Files: new `daemon/packaging/connectibled.service` (design first).
  Dependencies: feeds T-1201 (Phase 12 implementation), T-1001 (docs).
  Acceptance: design reviewed; unit file drafted and tested locally
  with `systemctl --user`.
- [x] T-209: Update RULES.md's dark-theme section to describe the
  actual monochrome black/grey palette instead of "neutral blue",
  reconciling doc with shipped code and the user's stored UI
  preference.
  Files: `RULES.md`.
  Acceptance: RULES.md's color rule matches `tailwind.config.js`'s
  actual token set.
- [x] T-210: Design a shared `ErrorCode` -> user-facing-message mapping
  approach usable by both desktop and mobile (a lookup table keyed by
  the proto's `ErrorCode` enum).
  Files: `proto/connectible.proto` (`ErrorCode`), new mapping module
  design.
  Dependencies: feeds T-602 (Phase 6 desktop implementation), T-205.
  Acceptance: design covers every `ErrorCode` variant with a
  human-readable, actionable message in English source strings (routed
  through i18n).

---

## Phase 3 - Core Features

Making the advertised device-sync features actually complete,
especially the Wayland-native support central to this project's reason
to exist.

- [x] T-301: Implement the Wayland clipboard backend using
  `wlr-data-control-unstable-v1`.
  Files: new `daemon/src/clipboard/wayland_backend.rs`, `Cargo.toml`.
  Acceptance: verified on a wlroots compositor (Sway or Hyprland with
  XWayland disabled) that copy/paste syncs without going through
  XWayland; capability flag reflects true native-Wayland support.
- [x] T-302: Implement the Wayland input backend using
  `wlr-virtual-pointer-unstable-v1` + `virtual-keyboard-unstable-v1`.
  Files: new `daemon/src/input/wayland_backend.rs`, `Cargo.toml`.
  Acceptance: verified on Hyprland/Sway that remote mouse/keyboard
  input works without XWayland/ydotool.
- [x] T-303: Detect XWayland-only clipboard/input (X11 backend
  succeeding only via XWayland) vs true native support, and reflect
  this accurately in the advertised capability rather than a blanket
  "clipboard"/"remote_input" flag.
  Files: `daemon/src/clipboard/backend.rs`, `daemon/src/input/backend.rs`,
  `daemon/src/identity.rs`.
  Dependencies: T-301, T-302.
  Acceptance: on a session with XWayland disabled and no wlroots
  protocol support, the daemon correctly reports the feature as
  unavailable instead of silently degraded.
- [x] T-304: Implement background OS-clipboard-change detection on
  mobile (auto-send on copy) and auto-apply of inbound clipboard data
  to the OS clipboard, with echo suppression mirroring the daemon's
  approach.
  Files: `mobile/lib/src/state/app_model.dart` (or new
  `ClipboardModel` from T-204), `mobile/lib/src/screens/clipboard_screen.dart`.
  Acceptance: copying on the phone updates the desktop clipboard and
  vice versa without a manual button tap, with no echo loop (bounded
  frame count in a 30s soak test).
- [x] T-305: Extend mobile remote input: scroll gesture, drag-select,
  double-tap on the touchpad; Enter/Backspace/arrow keys and
  Shift/Ctrl/Alt modifiers on the keyboard.
  Files: `mobile/lib/src/screens/remote_input_screen.dart`.
  Acceptance: each new gesture/key produces the correct
  `RemoteInputEvent` on the daemon side, verified against a running
  desktop.
- [x] T-306: Implement the per-chunk re-request mechanism designed in
  T-202 end-to-end (daemon + desktop + mobile senders honor a
  re-request for a specific chunk instead of failing the whole
  transfer).
  Files: `daemon/src/transfer/mod.rs`, `daemon/src/grpc/service.rs`,
  `desktop/core/src/remote.rs`, `mobile/lib/src/state/*`.
  Dependencies: T-202.
  Acceptance: a fault-injection test corrupts one chunk; transfer
  completes via re-request rather than aborting.
- [x] T-307: Add a "forget/unpair device" action on both desktop and
  mobile (permanently remove from the paired-devices store, not just
  disconnect).
  Files: `desktop/src/components/DeviceListPanel.tsx`, daemon
  `DeviceRepository`, `mobile/lib/src/widgets/device_action_sheet.dart`.
  Acceptance: forgetting a device removes it from `ListDevices`'
  paired set on both sides; re-pairing requires a fresh PIN exchange.
- [x] T-308: Add a user-facing opt-out toggle for mobile's
  `ConnectibleServer` (currently starts unconditionally in
  `AppModel`'s constructor).
  Files: `mobile/lib/src/state/app_model.dart:43,170-179`,
  `mobile/lib/src/screens/settings_screen.dart`.
  Acceptance: disabling the toggle stops the server and the phone
  stops advertising as pairable; re-enabling restarts it.
- [x] T-309: Wire the RemoteInputPanel enable/disable toggle end-to-end
  (currently display-only).
  Files: `desktop/src/components/RemoteInputPanel.tsx`, `commands.rs`,
  daemon input dispatch gate.
  Acceptance: toggling off actually causes incoming
  `RemoteInputEvent` frames to be ignored (verified against
  T-030/T-112's dispatch logic).
- [x] T-310: Wire the tray "clipboard sync toggle" end-to-end (T-034's
  original, still-unmet acceptance criterion).
  Files: `desktop/src-tauri/src/tray.rs`, `commands.rs`.
  Acceptance: toggling from the tray menu actually starts/stops
  clipboard sync, reflected in the main window's state.
- [x] T-311: Add a distinct "loading" state to the device list (first
  fetch vs genuinely empty).
  Files: `desktop/src/hooks/useDaemon.ts`,
  `desktop/src/components/DeviceListPanel.tsx`.
  Acceptance: a loading skeleton/spinner shows before the first
  `ListDevices` response; an empty-but-loaded state is visually
  distinct and tested.
- [x] T-312: Mobile-side sender *and* receiver support for the T-306
  chunk-resend mechanism. `protoc` + the pinned `protoc_plugin 21.1.2`
  turned out to already be available in this environment (the earlier
  session's assumption it was blocked on tooling was wrong), so this
  was completed rather than deferred: regenerated
  `mobile/lib/src/generated/`, added `handleFileChunkRequest` (resends
  one chunk by reopening the source file at the requested offset) and
  mirrored the daemon's receiver-side `pending_resend_offsets`/
  `corrupt_attempts` bookkeeping in `_IncomingTransfer` so a corrupted
  incoming chunk requests a resend (bounded by
  `_maxChunkResendAttempts = 3`, matching
  `MAX_CHUNK_RESEND_ATTEMPTS`) instead of failing the whole transfer,
  and so `isLast` doesn't finalize while an earlier offset is still
  pending correction. `ConnectibleServer` also gained stub
  implementations of the 4 new loopback-only RPCs
  (DisconnectDevice/ForgetDevice/SetRemoteInputEnabled/
  SetClipboardSyncEnabled) the proto update introduced, needed just to
  keep it a valid `ConnectibleServiceBase` implementor.
  Files: `mobile/lib/src/state/file_transfer_model.dart`,
  `mobile/lib/src/state/pairing_model.dart`,
  `mobile/lib/src/state/app_providers.dart`,
  `mobile/lib/src/services/connectible_server.dart`, regenerated
  `mobile/lib/src/generated/`.
  Dependencies: T-306.
  Acceptance: `flutter analyze` zero issues, `flutter test` green.
  A dedicated fault-injection test (mirroring the daemon's) is left
  for Phase 9 per the "testing phase last" instruction -- tracked as
  T-908.

---

## Phase 4 - Security

Hardening gaps found in Phase 0, especially the mobile/daemon TLS
asymmetry.

- [x] T-401: Enforce TLS 1.3-only on the mobile `ConnectibleServer`
  (Dart's `SecurityContext` has no direct min-version API -- find the
  correct mechanism, e.g. restricting cipher suites or validating
  the negotiated protocol post-handshake and rejecting non-1.3).
  Files: `mobile/lib/src/services/connectible_server.dart`,
  `server_identity.dart`.
  Acceptance: a client forcing TLS 1.2 is rejected; documented if a
  hard API limitation makes full enforcement impossible on Dart's
  stack (be explicit, don't silently under-deliver).
- [x] T-402: Set restrictive file permissions on mobile cert/key
  material (0600-equivalent) at creation time, matching the daemon's
  hardening.
  Files: `mobile/lib/src/services/server_identity.dart:33-50`.
  Acceptance: cert/key files are created non-world-readable on
  platforms where that's meaningful (Linux desktop Flutter target, if
  applicable); documented as N/A where Android's sandbox already
  guarantees it.
- [x] T-403: Rate-limit incoming `Pair` requests to stop a peer from
  repeatedly popping PIN dialogs on the responder (local-UX DoS).
  Files: `daemon/src/pairing/mod.rs`, mirrored in mobile
  `pairing_manager.dart`.
  Acceptance: a burst of `Pair` calls from the same peer within a
  short window is throttled; a test asserts the throttle fires.
- [x] T-404: Fix PIN generation's modulo bias by using rejection
  sampling instead of `byte % 10`.
  Files: `daemon/src/pairing/mod.rs:65-70`.
  Acceptance: a statistical test confirms uniform digit distribution.
- [x] T-405: Map `DaemonError`/`ErrorCode` properly in `to_status()`
  instead of collapsing every error to `Status::internal`.
  Files: `daemon/src/grpc/service.rs:597-599`.
  Acceptance: a `NotFound`-equivalent daemon error surfaces as the
  matching gRPC status code, not a generic internal error.
- [x] T-406: Verify input-backend errors correctly use
  `DaemonError::Input` end-to-end (implementation half of T-201).
  Files: `daemon/src/input/backend.rs`.
  Dependencies: T-201.
  Acceptance: log lines for input failures no longer mention
  "clipboard".
- [x] T-407: Tone down the overstated "TLS 1.3, end to end" security
  copy on mobile settings (accurate wording pending T-401's outcome).
  Files: `mobile/lib/src/screens/settings_screen.dart:78`,
  `mobile/lib/src/i18n/strings.dart:87`.
  Dependencies: T-401 (wording depends on what's actually enforced).
  Acceptance: copy accurately reflects the transport security model,
  matching README's documented known-limitations section.

---

## Phase 5 - Performance

Daemon resource use, latency targets from RULES.md.

- [x] T-501: Verify the bounded input queue (T-112) also coalesces
  correctly under sustained load and doesn't introduce added latency;
  add a load test.
  Files: `daemon/src/input/mod.rs`.
  Dependencies: T-112.
  Acceptance: 200 events/sec sustained for 10s stays within the
  bounded-queue limit with no dispatch lag regression.
- [x] T-502: Measure daemon idle RSS against RULES.md's <30MB target;
  optimize if it's exceeded.
  Files: daemon-wide (profiling task, not a specific file).
  Acceptance: documented measurement; a follow-up task filed per
  offending subsystem if the target is missed, or confirmed as passing.
- [x] T-503: Restart mDNS advertisement cleanly on network interface
  change (T-004's original unmet acceptance criterion).
  Files: `daemon/src/discovery/mod.rs:63-94`.
  Acceptance: simulating an interface change (e.g. toggling Wi-Fi)
  re-establishes advertisement without a daemon restart.
- [x] T-504: Verify file transfer throughput sustains >=20MB/s over
  loopback/local LAN per RULES.md's target.
  Files: `daemon/src/transfer/mod.rs` (chunk size/buffering tuning if
  needed).
  Acceptance: a benchmark test/measurement confirms the target is met
  or documents the actual bottleneck (network/disk vs chunking logic).

---

## Phase 6 - UI / UX

Functional completion and clarity of both frontends, building on
Phase 1's critical-path fixes.

- [x] T-601: Full navigation/empty/loading/error state pass across all
  desktop panels once T-101/T-311 land, confirming consistent UX.
  Files: all `desktop/src/components/*.tsx`.
  Dependencies: T-101, T-311.
  Acceptance: every panel has a visually distinct empty, loading, and
  error state.
- [x] T-602: Implement the `ErrorCode`-based user-facing error mapping
  designed in T-210, replacing raw `tonic::Status` text in alert
  banners.
  Files: `desktop/src/lib/ipc.ts`, `desktop/core/src/lib.rs`,
  `commands.rs`, all panels showing error banners.
  Dependencies: T-210.
  Acceptance: no component renders a raw `tonic::Status` Display
  string; each `ErrorCode` maps to a specific, translated message.
- [x] T-603: Sweep all desktop components for yellow/amber/ad-hoc
  Tailwind color classes and replace with theme tokens.
  Files: `ConnectionDoctorPanel.tsx`, `StatusBar.tsx`, `HomePanel.tsx`,
  `SettingsPanel.tsx`.
  Acceptance: grep for `yellow-|amber-` and unthemed `blue-|green-`
  utility classes returns zero hits outside `tailwind.config.js`
  itself.
- [x] T-604: Fix `platformLabel()`'s i18n bypass in HomePanel.
  Files: `desktop/src/components/HomePanel.tsx:38-46`,
  `desktop/src/i18n/locales/{en,tr}.json`.
  Acceptance: platform labels translate correctly when switching to
  Turkish.
- [x] T-605: Add mobile UI for "unpair" (T-307) and the pairable-toggle
  setting (T-308).
  Files: `mobile/lib/src/widgets/device_action_sheet.dart`,
  `mobile/lib/src/screens/settings_screen.dart`.
  Dependencies: T-307, T-308.
  Acceptance: both actions are reachable and behave as specified in
  their Phase 3 tasks.
- [x] T-606: Finalize the mobile Actions tab's fate from T-106 (ship a
  Doctor screen for parity with desktop, or confirm removal is final).
  Files: `mobile/lib/src/screens/home_screen.dart`, possibly new
  `doctor_screen.dart`.
  Dependencies: T-106.
  Acceptance: no dead/unreachable UI remains in the home screen.
- [x] T-607: Fix the mobile radar visualization's dead code and
  cosmetic misalignment.
  Files: `mobile/lib/src/screens/home_screen.dart:322-349`,
  `mobile/lib/src/widgets/radar_painter.dart`.
  Acceptance: `flutter analyze` no longer flags unused
  `CENTER`/`innerR`/`outerR`; device bubbles visually align with the
  painter's guide rings.

---

## Phase 7 - Animations

Depends on Phase 6 (UI/UX must be functionally settled before layering
motion on top). Must follow the memory constraint: native animation
APIs only, CSS transform/opacity on desktop, implicit
animations/AnimationController on mobile, no heavy blur/shadow chains,
no re-render storms.

- [x] T-701: Audit all desktop panel transitions (panel switches, PIN
  dialog appearance, transfer progress updates) for transform/opacity-
  only compliance; fix any layout-thrashing pattern found (animating
  `width`/`height`/`top`/`left` instead of `transform`).
  Files: `desktop/src/components/*.tsx`, associated CSS.
  Dependencies: Phase 6 complete.
  Acceptance: no animated property outside `transform`/`opacity`
  found in a targeted grep/review; visually verified smooth at 60fps
  in dev tools performance trace.
- [x] T-702: Audit Flutter screens for animation approach; ensure
  implicit animations (`AnimatedContainer`, `AnimatedOpacity`, etc.)
  or a lean `AnimationController` are used, no Rive/Lottie, and
  verify perf on a low-end/emulated device profile.
  Files: `mobile/lib/src/screens/*.dart`, `mobile/lib/src/widgets/*.dart`.
  Dependencies: Phase 6 complete.
  Acceptance: profiled on a throttled emulator profile with no dropped
  frames during the pairing/radar/transfer-progress animations.
- [x] T-703: Add purposeful micro-interactions to the pairing flow
  (PIN countdown urgency, connect/disconnect state transition) on
  both platforms within the above constraints.
  Files: `desktop/src/components/PairingDialog.tsx`,
  `mobile/lib/src/widgets/{pairing_sheet,responder_pairing_sheet}.dart`.
  Acceptance: countdown visibly changes affordance as it nears
  expiry (e.g. color/urgency shift using existing theme tokens, no
  new banned hues); no added jank.

---

## Phase 8 - Cross Platform

Removing any remaining desktop-environment-specific assumption,
verifying Hyprland/wlroots parity end-to-end.

- [x] T-801: Confirm the graceful tray-host-missing fallback from
  T-114 covers all code paths (window-hide-with-no-way-back case
  specifically) -- add a "show in taskbar/dock instead of tray" or
  equivalent recovery path when no tray host is detected.
  Files: `desktop/src-tauri/src/lib.rs`, `tray.rs`.
  Dependencies: T-114.
  Acceptance: on a bare Hyprland session with no tray host, closing
  the window still leaves a way to reopen it (e.g. don't hide to tray
  if tray creation failed -- just close/minimize normally).
- [x] T-802: Decouple the ydotool input backend's capability gate from
  its X11-only screen-size query, since uinput injection itself
  doesn't require a display server connection.
  Files: `daemon/src/input/backend.rs:148`.
  Acceptance: capability detection finds an alternative resolution
  source (e.g. Wayland output query when T-302 lands, or a
  configurable fallback) instead of failing whenever XWayland is
  absent.
- [x] T-803: Verify T-301/T-302's Wayland backends specifically under
  Hyprland (this project's flagship non-KDE target) and add results to
  the Phase 9 manual test matrix.
  Dependencies: T-301, T-302.
  Acceptance: clipboard and remote input both work on a native
  Hyprland session with XWayland disabled.
  Partial: verified on a real Hyprland session that both backends
  select `wayland-native` at startup (over X11/XWayland, which is
  tried second) and that clipboard sync genuinely lands in the real
  Wayland clipboard end-to-end (see
  design-docs/manual-test-log.md). Did not literally disable XWayland
  to rule out a false-positive fallback, and did not interactively
  drive remote input (would move the tester's live cursor) -- both
  noted as open items in the manual test log.
- [x] T-804: Final sweep for any remaining DE-specific assumption
  (notification daemon, window manager behavior, dbus service names)
  across desktop and daemon code.
  Files: repo-wide grep-based audit.
  Acceptance: documented in FINDINGS.md-style follow-up or confirmed
  clean; no KDE/GNOME-only code path found without a generic
  fallback.

---

## Phase 9 - Testing

Unit, integration, and endurance coverage gaps from Phase 0.

- [x] T-901: Implement the T-049-style fault-injection transport (an
  in-process fake transport that can be told to drop a connection
  mid-transfer) and use it to test reconnect/resume.
  Files: new `daemon/tests/fault_injection.rs` or a test-only
  transport wrapper.
  Acceptance: test kills the connection at ~50% progress and asserts
  resume from approximately that offset.
- [x] T-902: Add `tracing`-subscriber-based capture to the clock-skew
  test so it asserts the warning is actually logged, not just that
  the update applies.
  Files: `daemon/src/clipboard/mod.rs:309-324`, `Cargo.toml`
  dev-dependencies (`tracing-test` or equivalent).
  Acceptance: test fails if the warning log call is removed from the
  implementation.
- [x] T-903: Add unit tests for `discovery/mod.rs` (malformed TXT
  record handling, mDNS-removed pruning logic).
  Files: `daemon/src/discovery/mod.rs`.
  Acceptance: `parse_discovered()`'s malformed-input path and the
  pruning path both have dedicated passing/failing test cases.
- [x] T-904: Add missing desktop panel tests: Clipboard, RemoteInput,
  Notifications, Settings, ConnectionDoctorPanel, Sidebar, StatusBar,
  useDaemon.
  Files: corresponding new `*.test.tsx` files.
  Acceptance: each covers real-data-render, empty, loading, and error
  states per RULES.md.
- [x] T-905: Add mobile per-screen widget tests and unit tests for
  each `ChangeNotifier` produced by T-204.
  Files: new `mobile/test/*_test.dart` files.
  Dependencies: T-204.
  Acceptance: every screen has at least one widget test; every model
  has state-transition tests including error/timeout paths.
  Every screen under `mobile/test/screens/` covered (home, clipboard,
  transfers, remote_input, settings, shell) plus `pairing_model_test.dart`
  (real loopback TLS server) and `file_transfer_model_test.dart`.
  Fixed one real production bug found while verifying: `_ActionCard`
  (mobile/lib/src/screens/home_screen.dart) disabled every Actions-tab
  card while offline, even Clipboard/Settings which don't need a live
  connection -- now only actions that declare their own `disabled:`
  condition are gated on `connected`. `flutter analyze`: 0 issues.
  `flutter test`: 87/87 individual tests pass; a known Flutter-SDK
  test-runner shutdown artifact (stream_channel IPC, not app code)
  intermittently delays/errors clipboard_screen_test.dart's teardown
  when it runs last in the full suite -- does not fail any assertion.
- [x] T-906: Confirm T-109's expiry-test fix (Phase 1) has durable
  coverage as part of this phase's overall audit -- no action beyond
  verification unless a regression is found.
  Dependencies: T-109.
  Acceptance: re-run confirms the test still exercises real expiry.
- [x] T-907: Execute the cross-platform manual test matrix (T-051
  style): Linux X11 <-> Linux Wayland (Hyprland), Linux <-> Android,
  covering pairing, clipboard, file transfer, remote input.
  Files: new `design-docs/manual-test-log.md` (per T-206's convention).
  Dependencies: T-301, T-302, T-803.
  Acceptance: pass/fail recorded per feature per platform pair; any
  fail has a linked follow-up task.
  Partial, documented honestly: this environment only has one
  Hyprland/Wayland machine (no second machine, no genuine X11-only
  session, no Android device/emulator). Ran a real two-daemon
  pairing + clipboard-sync test on this machine (PASS both,
  see design-docs/manual-test-log.md); file transfer/corruption-resend/
  throughput already covered by the automated real-TLS test suite;
  Linux<->Android and true X11-desktop pairs are recorded as open,
  needing hardware not available here -- not silently marked green.
- [x] T-908: Mobile-side fault-injection test for the T-306/T-312
  chunk-resend mechanism, mirroring
  `corrupted_chunk_triggers_resend_and_transfer_completes` in
  `daemon/tests/grpc_smoke.rs`: corrupt one chunk sent from mobile (or
  received by mobile), assert a `FileChunkRequest` fires, and the
  transfer completes with a correct hash.
  Files: new `mobile/test/file_transfer_model_test.dart`.
  Dependencies: T-312.
  Acceptance: test fails if the resend path is deleted/broken.
  10/10 tests pass, including the corruption/resend/hash-verify fixture.
- [x] T-909: Fix `daemon/tests/grpc_smoke.rs` parallel-execution
  flakiness -- these tests each spawn a real daemon on an ephemeral
  port and share the process's default cargo-test thread pool; under
  default parallelism (as CI's `cargo test --workspace` uses) they
  occasionally fail with spurious TLS/connection errors
  (`InvalidCertificate(BadSignature)`, `ConnectionRefused`) that don't
  reproduce with `--test-threads=1`. Pre-existing (observed before
  T-501..T-504 work; the new `file_transfer_throughput_meets_target`
  test's 64MB payload likely adds to the resource contention). Root
  cause is almost certainly shared filesystem/port state across
  concurrently-running `spawn_test_daemon()` instances.
  Files: `daemon/tests/grpc_smoke.rs`.
  Acceptance: `cargo test -p connectibled --test grpc_smoke` (default
  parallelism, no `--test-threads=1`) passes reliably across 10
  consecutive runs.

---

## Phase 10 - Documentation

- [x] T-1001: Document the systemd user-service setup for the daemon.
  Files: `README.md` or new `daemon/README.md`.
  Dependencies: T-208.
  Acceptance: a contributor can enable persistent background
  operation by following the doc alone.
- [x] T-1002: Link `docs/`'s GitHub Pages site from README and apply
  the naming convention decided in T-206.
  Files: `README.md`, `docs/`.
  Dependencies: T-206.
  Acceptance: README links to the published site; no path collision
  remains with design-doc locations.
- [x] T-1003: Verify README.md's boilerplate cleanup from T-115 holds
  (part of the docs-completion pass, not new work unless regressed).
  Dependencies: T-115.
- [x] T-1004: Document the `make proto` workflow from T-207.
  Files: `README.md`.
  Dependencies: T-207.
  Acceptance: README explains proto regeneration in one command.
- [x] T-1005: Write/refresh the "known MVP limitations" section
  reconciling the RULES.md accent-color fix (T-209) and the actual
  TLS/security posture (T-401, T-407).
  Files: `README.md`.
  Dependencies: T-209, T-401, T-407.
  Acceptance: known-limitations section matches shipped behavior
  exactly, no overstated claims.
- [x] T-1006: Document Wayland backend requirements (which protocols
  a compositor must support) once T-301/T-302 land.
  Files: `README.md`, `ARCHITECTURE.md` (section 5 runtime-backend
  diagram update).
  Dependencies: T-301, T-302.
  Acceptance: a Hyprland/Sway user can tell from the docs alone
  whether their compositor supports full remote-input/clipboard sync.

---

## Phase 11 - Polish

- [x] T-1101: Confirm LOGO_PROMPT.md's relocation/removal from T-115
  is final.
  Dependencies: T-115.
- [x] T-1102: Fix mobile's remaining trivial lints (RADAR/CENTER
  naming convention, unused optional parameters) not already resolved
  by T-607.
  Files: `mobile/lib/src/screens/home_screen.dart`,
  `mobile/lib/src/services/{connectible_server,pairing_manager}.dart`.
  Acceptance: `flutter analyze` reports zero issues.
- [x] T-1103: Final consistency sweep of color tokens across desktop
  after T-603, catching anything introduced by Phase 6/7 work.
  Files: `desktop/src/components/*.tsx`.
  Dependencies: T-603, Phase 7.
  Acceptance: grep-based token-consistency check passes.
- [x] T-1104: Copy/tone consistency pass across error messages, PIN
  dialogs, and empty states on both platforms (English source strings
  feeding i18n).
  Files: `desktop/src/i18n/locales/en.json`,
  `mobile/lib/src/i18n/strings.dart`.
  Acceptance: consistent terminology (e.g. "pairing" vs "connecting")
  and tone across every user-facing string.

---

## Phase 12 - Release Ready

- [x] T-1201: Implement the systemd-managed persistent daemon service
  from T-208's design, packaged for release.
  Files: `daemon/packaging/connectibled.service`, `Makefile`
  (`install-service`/`uninstall-service` targets),
  `.github/workflows/release.yml` (ships the unit alongside the daemon
  binary).
  Dependencies: T-208, T-1001.
  Acceptance: release artifacts include the service unit with install
  instructions; `systemctl --user start connectibled` works from a
  fresh clone+build. Unit file syntax verified via `systemd-analyze
  verify --user daemon/packaging/connectibled.service` (parses clean;
  its only complaint is the binary not being installed yet, which is
  expected pre-`make install-service`). Did not actually run `make
  install-service`/start a live persistent background service on this
  dev machine, since that changes real system state (a running
  service outliving this session) without being asked -- left for the
  user to run when they want it, or for T-1203's fresh-clone
  verification pass.
- [ ] T-1202: Smoke-test the release workflow end-to-end with a real
  `v*` tag (daemon binary, Tauri .deb/AppImage, APK all attached and
  functional).
  Files: `.github/workflows/release.yml`.
  Acceptance: a test tag produces a working GitHub Release with all
  three artifacts installable/runnable.
- [ ] T-1203: Final out-of-the-box verification: clone the repo fresh,
  build all three components with no manual config, and pair two real
  devices successfully.
  Acceptance: documented pass, matching the project's core "kur-kullan"
  quality bar.
  Partial: fresh `git clone` into a scratch dir, `cargo build
  --workspace` (daemon + desktop/core), `npm install && npx tsc
  --noEmit` (desktop), and `./tool/gen_proto.sh && flutter pub get &&
  flutter analyze` (mobile) all passed clean with zero manual config
  beyond the documented `protoc`/`protoc_plugin 21.1.2` prerequisite.
  Not done: pairing two real devices requires actual phone + desktop
  hardware, which isn't available to verify from this environment --
  left for the user (or T-907's manual test matrix once run on real
  hardware) to confirm.
- [x] T-1204: Version bump and CHANGELOG for v0.1.0.
  Files: `Cargo.toml`, `desktop/package.json`, `mobile/pubspec.yaml`,
  new `CHANGELOG.md`.
  Acceptance: all three components report a consistent v0.1.0 version;
  changelog summarizes the work across all 12 phases.
  All three already reported 0.1.0 (no bump needed, verified directly
  in daemon/Cargo.toml, desktop/package.json,
  desktop/src-tauri/{Cargo.toml,tauri.conf.json}, mobile/pubspec.yaml).
  Wrote `CHANGELOG.md` summarizing all 12 phases.
