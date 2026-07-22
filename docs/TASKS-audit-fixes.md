# Connectible - Audit Fix Campaign (2026-07-22)

Source: three parallel read-only audits run on 2026-07-22 — a desktop
audit (`desktop/src`, `desktop/src-tauri`, `desktop/core`), a mobile
audit (`mobile/lib`, `mobile/android`, `mobile/test`), and a docs
cleanup pass. Every finding below was verified against the code at
audit time with file:line evidence. This file is the single source of
truth for the fix campaign; the main roadmap stays in `docs/TASKS.md`
(Phases K-N) and is NOT superseded by this file.

Status markers: `[ ]` todo · `[~]` in progress · `[x]` done.
Mark each task `[x]` with a short **Done** note as you finish it.

## Ground rules for whoever executes this file

1. **Re-verify before you touch.** Line numbers are from the audit
   date and may have drifted. If a finding is already fixed or turns
   out to be wrong, mark the task `[x]` with a note saying so and move
   on — do not "fix" what is not broken.
2. **Phases run in order** (X1 -> X7). Tasks within a phase run in
   order unless marked independent.
3. **Verification cadence:** lightweight checks while working
   (`cargo check`, `flutter analyze`, `npx tsc --noEmit -p .`), the
   full suites once at the end of each phase:
   - `cargo test --workspace` + `cargo clippy --workspace --all-targets -- -D warnings` (repo root)
   - `npx tsc --noEmit -p .` + `npx vitest run` (from `desktop/`)
   - `flutter analyze` + `flutter test` (from `mobile/`)
4. **Conventions:** code/comments/docs in English, ASCII only.
   Monochrome black/grey UI aesthetic — no colored accents beyond the
   existing danger red. i18n: every new user-visible string gets an
   `en` + `tr` key on the platform it touches; no hardcoded English.
5. **Do not touch** `backups/` (frozen), `mobile-rn` remnants (dead),
   or anything under `docs/archive/` beyond reading. Never create new
   `.md` files at the repo root (docs live under `docs/`).
6. **No git commits** — the working tree carries other uncommitted
   work; the owner handles all commits and tags herself.
7. **Decision-gated tasks** (Phase X6) require the owner's explicit
   go-ahead — present the options and stop; do not pick silently.
8. Tests removed or intentionally skipped must be documented in the
   task's Done note, never silently dropped.

---

## Phase X1 — Mobile critical

**Why first:** finding M-K1 breaks the security AND function of the
phone-initiated (QR/scan) pairing flow — TOFU pinning never engages in
that direction, the pairing is lost on restart, and desktop->phone
file push is rejected. M-K2/M-K3 make received files effectively
inaccessible or crash-prone. Nothing else in this file matters if the
primary pairing flow is broken.

### T-X1: Persist requester-side pairing on ConfirmPin success `[x]`
**Done (2026-07-22):** Re-verified against current code — still broken as
described. Added `DeviceListModel.addPairedDeviceFromNearby(NearbyDevice)`
(shares a new `_upsertPairedPeer` helper with the responder-side
`addPairedDevice`), and `PairingModel.confirmPin` now persists the peer
immediately after PIN verification, BEFORE the fingerprint-record step.
Files: `mobile/lib/src/state/device_list_model.dart`,
`mobile/lib/src/state/pairing_model.dart`. Test: new
`pairing_model_test.dart` case "confirmPin success persists the peer on
the requester side..." — confirmPin against the loopback TLS responder,
then a fresh `DeviceListModel` on the same prefs still has the peer with
correct name (`Desk`) and platform (`PLATFORM_LINUX_X11`).
`DeviceListModel.addPairedDevice` is only ever called on the responder
path (`pairing_model.dart:182-184`, `onPeerPaired`). The phone's own
`confirmPin` success path (`pairing_model.dart:351-381`) never writes
the peer into `_pairedStore`, so a phone-initiated pairing vanishes on
restart (`_loadPairedStore` rebuilds `devices` from `_pairedStore`
only, `device_list_model.dart:168-192`). Fix: on confirm success,
persist the peer (identity data is available from the
nearby-device/manual-connect info that `startPair` received) via
`addPairedDevice` (or an equivalent that takes name/platform/host
data), BEFORE the fingerprint-record step so T-X2 has a row to pin to.
*Files:* `mobile/lib/src/state/pairing_model.dart`,
`mobile/lib/src/state/device_list_model.dart`.
*Acceptance:* new test — confirmPin success against the loopback test
server, then reconstruct `DeviceListModel` on the same prefs: the peer
is still in the paired roster with correct name/platform.

### T-X2: Requester-side TOFU pin actually records `[x]`
**Done (2026-07-22):** Verified — no production fix needed beyond T-X1:
with the store row now written first, the existing post-confirm
`recordFingerprint` call lands (and the reconnect backfill path is
unchanged). Updated the stale "no-op if the requester side didn't
persist" comment in `pairing_model.dart`. Regression test: new
`pairing_model_test.dart` case "confirmPin success pins the observed TLS
fingerprint..." — after confirmPin, `pinnedFingerprint('desk-1')` is
non-null and identical after a `DeviceListModel` reconstruction on the
same prefs.
`recordFingerprint` is a silent no-op when the device is not in the
store (`device_list_model.dart:220-240`), which — because of T-X1 —
was ALWAYS the case for phone-initiated pairings: both the
post-confirm pin attempt (`pairing_model.dart:366-369`) and the
reconnect backfill (`pairing_model.dart:503-507`) fell through, so
fingerprint pinning (MITM-on-reconnect protection) never engaged in
this direction. After T-X1 the store row exists; verify the pin now
lands, and add a regression test.
*Files:* `mobile/lib/src/state/pairing_model.dart` (verify only, or
minimal fix), `mobile/test/pairing_model_test.dart`.
*Acceptance:* test — after confirmPin success,
`pinnedFingerprint(peerId)` is non-null and survives a
`DeviceListModel` reconstruction on the same prefs.

### T-X3: Desktop->phone push accepted after phone-initiated pair `[x]`
**Done (2026-07-22):** Tests only, as planned — T-X1 removed the root
cause; no extra wiring was needed. New `pairing_model_test.dart` case "a
desktop push is accepted after a phone-initiated pair..." proves: (a)
`prepareUpload` from the peer's device_id is rejected before pairing,
accepted (offer.accepted true) after confirmPin, while a stranger id
still gets `GrpcError`; (b) an inbound SyncStream clipboard frame from
that peer is dispatched to the clipboard callback, not dropped.
The phone's `prepareUpload` gate checks `knownDevices()` =
`_pairedStore` (`pairing_model.dart:196-202`), and inbound SyncStream
frames are gated the same way (`pairing_model.dart:289-296`) — both
rejected desktop pushes after a phone-initiated pair. T-X1 fixes the
root cause; this task proves the consequence is gone.
*Files:* tests only (or whatever small wiring T-X1 left).
*Acceptance:* test — after a requester-side pair, a
`handlePrepareUpload` request from that peer's device_id is accepted
(offer.accepted true), and an inbound clipboard frame from it is
dispatched, not dropped.

