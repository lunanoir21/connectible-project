# Connectible - Findings (Phase 0 Discovery)

Date: 2026-07-12. This document is the result of an end-to-end sweep of
the current working tree (including the 38 files of uncommitted changes
visible in `git status`). `cargo check --workspace --all-targets`,
`npx tsc --noEmit` (desktop), and `flutter analyze` (mobile) were all
run: all three passed clean (mobile has 13 minor lints only). The
project is not in a "doesn't compile" state -- most features already
work. The findings below were turned into the phased plan in TASKS.md.

---

## 1. Daemon (Rust)

### Solid / complete
- mDNS advertise + discovery, TLS 1.3 (rustls, no TLS 1.2 fallback),
  self-signed cert (ECDSA P-256), SQLite + sqlx migrations, device
  repository, Pair/ConfirmPin (CSPRNG PIN, constant-time compare,
  3-attempt lockout), clipboard sync + echo suppression + history,
  chunked file transfer + resume + CRC32/SHA-256 verification, ydotool
  X11 input backend, battery/notification forwarding.
- Test coverage is broad and realistic (real over-the-wire TLS e2e
  tests in `daemon/tests/grpc_smoke.rs`).

### Missing / broken
- **No Wayland clipboard backend** (`wlr-data-control-unstable-v1`) --
  `daemon/src/clipboard/backend.rs:58-72` only tries X11; no
  wayland-client dependency exists in `Cargo.toml` at all.
- **No Wayland input backend** (`wlr-virtual-pointer`/`virtual-keyboard`)
  -- same story at `daemon/src/input/backend.rs:143-156`.
- Hyprland-specific risk: because XWayland runs by default, the X11
  backends "succeed" and advertise capability, but won't observe
  native-Wayland-app clipboard/input -- a false-positive capability
  flag (silently degraded functionality, not a crash).
- `daemon/src/lib.rs:101-104` -- SIGINT/SIGTERM graceful shutdown is
  not wired (T-006 acceptance criterion unmet); tokio's "signal"
  feature is enabled but unused.
- Systemic: every `Mutex`/`RwLock` access uses `.expect("lock
  poisoned")` (discovery/mod.rs, grpc/service.rs, pairing/mod.rs,
  clipboard/mod.rs, input/mod.rs, transfer/mod.rs, status/mod.rs) --
  one task panicking poisons the lock and can cascade into every other
  connection's handler panicking.
- `daemon/src/input/mod.rs` -- mouse-move events are coalesced, but the
  Key/Button/Scroll queue has no capacity bound (DoS risk fed directly
  from the network); T-030's "bounded queue" criterion is not fully met.
- `daemon/src/tls.rs:87-96` -- cert/key file is written with default
  permissions first, then chmod'd to 0600 (a TOCTOU window).
- `daemon/src/input/backend.rs:50,68,71,131,136` -- input backend
  errors are mistakenly returned as `DaemonError::Clipboard` (no
  separate `DaemonError::Input` variant exists).
- `daemon/src/grpc/service.rs:597-599` -- `to_status()` collapses every
  error into `Status::internal`, losing the `ErrorCode` mapping (unary
  RPCs only; the streaming `Error` frame path is better-typed).
- The `FileChunk.chunk_checksum` comment in `proto/connectible.proto`
  claims a single corrupted chunk can be re-requested, but that
  mechanism doesn't exist -- only an `Error(ChecksumMismatch)` frame is
  sent; the transfer isn't aborted, but the chunk is never actually
  re-requested (T-025 partially met).
- Slight modulo bias in PIN generation (`byte % 10`) -- low risk given
  the 30s TTL + 3-attempt lockout, but fixable.
- T-049 (connection-drop fault-injection test) does not exist at all.
- T-050a (clock skew test) doesn't check whether the warning is
  actually logged, only that the update is applied.
- No unit tests exist for `discovery/mod.rs` (malformed TXT record
  parsing, pruning logic).