### T-X4: Filter self out of the merged device list `[x]`
**Done (2026-07-22):** Re-verified — `_mergeDevices` had no self-filter.
It now drops `localIdentity.deviceId` from the merged map (covers both
the connection-reported list and a hypothetical self row in the paired
store). File: `mobile/lib/src/state/device_list_model.dart`. Tests: new
`device_list_model_test.dart` group "self-filter (T-X4)" (merging a
connection list containing the local id does not surface it); new
`home_screen_test.dart` widget test "status line names the active
peer..." (paired roster row + active session renders "Connected to
Pixel", not generic "Connected").
The daemon's `ListDevices` response includes the phone itself;
`_mergeDevices` has no self-filter (`device_list_model.dart:242-251`),
so the phone can appear in its own "Paired" list mid-session, and the
Home status line stays generic "Connected" instead of "Connected to
{name}" (`home_screen.dart:473-487`).
*Files:* `mobile/lib/src/state/device_list_model.dart`.
*Acceptance:* test — merging a connection list containing the local
device id does not surface it in `devices`; Home status line shows the
real peer's name once T-X1 rows exist.

### T-X5: Persist received-file paths in transfer history `[x]`
**Done (2026-07-22):** Re-verified — still as described. Added optional
`localPath` ('' default) to `TransferHistoryEntry` (models.dart), wrote
it for completed incoming transfers in `_recordHistory`, round-tripped
it through `_saveHistory`/`_loadHistory` (missing JSON key tolerated),
and `incomingFilePath` now falls back to the persisted entry. Files:
`mobile/lib/src/models/models.dart`,
`mobile/lib/src/state/file_transfer_model.dart` (no screen change was
needed for the fallback itself). Tests: `file_transfer_model_test.dart`
"incomingFilePath survives an app restart..." + pre-T-X5-blob
backward-compat case; `transfers_screen_test.dart` widget test proves a
restored row still offers Save to and a deleted-from-disk file degrades
to the "no longer available" snackbar without crashing.
`_incomingFinalPaths` is in-memory only
(`file_transfer_model.dart:131`) and `TransferHistoryEntry` has no
path field (`models.dart:96-117`), so after an app restart "Save
to..." on a history row reports "file no longer available"
(`transfers_screen.dart:38-42`) even though the file is still on disk
under app-private `received/` — making it permanently inaccessible
(this button is the only way out of app storage). Fix: add an optional
`localPath` field to `TransferHistoryEntry` (persisted for completed
incoming transfers; JSON key optional/backward-compatible),
`incomingFilePath` falls back to it, and the missing-file snackbar
stays for genuinely deleted files.
*Files:* `mobile/lib/src/models/models.dart`,
`mobile/lib/src/state/file_transfer_model.dart`,
`mobile/lib/src/screens/transfers_screen.dart`.
*Acceptance:* test — complete an incoming upload, reconstruct the
model on the same prefs, `incomingFilePath(id)` still resolves and the
history row offers Save to; a row whose file was deleted from disk
still degrades to the snackbar, not a crash.

### T-X6: "Save to..." must not load the whole file into RAM `[x]`
**Done.** Introduced a `SaveFileService` seam
(`mobile/lib/src/services/save_file_service.dart`) that the transfers
screen goes through; the old `File(path).readAsBytes()` +
`FilePicker.saveFile(bytes:)` route is gone. On Android the whole flow
is native (`mobile/android/.../files/SaveFilePlugin.kt`, wired via
`MainActivity.onActivityResult`): `ACTION_CREATE_DOCUMENT` picks the
destination and Kotlin streams the copy with a fixed 64 KiB buffer on
a background thread, so no file byte crosses the platform channel or
accumulates in the Dart heap. On the linux dev shell it falls back to
`FilePicker.saveFile` (path, not `bytes:`) + a dart:io
`openWrite().addStream(openRead())` disk-to-disk stream. Widget tests
inject a fake service; `_saveTo` now maps saved/canceled/failed to the
right snackbar (canceled is silent). **Real-device SAF verification
flagged for the owner** — the native picker + content-URI copy cannot
be exercised in this sandbox (no emulator); correctness here is
by-construction (fixed-size buffer loop, no whole-file read anywhere).
*Files:* `mobile/lib/src/services/save_file_service.dart` (new),
`mobile/android/.../files/SaveFilePlugin.kt` (new),
`mobile/android/.../MainActivity.kt`,
`mobile/lib/src/screens/transfers_screen.dart`,
`mobile/test/screens/transfers_screen_test.dart`.
*Acceptance:* met by construction; `flutter analyze` clean; Save-to
tests pass. On-device SAF flow is the owner's to confirm.

<details><summary>original</summary>

`transfers_screen.dart:45` does `await File(path).readAsBytes()` and
hands the whole file to `FilePicker.saveFile(bytes: ...)` — a GB-scale
video/APK (this is a LAN file-transfer tool) risks OOM on the phone,
while the receive path was deliberately written constant-memory
(`file_transfer_model.dart:377-379`). Investigate the smallest
streaming alternative first (SAF `ACTION_CREATE_DOCUMENT` via a small
platform channel + chunked copy is the known-good route; a plugin swap
is acceptable if it genuinely streams), then implement it.
*Files:* `mobile/lib/src/screens/transfers_screen.dart`, likely a
small `mobile/android/.../` platform-channel addition.
*Acceptance:* copying works for a file larger than typical heap
budgets (verifiable by construction: fixed-size buffer loop, no
whole-file `readAsBytes` anywhere in the flow); `flutter analyze`
clean; existing Save-to tests still pass.
</details>

### T-X7: Phase X1 verification `[x]`
**Done.** `flutter analyze` -> "No issues found!"; `flutter test` ->
**150 passed, 0 failed** (includes the new T-X1/T-X2/T-X3 requester-
side pairing/TOFU tests). Phase X1 complete: T-X1 through T-X7 all
done. One real-device item flagged (T-X6 on-device SAF flow).

---

## Phase X2 — Desktop critical

### T-X8: UI-spawned daemon must not deadlock on full pipes `[x]`
`start_daemon` spawns the child with
`.stdout(Stdio::piped()).stderr(Stdio::piped())`
(`desktop/src-tauri/src/commands.rs:653-654`) but nothing ever reads
those pipes; the daemon logs at `info` to stdout
(`daemon/src/main.rs:22-29`), so after ~64KB the daemon's writes block
and it silently freezes. Fix: stop piping-without-reading — either
`Stdio::null()` for both, or spawn drain tasks that forward lines into
the Tauri app's own log. Pick one, document why in a comment.
*Files:* `desktop/src-tauri/src/commands.rs`.
*Acceptance:* a UI-started daemon under `RUST_LOG=debug` keeps
responding well past 64KB of log output (scripted or manual check —
describe what was run in the Done note).
**Done (2026-07-22):** finding re-verified (same lines). Chose drain
threads over `Stdio::null()`: the daemon writes no log file, so for a
UI-spawned daemon the pipes are the only surviving diagnostics —
`spawn_daemon_log_drains` (commands.rs) forwards each line into the
app's tracing log under a `connectibled` target on detached threads
that exit on EOF (rationale in the code comment). Checks run: (1) new
unit test `commands::tests::
drained_child_writes_past_pipe_buffer_without_blocking` — a child
writing ~400KB to each pipe must exit instead of blocking; passes.
(2) Scripted repro of the old config (real daemon, RUST_LOG=debug,
stdout to a held-open never-read FIFO, 250 garbage TCP connects for
log volume): a daemon thread stuck in `pipe_write` for >2s; draining
exactly 65398 bytes (the full ~64KB pipe buffer) unblocked it. (3)
Scripted check of the fixed config (std-only harness replicating the
new spawn+drain exactly, same real daemon under RUST_LOG=debug):
204364 bytes drained over 995 connects, daemon still alive, a fresh
probe connection accepted and logged (probe_log_delta=176). `cargo
check -p connectible-desktop` + `cargo test -p connectible-desktop
--lib` (1 passed) clean.

### T-X9: Device/nearby list updates live `[x]`
No polling and no device-change LocalEvent exist: `useDaemon.ts`
(`desktop/src/hooks/useDaemon.ts:94-172`) only refreshes on bridge
reconnect / pairingCompleted / tray refresh, while the UI copy
promises "It will show up here automatically" (`en.json:101`) and
TransferPanel's target list derives from `nearby`
(`TransferPanel.tsx:63-65`) with no refresh button. Fix (smallest
correct): poll `refresh()` every ~5s while the document is visible
(mirror the existing `daemonStatus` interval in `App.tsx:63-76`),
pausing when hidden. A proto-level DeviceListChanged event is
explicitly out of scope here.
*Files:* `desktop/src/hooks/useDaemon.ts` (or `App.tsx`, wherever the
existing interval convention lives).
*Acceptance:* vitest with fake timers — a device appearing in the
mocked `listDevices`/nearby response shows up without any manual
refresh call; polling stops while hidden.
**Done (2026-07-22):** finding re-verified (refresh still only fired
on reconnect/pairingCompleted/tray). Added a visibility-gated 5s
`refresh()` poll to `useDaemon.ts` (the hook that owns refresh),
active only while the bridge is connected and
`document.visibilityState` is visible; hiding stops the interval,
re-showing does an immediate catch-up refresh then resumes the
cadence. Mirrors the App.tsx daemonStatus interval convention
including its no-change bail-out: refresh()'s setters now keep the
previous reference when the fetched value is content-identical
(`keepIfUnchanged`), so a no-change tick doesn't re-render the app
every 5s. No proto changes, no new user-visible strings. Tests: two
new fake-timer vitest cases in `useDaemon.test.ts` (device + nearby
peer appear after one tick with no manual refresh; hidden pauses
polling — 0 calls across 20s — and re-show catches up immediately
then resumes). `npx tsc --noEmit -p .` clean; `npx vitest run` 116
passed (116).

### T-X10: Phase X2 verification `[x]`
`npx tsc --noEmit -p .` + `npx vitest run` + `cargo check -p
connectible-desktop` clean.
**Done (2026-07-22):** all three run fresh after T-X8/T-X9 landed.
`npx tsc --noEmit -p .` (desktop/): exit 0, no diagnostics.
`npx vitest run` (desktop/): "Test Files  16 passed (16) / Tests  116
passed (116)". `cargo check -p connectible-desktop` (from
desktop/src-tauri/, crate is workspace-excluded): "Finished `dev`
profile [unoptimized + debuginfo] target(s)", zero warnings. Bonus:
`cargo test -p connectible-desktop --lib` runs the new T-X8 drain
regression test — "1 passed; 0 failed".

---

## Phase X3 — Desktop medium

### T-X11: "Stop daemon" gives feedback on externally-managed daemons `[x]`
**Done.** `stopDaemon` returns `Result<boolean>`; the boolean was
ignored. Now on `ok && value === false` (the app did not spawn the
running daemon), a neutral `role="status"` notice renders (distinct
from the danger `role="alert"` error path) pointing to `systemctl
--user stop connectibled`. New i18n key `settings.daemonExternal`
(en+tr). 2 vitest cases: value:false renders the notice + no alert;
value:true renders no notice.
*Files:* `desktop/src/components/SettingsPanel.tsx`,
`desktop/src/i18n/locales/{en,tr}.json`,
`desktop/src/components/SettingsPanel.test.tsx`.