---

## 2. Desktop (Tauri v2 + React + TS)

### Solid / complete
- Every panel is wired to real daemon data via `useDaemon`, no mock
  data (except preview.tsx, which is explicitly documented as "NOT
  part of the shipped app").
- `ipc.ts` provides a central typed Result wrapper, used in most
  places. ConnectionDoctorPanel is fully functional (8 real diagnostic
  checks).
- desktop/core (Rust) -- local.rs (loopback, cert pinning) / remote.rs
  (remote pairing, self-signed accept) are correctly and symmetrically
  split; no `unwrap()` anywhere.

### Missing / broken
- **HomePanel.tsx:110-113** -- `handleDisconnect` just does
  `setInfo(null)`, never tells the daemon anything (comment: "Would
  call daemon to disconnect").
- **HomePanel.tsx:178-215** -- all 6 "Quick Actions" buttons are no-ops
  (comment-only handlers), no panel navigation happens.
- **RemoteInputPanel.tsx** -- the enable/disable toggle required by
  T-039 does not exist at all, it only displays capability.
- **tray.rs:10-13** -- the "clipboard sync toggle" required by T-034
  is missing from the tray menu; only show/hide/quit exist.
- **SettingsPanel.tsx:25-69** -- bypasses the central `ipc` wrapper and
  calls `invoke()` directly; the `startDaemon`/`stopDaemon` catch
  blocks silently swallow the error (comment says "// Error shown in
  status" but no code actually does that) -- exactly the silent-swallow
  pattern RULES.md forbids.
- **SettingsPanel.tsx:30,48,63** -- `as any` casts with no
  justification comment; `ipc.daemonStatus()` already returns a typed
  result and should be used instead.
- **Raw gRPC/tonic::Status text is shown to users** -- `DesktopError`
  variants in `desktop/core/src/lib.rs` are stringified
  (`commands.rs:78,84,90,115,126,142,197`) and shown directly in alert
  banners. There is no `ErrorCode`-to-message mapping anywhere (RULES.md
  explicitly forbids this).
- **Yellow/amber violation** (RULES.md "hard constraint"):
  `ConnectionDoctorPanel.tsx:142,438,454,497-498` (`yellow-500`),
  `StatusBar.tsx:84` (`yellow-400`). Also raw `blue-500`/`green-500`
  Tailwind defaults used outside the theme token system
  (ConnectionDoctorPanel.tsx:436-437, HomePanel.tsx:251,534,
  SettingsPanel.tsx:163).
- **RULES.md contradicts itself**: it says "neutral blue accent" but
  the shipped palette is fully monochrome black/grey (which matches the
  user's stored [[ui-aesthetic]] preference) -- RULES.md's text needs
  updating, not the code.
- **HomePanel.tsx:38-46** `platformLabel()` -- returns raw English
  strings, bypasses i18n (never translates when switching to Turkish).
- **Critical UX inconsistency**: `DeviceListPanel.tsx` shows a "pair
  from the phone" hint for a nearby phone (no button), while
  `HomePanel.tsx` starts pairing directly for the same device type
  (comment: "phones run a server too") -- the two panels present
  contradictory behavior for the same device kind, both locked in by
  passing tests. Concrete evidence that the bidirectional-pairing
  architecture change hasn't fully propagated through the UI.
- **useDaemon.ts** -- no distinct "loading" state; initial load and a
  genuinely empty list render identically (untested in
  DeviceListPanel's tests too).
- Missing test coverage: ClipboardPanel, RemoteInputPanel,
  NotificationsPanel, SettingsPanel, ConnectionDoctorPanel, Sidebar,
  StatusBar, useDaemon, App.tsx have no tests at all.
- `desktop-tauri/src/lib.rs:44` + `tray.rs:16` -- if tray setup fails
  (no tray host present under Hyprland), the whole app fails to start
  (`.expect()` chain); no graceful fallback exists. Similarly, the
  window hides to tray on close, but if no tray host exists the user
  has no way to bring the window back.

---

## 3. Mobile (Flutter)

### Solid / complete
- Bidirectional pairing architecture works end-to-end:
  `connectible_server.dart` stands up a real TLS gRPC server,
  `pairing_manager.dart` correctly implements the responder side
  (constant-time PIN compare, 3-attempt lockout, CSPRNG via
  `Random.secure`). `responder_pairing_sheet.dart` is correctly wired.
  A real TLS integration test exists
  (`test/integration/server_pairing_test.dart`).
- File transfer (chunked send/receive + resume + CRC32/SHA-256) is
  complete.

### Missing / broken
- **No TLS 1.3 enforcement on the mobile server** -- Dart's
  `SecurityContext` has no minimum-protocol-version API, only
  cert/key are provided; the daemon side enforces this specifically via
  rustls, mobile has no equivalent.
- **No 0600 permission hardening on mobile cert/key files**
  (`server_identity.dart:33-50`) -- Android's sandbox mitigates this
  somewhat, but it's asymmetric with the daemon side.
- **Clipboard sync is manual-only** -- no background listener for OS
  clipboard changes (only read on "Send" tap), and inbound data is
  never auto-applied to the OS clipboard (only appended to in-app
  history). Echo suppression is therefore absent too (nothing to guard
  against, since there's no auto-loop).
- **Remote input is very minimal** -- no scroll, drag-select, or
  double-tap on the touchpad; no Enter/Backspace/arrow keys/modifiers
  on the keyboard, only printable characters.
- **Battery/notification forwarding entirely absent** (a
  known/documented decision, but there's also zero groundwork in the
  Android manifest -- if this feature is built later, the
  permission/opt-in flow needs to be built from scratch too).
- **"Actions" tab is entirely dead UI** -- `home_screen.dart:686-731`,
  none of the 6 cards navigate anywhere; there is no "doctor" screen on
  mobile at all. 9 i18n keys (`common.actions`, `clipboard.history`,
  `input.eyebrow`, etc.) are not defined in `strings.dart` at all -- if
  the cards were ever wired up, users would see raw key strings.
- **Dead code in the radar visualization**
  (`home_screen.dart:322-349`) -- `CENTER` is never used, `innerR`/
  `outerR` are computed but unused; `RadarPainter`'s own hardcoded
  ratios don't visually align with device placement (a design
  inconsistency).
- **Stale comments** -- `home_screen.dart:55-58` and
  `mdns_service.dart:41-46` still say "the phone has no server,
  pairing is always initiated from the phone" -- contradicted by the
  new architecture.
- **File-receive collision bug** -- the destination path for an
  incoming file is derived from the filename alone
  (`app_model.dart:551-554`, `file_util.dart:6-10`), with no
  transfer_id/peer disambiguation -- two concurrent/sequential
  transfers sharing a filename can corrupt/overwrite each other.
- **No `ConnectibleException` hierarchy exists** (RULES.md violation)
  -- only a flat `GrpcServiceException`, used inconsistently.
- **Bare `catch (_) {}` blocks** -- `main.dart:42-44`,
  `app_model.dart:605-607,613,773` -- errors silently discarded.
- **Test gap**: `pairing_manager_test.dart:41-50`'s "expired PIN" test
  doesn't actually test expiry (comment admits "would require clock
  injection", tests the happy path instead). Almost no per-screen
  widget tests exist (only one generic smoke test).
- **AppModel is one monolithic ChangeNotifier** -- RULES.md expects a
  DeviceListModel/PairingModel/ClipboardModel/FileTransferModel split
  that doesn't exist.
- **No "unpair/forget device" UI action** -- once paired, a device can
  never be permanently removed, only disconnected.
- **ConnectibleServer starts unconditionally**
  (`app_model.dart:43,170-179`) -- no setting lets the user opt out of
  being pairable.
- Overstated security copy: `settings_screen.dart:78` says "TLS 1.3,
  end to end" but the actual model is accept-any-self-signed and
  doesn't even enforce TLS 1.3 (see above).

---

## 4. Cross-cutting (proto, docs, CI, Hyprland-agnosticism, security)

### Solid / complete
- `proto/connectible.proto` fully matches RULES.md/TASKS.md; the
  bidirectional-pairing design was already symmetric (no redesign
  needed).
- README.md covers build/run, firewall/mDNS, ydotool udev rules.
  mobile/README.md covers Flutter setup (including the protoc_plugin
  pin gotcha).
- CI (`ci.yml`) runs real gates: cargo fmt/clippy/test, tsc/vitest/vite
  build, tauri build, flutter pub get + analyze. `release.yml` builds
  the musl daemon + Tauri .deb/AppImage + APK and attaches them to a
  GitHub Release.
- Security: no hardcoded secrets/keys anywhere; two self-signed-cert
  acceptance points (desktop/core/src/tls.rs, mobile
  grpc_service.dart), both narrowly scoped and documented (part of the
  v1.0-deferred cert-pinning decision, not an oversight).

### Missing / broken
- **No systemd unit or install script for connectibled at all** -- a
  critical gap for the "stay up for days" goal; the only run paths
  today are foreground `cargo run`/binary execution or the Makefile's
  fragile background+trap approach.
- **`flutter test` never runs in CI** (the mobile job in `ci.yml` only
  runs `flutter analyze`) -- 7 real test files are never executed,
  a direct violation of RULES.md/TASKS.md T-054.
- **`make test` also excludes mobile**, and the Makefile has no
  proto-codegen target (mobile codegen requires manually running
  `./tool/gen_proto.sh`).
- **`docs/` (new)** is a GitHub Pages landing page, not linked from
  README at all; it also collides in name with TASKS.md's planned
  `docs/v1.0/cert-pinning.md` design-doc location.
- **README.md:186-191** -- "License: TBD." plus 3 leftover
  repo-init boilerplate lines (`# connectible-project`) never cleaned
  up.
- **LOGO_PROMPT.md** -- an unreferenced scratch file at repo root with
  AI-image-generator prompts, containing non-ASCII characters; not
  part of the product or docs.
- **Tray/DE-agnosticism**: no KDE-specific dependency exists (uses
  standard StatusNotifierItem/appindicator), but if no tray host is
  present (bare Hyprland without a waybar tray module), the app fails
  hard instead of degrading gracefully (see Desktop section above).
- **ydotool backend's capability check depends on an X11 screen-size
  query** (`daemon/src/input/backend.rs:148`) -- even though uinput
  itself doesn't need a display server, capability never activates
  without an X11 connection (XWayland disabled) -- a wider side effect
  than the documented "no Wayland backend" gap.

---

## Summary: top 5 critical gaps

1. Wayland-native clipboard/input backends are entirely missing --
   the project's core promise ("not KDE-dependent, equally stable on
   Hyprland") isn't met yet (currently runs over X11/XWayland, and the
   capability flag can be misleading).
2. Bidirectional-pairing architecture hasn't fully propagated through
   the desktop/mobile UIs (DeviceListPanel vs HomePanel contradiction,
   stale comments).
3. Silently swallowed errors / no-op UI elements (SettingsPanel,
   HomePanel Quick Actions, mobile Actions tab) -- violates RULES.md's
   "no half-finished implementation" rule.
4. No service management (systemd) or graceful shutdown exists for
   the daemon to stay up reliably for days.
5. Security-hardening asymmetry: the mobile TLS server (no TLS 1.3
   enforcement, no 0600 permissions) isn't hardened to the same
   standard as the daemon.

These findings were converted into concrete, individually testable
tasks across the 12 phases in TASKS.md.