<details><summary>original</summary>
`stop_daemon` only kills the process the app itself spawned and
returns `Ok(false)` otherwise (`commands.rs:671-681`);
`SettingsPanel.tsx:125-142` ignores the boolean. Show an i18n'd notice
("daemon is managed externally — use systemctl --user stop
connectibled") when `false` comes back.
*Files:* `desktop/src/components/SettingsPanel.tsx`,
`desktop/src/i18n/locales/{en,tr}.json`.
*Acceptance:* vitest — mocked `stopDaemon -> false` renders the
notice; `true` does not.
</details>

### T-X12: Persist clipboard-sync and remote-input toggles across daemon restarts `[x]`
**Done.** New plain-text `ui_toggles` file in the daemon data dir
(same pattern as the `download_dir` override, no JSON dep for two
booleans): `config::{UiToggles, load_ui_toggles, write_ui_toggles}`.
`lib.rs` loads it at startup and seeds both gates (the clipboard
atomic and `InputDispatcher::set_enabled`); missing/corrupt file ->
both default on. Both `Set*Enabled` RPC handlers call a new
`persist_ui_toggles()` (writes BOTH current states, so the file is
always self-consistent regardless of which toggle changed);
best-effort, a write failure is logged not surfaced. Tests: 3 config
unit tests (defaults-when-absent, round-trip, missing-key-keeps-
default) + a service integration test
`clipboard_sync_toggle_persists_across_a_restart` (toggle off via RPC
in an isolated tempdir, rebuild the service seeded from
`load_ui_toggles` as lib.rs does, GetLocalState still reports off).
Remote-input follows the identical path (same `persist_ui_toggles` +
startup seed); its RPC needs an input backend the fixture doesn't wire,
so it's covered by the shared mechanism rather than its own e2e.
*Files:* `daemon/src/config.rs`, `daemon/src/lib.rs`,
`daemon/src/grpc/service.rs`.

<details><summary>original</summary>
Both flags reset to defaults on every daemon start
(`daemon/src/lib.rs:100`, `daemon/src/input/mod.rs:55`) — a user who
disabled clipboard sync finds it silently re-enabled after a reboot (a
privacy-expectation break). Persist both in the daemon's data dir
(reuse the existing small-override-file pattern the download-dir
override uses; a JSON `ui-toggles` file is fine) — load at startup,
write on each `Set*Enabled` RPC.
*Files:* `daemon/src/lib.rs`, `daemon/src/grpc/service.rs`, a small
new `daemon/src/` helper or `config.rs` addition.
*Acceptance:* unit test on the load/save helper + integration test:
set a toggle off via RPC, rebuild the service against the same data
dir, `GetLocalState` reports it still off.
</details>

### T-X13: Doctor panel renders localized check content `[x]`
**Done, with a re-verification correction.** The finding assumed 44
ready-to-wire keys; in reality the existing `doctor.checks.*` keys were
written for an OLDER check set (camelCase names like `daemonProcess`,
`mdnsDiscovery`) that no longer matches the daemon's current kebab-case
ids (`daemon-version`, `disk-space`, `db-encryption-key-source`, ...).
So naive wiring would have mis-titled or blanked checks. Instead:
badges now come from i18n (`doctor.statusSuccess/Warning/Error`, was
hardcoded OK/WARN/FAIL); titles come from a fresh, accurate
`CHECK_TITLE_KEY` map keyed by the daemon's ACTUAL ids with new correct
en+tr keys, falling back to the daemon-provided English title for any
unknown/new id. Summaries + remediation stay daemon-provided: they are
dynamic (embed counts, RTTs, error text) and can't be localized
client-side without the daemon emitting structured message ids -- **new
follow-up appended below as T-X43.** The stale camelCase check keys are
now orphaned and flagged for T-X29's prune. vitest: TR locale renders
translated titles for known ids, falls back for an unknown id, badges
localized.
*Files:* `desktop/src/components/ConnectionDoctorPanel.tsx`,
`desktop/src/i18n/locales/{en,tr}.json`,
`desktop/src/components/ConnectionDoctorPanel.test.tsx`.

<details><summary>original</summary>
44 translated `doctor.checks.*`/`doctor.messages.*`/`doctor.status*`
keys exist in both locales (`en/tr.json:198-253`) but no code
references them; the panel prints the daemon's English
title/summary/remediation verbatim
(`ConnectionDoctorPanel.tsx:166-170`) and hardcodes "OK/WARN/FAIL"
badges (`:189-190`). Map check ids to the existing keys client-side
with fallback to the daemon-provided English (unknown/new checks must
still render), and use the status keys for badges.
*Files:* `desktop/src/components/ConnectionDoctorPanel.tsx`.
*Acceptance:* vitest — TR locale renders translated titles for known
check ids, falls back gracefully for an unknown id; badge labels come
from i18n.
</details>

### T-X14: Tray menu localized and state-synced `[x]`
**Done.** Tray menu item handles are now kept in a managed
`TrayHandles` struct; a new loopback-free `update_tray` command
(`commands.rs`) relabels all four items and re-checks the
clipboard-sync box. The frontend calls it from an `App.tsx` effect keyed
on `[locale, daemon.clipboardSyncEnabled]`, so the tray follows a
language switch and a clipboard-sync change made from ANY surface
(Settings, daemon, the tray's own toggle) -- fixing both the frozen-
English labels and the stale checkbox. New `tray.{show,hide,
syncClipboard,quit}` keys (en+tr); `updateTray` ipc wrapper. `cargo
check` (src-tauri) + tsc + vitest (124) all clean. **On-device manual
check flagged for the owner** (no clickable tray in this sandbox):
switch language -> tray labels change; toggle clipboard sync in
Settings -> tray checkbox follows. UI-automation of the tray is out of
scope per the task.
*Files:* `desktop/src-tauri/src/tray.rs`,
`desktop/src-tauri/src/commands.rs`, `desktop/src-tauri/src/lib.rs`,
`desktop/src/App.tsx`, `desktop/src/lib/ipc.ts`,
`desktop/src/i18n/locales/{en,tr}.json`.

<details><summary>original</summary>
Tray labels are hardcoded English (`tray.rs:21-34`) and never change
with locale; the "Sync Clipboard" checkbox is only updated inside its
own toggle handler, so a change made from Settings leaves the tray
checkbox wrong indefinitely. Fix: a `update_tray` command the frontend
calls with localized labels + current checked state (on mount, on
locale change, and whenever the toggle changes from any surface).
*Files:* `desktop/src-tauri/src/tray.rs`,
`desktop/src-tauri/src/commands.rs` (new command + registration),
`desktop/src/` caller (App or useDaemon), locales.
*Acceptance:* manual check documented in Done note (tray text follows
language switch; checkbox follows a Settings-made change) + `cargo
check`/vitest clean. UI-automation of the tray is not expected.
</details>

### T-X15: Relative timestamps localized `[x]`
**Done.** `formatRelativeTime(epochMs, locale, nowMs?)` now uses
`Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "short" })`
-- `numeric: "auto"` renders the sub-5s case as the locale's own "now"
wording for free (no extra key). The 4 call sites
(Home/DeviceList/Clipboard/Notifications panels) thread the active
locale via `useI18n()` (HomePanel's `PairedRow` gets its own hook so
memo doesn't stop a locale change from re-rendering it). Test rewritten
to compute expected strings from Intl directly (ICU-version
independent) and assert tr differs from en.
*Files:* `desktop/src/lib/format.ts`, the 4 panels,
`desktop/src/lib/format.test.ts`.

<details><summary>original</summary>
`formatRelativeTime` is hardcoded English ("just now", "5s ago", ...)
(`desktop/src/lib/format.ts:22-33`) and is rendered by
HomePanel/DeviceListPanel/ClipboardPanel/NotificationsPanel. Use
`Intl.RelativeTimeFormat` with the active i18n locale (plus an i18n
key for the "just now" special case if needed).
*Files:* `desktop/src/lib/format.ts` + call sites for locale
threading, `format.test.ts`.
*Acceptance:* format tests cover en + tr outputs.
</details>

### T-X16: Transfer history rows show peer + time, sort chronologically, and restore "canceled" correctly `[x]`
Three audit findings in one surface (`TransferPanel.tsx`):
(a) persisted `peerDeviceId`/`finishedAtMs` are dropped by
`historyEntryToProgress` (`:393-405`) and never rendered — history
cannot answer "to whom, when";
(b) rows sort by `transferId` hash (`:171`) with persisted rows
appended (`:182`) — not chronological;
(c) a restored `canceled` entry maps to `completed:false,
failed:false`, i.e. looks ACTIVE: shimmer bar + a working Cancel
button appear on it (`:399-401` vs `:317`, `:357`, `:374`). Live
cancel events set `failed:true, canceled:true`
(`core/src/remote.rs:361-364`) — mirror that mapping. Render peer
name (resolve device_id via the devices list, fall back to a
shortened id) and finished time (T-X15's formatter); stamp a
client-side finished time on live terminal events so the merged list
sorts by it desc. Mobile has the same peer/time gap — that half is
T-X24.
*Files:* `desktop/src/components/TransferPanel.tsx`,
`desktop/src/hooks/useDaemon.ts` (terminal-time stamp), locales,
`TransferPanel.test.tsx`.
*Acceptance:* vitest — restored canceled row shows Canceled with no
cancel button and no shimmer; history ordered by finish time; peer
name + time visible on persisted rows.

**Done.** `TransferProgress` gained two optional client-only display
fields (`finishedAtMs`, `peerDeviceId`). useDaemon stamps `finishedAtMs
= Date.now()` the first time a transfer reaches a terminal state (both
the incoming LocalEvent path and the outgoing Tauri-event path).
`historyEntryToProgress` now (a) carries `peerDeviceId`/`finishedAtMs`
through and (b) maps `canceled` -> `failed:true, canceled:true`
(mirroring a live cancel), so a restored canceled row is terminal --
no shimmer, no Cancel button. History is sorted by `finishedAtMs` desc.
`TransferRow` renders a "peer - time" meta line, resolving the peer id
against the (now-used again) `devices` prop with a shortened-id
fallback. **Note: this revives the `devices` prop, so T-X28's "remove
dead devices prop" no longer applies -- flagged there.** 4 new vitest
cases (restored-canceled terminal; peer name + shortened-id fallback;
chronological order). All 13 TransferPanel tests green.
*Files:* `desktop/src/components/TransferPanel.tsx`,
`desktop/src/hooks/useDaemon.ts`, `desktop/src/lib/types.ts`,
`desktop/src/components/TransferPanel.test.tsx`.

### T-X17: `refresh()` must not let a later success clear an earlier failure `[x]`
**Done.** `refresh()` no longer calls `setLoadError(null)` per-branch;
it computes the error once after both fetches -- state's error wins if
both fail, cleared only when both succeed. `setDevicesLoaded(true)`
moved out to always run. Test: state-fails/devices-succeeds leaves
`loadError` set.
*Files:* `desktop/src/hooks/useDaemon.ts`,
`desktop/src/hooks/useDaemon.test.ts`.

<details><summary>original</summary>
In `useDaemon.ts:70-92` a failed `getLocalState` sets `loadError`, but
an immediately-following successful `listDevices` calls
`setLoadError(null)`, masking the partial failure — clipboard/
notification panels then look "genuinely empty" instead of failed.
Track both results; set `loadError` once from whichever failed.
*Files:* `desktop/src/hooks/useDaemon.ts`, `useDaemon.test.ts`.
*Acceptance:* test — state-fails/devices-succeeds leaves `loadError`
set.
</details>

### T-X18: Phase X3 verification `[x]`
**Done, all green:**
- `cargo test --workspace` -- daemon lib 103 (+4 from T-X12), grpc_smoke
  6, process_shutdown 1, upload_transfer 8, desktop-core lib 7,
  desktop_core_e2e 6; 0 failed.
- `cargo clippy --workspace --all-targets -- -D warnings` -- clean;
  src-tauri (workspace-excluded) clippy -- also clean.
- `npx tsc --noEmit -p .` (desktop) -- clean.
- `npx vitest run` (desktop) -- 16 files, 124 tests (+10 from
  T-X11/X13/X16), 0 failed.

**Phase X3 status: complete.** T-X11 through T-X18 all done. Two
re-verification corrections were surfaced and documented rather than
forced: T-X13's stale doctor keys (new follow-up T-X43 for structured
summary localization) and T-X16 reviving the `devices` prop (flagged
against T-X28). On-device manual check flagged for T-X14 (tray).

### T-X43: Doctor summary/remediation localization (follow-up from T-X13) `[ ]`
Discovered during T-X13: the daemon emits check `summary`/`remediation`
as already-formatted English strings embedding dynamic data (counts,
RTTs, error text), so the client cannot localize them without the
daemon instead emitting a stable message-id + a `data` param map the
client formats against localized templates (the `doctor.messages.*`
keys were written for exactly this but are unusable as-is). Titles and
badges are localized (T-X13); this closes the remaining half.
*Files:* `daemon/src/diagnostics/*.rs` (emit message-id + data),
`proto/connectible.proto` (if the DiagnosticCheck shape needs a
message-id field), `desktop/src/components/ConnectionDoctorPanel.tsx`.
*Acceptance:* a check's summary renders in Turkish for a known
message-id, falling back to daemon English for an unknown one.

---

## Phase X4 — Mobile medium

### T-X19: Surface pairing/connection errors on Home `[x]`
**Done (2026-07-22):** Re-verified -- `lastError`'s only consumer was still
`pair_scan_screen.dart`; tapping a nearby device, "connect by address", and
the reconnect fingerprint-changed warning all failed silently on Home. Added
a structured error to `PairingModel` (`PairingErrorKind {generic,
fingerprintChanged}` + `lastErrorKind` + a monotonic `lastErrorSeq`, all set
via a new `_setError` helper that the five failure sites now call). Home
(`home_screen.dart`) attaches a listener in its post-frame init and, on a
fresh `lastErrorSeq`, shows a snackbar -- the fingerprint case uses the new
i18n key `home.fingerprintChanged` (en+tr), everything else surfaces the
model's message; guarded by `ModalRoute.isCurrent` so a pushed pairing/scan
screen (which shows its own error) doesn't double up. The model keeps an
English fallback string for the fingerprint case (no BuildContext/i18n in the
model layer) -- the user-visible copy is now the translated one. Files:
`mobile/lib/src/state/pairing_model.dart`,
`mobile/lib/src/screens/home_screen.dart`,
`mobile/lib/src/i18n/strings.dart`. Tests: two new `home_screen_test.dart`
widget cases (a generic failure surfaces its message; the fingerprint case
shows the dedicated localized string, not the raw fallback) -- the whole file
is green (8/8). Note: the widget tests drive the failure through an
`_ErrorPairing` seam rather than a real dial, because `testWidgets` fakes
timers and a live gRPC connect hangs on its internal timeout timers; that a
genuine failed connect sets `lastError` is already covered by
`pairing_model_test.dart`.
`PairingModel.lastError`'s only UI consumer is
`pair_scan_screen.dart:170`. Tapping a nearby device
(`home_screen.dart:93-113`), "connect by address"
(`home_screen.dart:81-91`), and the reconnect fingerprint-changed
warning (`pairing_model.dart:514-522`) all fail with zero user
feedback — including the security warning. Show a snackbar (or
equivalent) on Home when `lastError` transitions non-null, with the
fingerprint-changed case using its own clear i18n string.
*Files:* `mobile/lib/src/screens/home_screen.dart`,
`mobile/lib/src/i18n/strings.dart`.
*Acceptance:* widget test — a failing connect surfaces the message;
fingerprint-change path shows the dedicated string.

### T-X20: Acquire an Android multicast lock while discovering `[x]`
**Done** (implementation by the X4 sub-agent before it hit a session
limit mid-task; finished + tested by the main session). New
`MulticastLockPlugin.kt` (channel `connectible/multicast`, idempotent
non-reference-counted `WifiManager.MulticastLock`, registered in
`MainActivity`); `MdnsService` gained `acquire/releaseMulticastLock()`
(idempotent via a `_multicastLockHeld` flag, no-op off Android or when
the native side is absent, swallows failures so a lock error never
breaks discovery); `DeviceListModel.startDiscovery` acquires and
`stopDiscovery` releases (and `MdnsService.dispose` releases on
teardown). New `test/services/mdns_multicast_lock_test.dart`: mocked
channel, verifies one native acquire/release each with idempotence, a
release-without-acquire no-op, and that a native acquire failure is
swallowed. `flutter analyze` clean. **On-device verification flagged
for the owner**: the real `WifiManager` lock (and whether it fixes
field discovery) can only be confirmed on a physical Android device --
no emulator in this sandbox.
*Files:* `mobile/android/.../net/MulticastLockPlugin.kt` (new),
`mobile/android/.../MainActivity.kt`,
`mobile/lib/src/services/mdns_service.dart`,
`mobile/lib/src/state/device_list_model.dart`,
`mobile/test/services/mdns_multicast_lock_test.dart` (new).

<details><summary>original</summary>
The manifest declares `CHANGE_WIFI_MULTICAST_STATE` and even comments
that discovery needs a multicast lock (`AndroidManifest.xml:5-7`), but
nothing in the repo acquires one (`multicast_dns` is pure Dart and
cannot); most real devices filter multicast without it, so discovery
can silently return nothing in the field. Add a tiny platform channel
(MainActivity or a small plugin) exposing acquire/release of
`WifiManager.MulticastLock`; `MdnsService` acquires on discovery
start/sweep and releases on stop; no-op off Android.
*Files:* `mobile/android/app/src/main/kotlin/.../MainActivity.kt` (or
new plugin file), `mobile/lib/src/services/mdns_service.dart`.
*Acceptance:* `flutter analyze` clean; Dart side unit-tested with a
mocked channel; real-device verification explicitly flagged for the
owner in the Done note (no phone in this sandbox).
</details>

### T-X21: Pause mDNS sweeps while the app is backgrounded `[x]`
**Done.** `DeviceListModel` now mixes in `WidgetsBindingObserver`
(registered in the constructor, removed in `dispose`), mirroring
`ClipboardModel`'s own lifecycle-pause pattern. New `_discoveryActive`
flag tracks "discovery has been started and not yet explicitly
stopped" independent of the timer itself, so `didChangeAppLifecycleState`
is a no-op unless discovery is actually active (a background/
foreground transition before pairing, or on a screen that never called
`startDiscovery`, must not spin it up). On non-`resumed` states: cancel
the sweep timer and release T-X20's multicast lock. On `resumed`:
reacquire the lock, restart the timer, and sweep immediately (catch-up
for whatever appeared while backgrounded). New `@visibleForTesting bool
get isSweepTimerActiveForTest` (mirrors `ClipboardEchoGuard`'s existing
test-seam pattern — `Timer` exposes no queryable "is this the current
generation" state from outside). 3 new tests: pause stops the timer +
resume restarts it; a lifecycle change before `startDiscovery` is a
no-op; a lifecycle change after an explicit `stopDiscovery` is also a
no-op (doesn't resurrect a deliberately-stopped discovery). All 9
`device_list_model_test.dart` tests green; `flutter analyze` clean.
*Files:* `mobile/lib/src/state/device_list_model.dart`,
`mobile/test/device_list_model_test.dart`.

<details><summary>original</summary>
`startDiscovery` runs a 4s multicast sweep every 5s
(`device_list_model.dart:255-267`) and only stops on `dispose`
(`:372-377`). `ClipboardModel` already has the lifecycle-pause pattern
(`clipboard_model.dart:131-138`) — apply the same observer to pause
sweeps (and release T-X20's lock) in background, resume on foreground.
*Files:* `mobile/lib/src/state/device_list_model.dart` (+ wherever the
lifecycle observer is wired).
*Acceptance:* test — simulated lifecycle pause stops the timer,
resume restarts it.
</details>

### T-X22: Cap distinct pending device_ids in mobile PairingManager `[x]`
**Done.** New `PairingManager.maxTrackedDevices = 256` (mirrors the
daemon's `MAX_TRACKED_DEVICES` exactly, same value and same doc
reasoning). `createPending`'s cooldown check gained an `else if`
branch: a brand-new device_id (`lastMs == null`) past the cap throws
`RateLimitedException('too many distinct devices are mid-pairing right
now')` -- the exact daemon message, for consistency. An already-tracked
id is never blocked (unchanged branch above handles it). New test
"distinct device flood is capped, but already-tracked devices still
work (T-X22)" ported directly from the daemon's
`distinct_device_flood_is_capped_but_known_devices_still_work`: floods
`maxTrackedDevices` distinct ids (all succeed), one more distinct id is
rejected, but the first flooded id (still tracked) succeeds again.
11/11 `pairing_manager_test.dart` tests green; `flutter analyze` clean.
*Files:* `mobile/lib/src/services/pairing_manager.dart`,
`mobile/test/pairing_manager_test.dart`.

<details><summary>original</summary>
`_pending`/`_lastCreatedMs` grow unbounded and cooldown is per-device
(`services/pairing_manager.dart:64-65, 91-95`) — a LAN peer minting a
fresh fake device_id per request can bloat the maps and keep the
responder PIN sheet busy forever. The daemon's equivalent is
explicitly capped (`daemon/src/pairing/mod.rs:22`); mirror that cap +
pruning behavior.
*Files:* `mobile/lib/src/services/pairing_manager.dart`, its test.
*Acceptance:* test — flooding N+1 distinct ids keeps memory bounded
and known devices still pairable (mirror the daemon's test).
</details>

### T-X23: `handleUploadFile` cleans up on stream error; tickets capped `[ ]`
No try/finally around the `await for` (`file_transfer_model.dart:
441-491`): a TCP reset mid-stream leaks the open `raf`/`hashInput` and
leaves the transfers row stuck "Receiving" forever (no terminal
emission). Wrap the loop; on error, close resources, emit a failed
terminal state (+ history record), rethrow the GrpcError. Also cap
`_uploadTickets` (`:382, 400-408`) like the daemon's `MAX_TICKETS`
(decline offers when full) so a paired peer can't grow it unboundedly.
*Files:* `mobile/lib/src/state/file_transfer_model.dart`, tests.
*Acceptance:* test — a stream that errors mid-transfer yields a
failed row (not stuck Receiving) and later uploads still work; a
tickets-full prepare gets `accepted:false`.

### T-X24: Mobile history shows peer + time; inbound peer id recorded `[ ]`
Mobile half of T-X16: `_TransferTile` renders only
name/status/bytes (`transfers_screen.dart:295-303`);
`peerDeviceId`/`finishedAtMs` are persisted but unused — and for
inbound pushes `peerDeviceId` is saved as `''` because `activePeerId`
is null on an inbound-only session (`file_transfer_model.dart:106`,
`pairing_model.dart:116-117` — `_inboundPeerDeviceId` is never
reflected). Fix `activePeerId` to fall back to the inbound peer id,
then render peer name (resolve via DeviceListModel) + finished time on
history rows, sorted by finish time desc.
*Files:* `mobile/lib/src/state/pairing_model.dart`,
`mobile/lib/src/screens/transfers_screen.dart`,
`mobile/lib/src/i18n/strings.dart`, tests.
*Acceptance:* tests — inbound completion records the real peer id;
widget test shows peer + time on a history row.

### T-X25: Idle connection chip must not say "Connecting" `[ ]`
`_ConnChip` labels the idle state (not connected, no reconnect
pending) as `status.connecting` (`screens/shell.dart:276-280`) — a
fresh phone shows a permanent "Connecting". Add a proper idle label
(en+tr) and use it.
*Files:* `mobile/lib/src/screens/shell.dart`,
`mobile/lib/src/i18n/strings.dart`, shell test.
*Acceptance:* widget test — idle state renders the idle label.

### T-X26: Single-character device names must not crash Home `[ ]`
`home_screen.dart`'s local `monogram` copy does
`parts[0].substring(0, 2)` without a length check (`:1355-1361`) — any
mDNS peer advertising a 1-char name triggers a `RangeError` during
Home render (LAN-triggerable crash). A safe version already exists in
`ui.dart:5-15`; delete the local copy and use it.
*Files:* `mobile/lib/src/screens/home_screen.dart`.
*Acceptance:* widget test — a 1-char nearby device name renders.

### T-X27: Phase X4 verification `[ ]`
`flutter analyze` + full `flutter test` green.

---

## Phase X5 — Low severity / cleanup (both platforms)

### T-X28: Desktop dead code removal `[ ]`
All verified unreferenced: `ping_daemon`, `check_tcp_port`,
`check_tls_handshake` commands (+ their `ipc.ts` wrappers and
`core/src/local.rs:164` `tls_handshake_check`) — leftovers from the
pre-T-F8 frontend doctor; `TransferPanel`'s dead `devices` prop
(`TransferPanel.tsx:14` vs `:55`, plus `App.tsx:139` and test call
sites); orphan `LanguageSwitcher.tsx`; `secondsUntil` (+its test only
usage, `lib/format.ts:36`). Remove them.
*Files:* as listed + `desktop/src-tauri/src/lib.rs` registration.
*Acceptance:* tsc/vitest/cargo check clean; grep shows no references.

### T-X29: Desktop orphan i18n keys pruned `[ ]`
55 orphan keys per audit: the 44 `doctor.*` keys become USED by T-X13
— re-check first — then prune what is still orphaned
(`status.reconnecting`, `daemon.running`, `daemon.reconnect`,
`common.actions/connect/info/disconnect`, `menu.connect/info/refresh`,
`devices.fromPhoneHint`, and any doctor keys T-X13 genuinely left
unused). Both locales stay in exact key parity.
*Files:* `desktop/src/i18n/locales/{en,tr}.json`.
*Acceptance:* a parity check (script or test) passes; no key
referenced in code is missing.

### T-X30: Desktop small correctness/UX papercuts `[ ]`
(a) silent failures get feedback: `listTransferHistory` fetch fail
(`TransferPanel.tsx:79-87`), `getDownloadDir` fail leaving eternal
"Loading..." (`SettingsPanel.tsx:56-58`), `rerunOne` fail freezing the
spinner (`ConnectionDoctorPanel.tsx:58-70`);
(b) `PairingQrDialog` doc comment claims auto-renew that does not
exist (`:34-36` vs `:154-163`) — fix the comment to match behavior;
(c) canceled transfers styled as danger/"failed" — neutral styling for
canceled (icon + tie fill), keep danger for real failures
(`TransferPanel.tsx:302, :359`, given `remote.rs:363` sets
failed+canceled);
(d) `rttMs === 0` hidden by falsy check (`SettingsPanel.tsx:239`) —
use an explicit null/undefined check;
(e) `APP_VERSION` hand-written "0.1.0" (`App.tsx:22`) — import from
`package.json` so version bumps propagate.
*Files:* as listed, locales for (a).
*Acceptance:* vitest for (a)/(c)/(d); tsc clean for (e).

### T-X31: Mobile dead/broken platform code removal `[ ]`
(a) `services/crc32.dart` + `test/crc32_test.dart` — orphaned by
Phase I (only reference each other);
(b) `NotificationPlugin.kt`'s `requestRebind`/`requestUnbind`
(`:74-102, 130-146`) — never invoked from Dart, and the `requestUnbind`
reflection targets a non-existent static method (real API is a
parameterless instance method; the `TIRAMISU` gate is wrong too, API
24). Remove both dead methods.
*Files:* as listed.
*Acceptance:* `flutter analyze` clean; grep shows no references;
notification permission flow (isGranted/openSettings) untouched and
its tests green.

### T-X32: Mobile i18n sweep `[ ]`
(a) Hardcoded user-visible strings to i18n (en+tr): 'Pairing was
rejected' (`pairing_model.dart:327`), the fingerprint-changed message
(`pairing_model.dart:516-517`) (T-X19 may have landed this — verify),
'Me' (`home_screen.dart:415`), 'Unknown device' x3
(`connectible_server.dart:145`, `device_list_model.dart:126`,
`mdns_service.dart:124`), clipboard source label rendering raw
`entry.source` (`clipboard_screen.dart:102-105`);
(b) prune the 7 orphan keys (`clipboard.title`, `common.cancel`,
`common.close`, `common.pairing`, `nav.devices`, `settings.subtitle`,
`transfers.title`) — re-verify each is still orphaned first;
(c) Doctor check texts (`services/doctor/checks.dart`) are English by
design parity with the daemon — leave them, but note it in the Done
note as a known, deliberate mixed-language surface (matches T-X13's
desktop treatment if you want parity later).
*Files:* `mobile/lib/src/i18n/strings.dart` + listed call sites.
*Acceptance:* analyze clean; existing widget tests updated where
strings changed; TR/EN parity intact.

### T-X33: Mobile small papercuts `[ ]`
(a) `ERROR_CODE_FINGERPRINT_CHANGED` missing from
`ConnectibleException.forCode` (`services/connectible_exception.dart:
29-56`) — map it with a user-actionable "re-pair" message (i18n);
(b) stop advertising the `remote_input` capability until the phone can
actually be controlled (`device_list_model.dart:76-83` vs frames
silently dropped `pairing_model.dart:416-429`);
(c) centralize the hand-written '0.1.0' version strings
(`settings_screen.dart:128`, `device_list_model.dart:69`) into one
const;
(d) `openAccessSettings()` false return ignored — implement the
documented general-settings fallback (`settings_screen.dart:451`,
`checks.dart:233` vs `notification_listener.dart:67-70`);
(e) surface `lastDiscoveryError` somewhere visible on Home
(`device_list_model.dart:51`);
(f) history rows for failed transfers draw a 100%-full bar
(`transfers_screen.dart:168-179`) — map failed non-canceled restored
rows to 0 progress (desktop half too if it shares the artifact);
(g) stale comments contradicting reality: `home_screen.dart:1004-1009`
("notifications forwarding isn't implemented on mobile at all",
"doctor is desktop-only" — both false now) and
`ConnectibleNotificationListener.kt:57-61` (references a nonexistent
foreground service — reword or tie to T-X36's outcome).
*Files:* as listed.
*Acceptance:* analyze + targeted tests green; each sub-item checked
off in the Done note.

### T-X34: Stale sub-README content `[ ]`
`desktop/README.md:4` still says "cool-toned (blue) accent" (the UI is
monochrome now) and `mobile/README.md` still describes the removed
"radar home screen". Update both to match current reality (plain
device list, monochrome).
*Files:* `desktop/README.md`, `mobile/README.md`.
*Acceptance:* no stale claims remain in either file.

### T-X35: Phase X5 verification `[ ]`
All six commands green (both platforms + workspace).

---

## Phase X6 — Decision-gated items (STOP: owner input required)

Present each with options + recommendation, then wait. Do not start
implementation without an explicit go-ahead.

### T-X36: Foreground service for the receiving/discoverable role `[ ]`
Audit finding: no foreground service exists (manifest has only the
notification listener, `AndroidManifest.xml:37-45`), so the inbound
server + mDNS advertise + heartbeat die silently under Doze/OEM kills;
Doctor's `BatteryOptimizationCheck` (`services/doctor/checks.dart:
266-286`) can only advise. Options: (a) proper foreground service with
persistent notification while "receiving enabled" (the KDE
Connect-parity answer, visible notification tradeoff), (b) keep
current behavior but document it honestly in-app (toggle subtitle) and
in docs, (c) defer to main roadmap as its own phase. Recommendation:
(a), scoped to the existing Home receiving toggle.
*Acceptance:* decision recorded here; implementation (if any) gets its
own task list appended to this phase.

### T-X37: Fate of the desktop-controls-phone dead code `[ ]`
`RemoteDeviceClient::open_input_session` + `InputSession`
(`core/src/remote.rs:389-463`) is complete, tested-by-nothing,
UI-less dead code (the "desktop drives the phone" direction). Options:
(a) delete now (git history preserves it; revive when the feature is
scheduled), (b) keep as-is with a doc comment marking it dormant.
Recommendation: (a) — dead paths rot.
*Acceptance:* decision recorded; corresponding removal or comment
task executed.

### T-X38: Publish scope of docs/ on GitHub Pages `[ ]`
The 2026-07-22 docs reorg moved archives + design notes under `docs/`,
and `.github/workflows/pages.yml` publishes ALL of `docs/` — internal
audit reports (e.g. `docs/archive/EKSIKLER-RAPOR.md`) are now part of
the public site if Pages is enabled. Options: (a) fine, leave it, (b)
exclude `docs/archive/` (and optionally `docs/design/`) from the
deployed artifact in the workflow. Recommendation: (b) for archive at
minimum.
*Acceptance:* decision recorded; workflow updated if (b).

### T-X39: Phone-side QR pairing parity `[ ]`
Mobile's `preArmPairingCode` is deliberately `unimplemented`
(`connectible_server.dart:279-291`) — the phone can scan a desktop QR
but cannot DISPLAY one for the desktop to scan. Options: (a) leave as
documented asymmetry (desktop has a screen+webcam story anyway), (b)
add a phone-shows-QR flow (needs a pre-arm concept in mobile
PairingManager). Recommendation: (a) for now; revisit post-v1.0.
*Acceptance:* decision recorded.

---

## Phase X7 — Campaign close-out

### T-X40: Full regression pass `[ ]`
All six commands, all green, run fresh at the end regardless of
per-phase runs: `cargo test --workspace`, `cargo clippy --workspace
--all-targets -- -D warnings`, `npx tsc --noEmit -p .`, `npx vitest
run`, `flutter analyze`, `flutter test`.
*Acceptance:* verbatim pass counts recorded in the Done note.

### T-X41: Documentation sync `[ ]`
Update whatever this campaign made stale: `docs/api-reference.md` (if
RPC/UI behavior descriptions changed), root `README.md` known-
limitations (e.g. if T-X36 landed a foreground service or T-X20 fixed
field discovery reliability), and add a CHANGELOG entry summarizing
the campaign. Keep English/ASCII, keep tone.
*Acceptance:* docs match shipped behavior; no new stale claims.

### T-X42: Final report `[ ]`
Write a short summary at the top of this file (below the header):
what shipped, what was decision-deferred, verbatim final test counts,
and any findings discovered mid-campaign that were NOT in the original
audits (append them to the relevant phase as new tasks or list them
for a future pass). Report to the owner in Turkish.
*Acceptance:* summary present; owner informed.
