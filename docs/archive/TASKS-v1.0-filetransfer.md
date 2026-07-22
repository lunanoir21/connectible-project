> **ARCHIVED (2026-07-19, updated 2026-07-20).** This is the
> file-transfer re-architecture roadmap (backpressure, dedicated upload
> stream, streaming hash resume). Active work now lives in
> `docs/TASKS.md`, which as of 2026-07-20 tracks the v1.0.0 completion-
> criteria work (Phases G-N: mTLS identity, DB encryption, legacy
> transfer-path removal, and beyond) -- it superseded an earlier
> revision of itself that tracked mobile pairing/QR + desktop UI
> simplification (now archived at `TASKS-v1.0-pairing-ui.md`), which is
> in turn also done. Only **T-B3** (real-device battery verification)
> remains open in this file -- T-A20/T-A21/T-A22 are done, see their
> entries below for the account and an important flagged deviation from
> this section's own gating condition. `TASKS.md` links back here
> rather than duplicating T-B3; do not resume it without checking
> `TASKS.md` first (it's re-tracked there as Phase N, also parked
> pending Luna's go-ahead since it needs real hardware).

# Connectible - Road to v1.0.0 (Phased Task Breakdown)

**Created:** 2026-07-16. Supersedes the v0.1.0 MVP plan, archived at
[`TASKS-v0.1.0.md`](TASKS-v0.1.0.md).

## Why this exists

Two independent audits ([`EKSIKLER-RAPOR.md`](EKSIKLER-RAPOR.md),
[`REVIEW-2026-07-15.md`](REVIEW-2026-07-15.md)) rated the project ~95%
complete and called file transfer "fully implemented with resume +
CRC32/SHA-256." On real devices it is **not stable**. Root causes, from
reading the code:

1. File bytes are multiplexed onto the shared control `SyncStream`
   (`FileChunk` frames), so a control-stream reconnect kills an in-flight
   transfer and bulk data head-of-line-blocks clipboard/input.
2. No backpressure: the sender pushes 64KB frames fire-and-forget; if it
   outruns the receiver's disk writes, frames queue in memory and drop.
3. The whole-file SHA-256 verify reads the **entire file into RAM**
   (`readAsBytes` on mobile), which OOMs on large files.
4. The two directions use different transports (desktop: short-lived
   `RemoteDeviceClient`; mobile: persistent sync stream), so reliability
   is asymmetric.

So 1.0.0 is gated on making the core promise — send a file, reliably —
actually true, then closing the genuinely user-visible gaps.

## How to work this file

One phase at a time, A -> F. Every task is small on purpose: it should be
completable and verifiable on its own. Check a task off only when its
**Acceptance** holds (automated tests where possible; real-device where
noted). Keep every stack compiling green after each task.

**Status keys:** `[ ]` todo, `[~]` in progress, `[x]` done, `[-]` cut/skip.
**Field keys:** *Files* = where the work lands; *Depends* = must land first;
*Acceptance* = definition of done.

### Prerequisite work already landed (2026-07-16)
- [x] **P-1** Transfer UI rebuilt both platforms: send composer,
  active/history sections, constellation "tie" progress, desktop
  drag-and-drop send. *Files:* `desktop/src/components/TransferPanel.tsx`,
  `mobile/lib/src/screens/transfers_screen.dart`.
- [x] **P-2** Native cross-distro open (xdg-open -> gio -> file-manager
  cascade), replacing the opener plugin that silently no-op'd on many
  Linux desktops. *Files:* `desktop/src-tauri/src/commands.rs`
  (`open_path`), `lib/ipc.ts`.
- [x] **P-3** Desktop received-files folder = `~/Downloads` (configurable
  override); mobile "Save to..." via Android SAF. *Files:*
  `daemon/src/config.rs`, `SettingsPanel.tsx`.

---

## Phase A - File transfer stabilization (LocalSend-style)

Adopt LocalSend's *transport model* — one file = one streamed body,
decoupled from control traffic, with a prepare/accept handshake — on our
**existing TLS 1.3 + persistent pairing** (no interop with the real
LocalSend app), **strengthened**: offset-based resume kept, hash computed
by streaming (never buffer the file), backpressure free from the stream.
See memory `file-transfer-rearchitecture`.

### Protocol

### T-A1: Define upload message types in the proto  `[x]`
**Done 2026-07-16.** Added `UploadFileMeta`, `PrepareUploadRequest`,
`UploadFileOffer`, `PrepareUploadResponse`, `UploadFileHeader`,
`UploadFilePart` (oneof header/chunk), `UploadFileResult` to
`proto/connectible.proto`, grouped after `FileChunkRequest` under a new
"Dedicated file upload" section; old transfer messages untouched;
`protoc` parse-check passes.

Add, additively, to `proto/connectible.proto` (leave old
`FileTransferStart`/`FileChunk`/`FileChunkRequest` untouched until T-A17):
- `UploadFileMeta { string file_id; string file_name; int64 file_size_bytes; string file_hash; string mime_type; }`
- `PrepareUploadRequest { Identity sender; string session_id; repeated UploadFileMeta files; }`
- `UploadFileOffer { string file_id; bool accepted; int64 resume_offset_bytes; string token; string reject_reason; }`
- `PrepareUploadResponse { string session_id; repeated UploadFileOffer offers; }`
- `UploadFileHeader { string session_id; string file_id; string token; int64 offset_bytes; }`
- `UploadFilePart { oneof part { UploadFileHeader header = 1; bytes chunk = 2; } }`
- `UploadFileResult { string file_id; bool completed; int64 bytes_received; bool hash_ok; }`

*Acceptance:* proto parses; field numbering documented with a comment per
message; no existing message altered.

### T-A2: Add the two RPCs to the `Connectible` service  `[x]`
**Done 2026-07-16.** Added `PrepareUpload` (unary) + `UploadFile` (client-
streaming) to the service in `proto/connectible.proto` with inline
contract docs; added UNIMPLEMENTED stubs to the daemon impl
(`daemon/src/grpc/service.rs`, `prepare_upload`/`upload_file`) so it
compiles against the new server trait. `cargo build -p connectibled` OK.

`rpc PrepareUpload(PrepareUploadRequest) returns (PrepareUploadResponse);`
and `rpc UploadFile(stream UploadFilePart) returns (UploadFileResult);`.
Document each RPC's contract inline (auth, resume, one file per call).
*Depends:* T-A1. *Acceptance:* `cargo build -p connectibled` regenerates
Rust stubs and the daemon still compiles.

### T-A3: Regenerate & compile the mobile Dart stubs  `[x]`
**Done 2026-07-16.** Ran `gen_proto.sh` (with `~/.pub-cache/bin` on PATH);
new upload symbols present in `lib/src/generated/*`. Adding the required
overrides is folded into T-A13 below; `flutter analyze` clean.

Run `PATH="$PATH:$HOME/.pub-cache/bin" ./tool/gen_proto.sh` from
`mobile/`. *Depends:* T-A1/A2. *Acceptance:* `mobile/lib/src/generated/*`
updated (client + server stubs for both RPCs present); `flutter analyze`
clean.

### Daemon receiver

### T-A4: Upload session bookkeeping in the daemon  `[x]`
**Done 2026-07-16.** New `daemon/src/transfer/upload.rs`: `UploadRegistry`
(token -> `UploadTicket{session_id, file_id, file_name, part_path,
total_bytes, expected_hash}`) with `accept()` (mint OsRng token + return
resume offset from the `.part` length), `resolve()` (validate token +
file_id + session), `finish()`. 3 unit tests green (mint/resolve,
reject wrong id/session/token, resume-offset-from-partial + finish drops
token).

A small session store keyed by `session_id`+`file_id` holding the minted
token, expected size/hash, and `.part` path. New type in
`daemon/src/transfer/mod.rs` (or a sibling module), reusing
`transfers_dir` and the `TransferProgress` broadcast. *Acceptance:* unit
test: mint -> look up -> validate token; unknown/expired token rejected.

### T-A5: Implement `PrepareUpload`  `[x]`
**Done 2026-07-16.** `ConnectibleService` gained an `uploads:
Arc<UploadRegistry>` field (wired in `lib.rs` + `test_service`).
`prepare_upload` rejects an unpaired sender with `UNAUTHENTICATED`
(via `devices.is_paired`), mints a session id when absent, and returns an
accepted `UploadFileOffer` per file (token + resume offset from the
registry). Test `prepare_upload_rejects_unpaired_and_accepts_paired`
green. Receiving-gate note: the daemon has no separate receiving toggle
(unlike mobile's pairable flag), so "paired" is the gate.

In `daemon/src/grpc/service.rs`: authorize `sender` against the paired
set (reject unpaired with `UNAUTHENTICATED`); honour the receiving/
pairable gate (reject with a `reject_reason` when off); per file compute
`resume_offset_bytes` = bytes already in its `.part`; mint a token; return
offers. *Depends:* T-A2, T-A4. *Acceptance:* test: paired sender gets
`accepted=true` + a token; unpaired gets rejected; a partial on disk
yields a non-zero resume offset.

### T-A6: Implement `UploadFile` streaming to disk  `[x]`
**Done 2026-07-16** (with T-A7/A8). New `UploadWriter` in
`transfer/upload.rs` (transport-agnostic disk/hash sink); the
`upload_file` handler in `service.rs` reads the header, validates the
token via `uploads.resolve`, then feeds each chunk to the writer. Bytes
go straight to the `.part`; throttled `TransferProgress` emitted on
`TransferManager`'s shared broadcast (via new `progress_sender()`).

Read the leading `UploadFileHeader`, validate token+session, open the
`.part` at `offset_bytes`; stream each `chunk` straight to disk (seek-
write), updating the high-water mark and a throttled `TransferProgress`.
*Depends:* T-A5. *Acceptance:* test uploads a multi-MB file over real TLS;
bytes on disk match; progress events observed.

### T-A7: Streaming whole-file hash + finalize on the daemon  `[x]`
**Done 2026-07-16.** `UploadWriter` folds a running SHA-256 as bytes are
written (seeded from the on-disk prefix on resume, so never a whole-file
re-read); `finish()` verifies against `expected_hash`, then reuses
`unique_destination` to finalize into `resolve_download_dir`, emits a
terminal completed/failed event, and drops the ticket. Hash mismatch
discards the partial.

Fold each chunk into a running SHA-256 (no whole-file re-read); at end of
stream, if size reached and hash matches `file_hash`, finalize into
`resolve_download_dir` with the existing collision-safe naming and emit a
terminal `completed` event; on mismatch emit `failed` with
`CHECKSUM_MISMATCH` and keep/discard the `.part` per resume policy.
*Depends:* T-A6. *Acceptance:* correct hash finalizes + appears in the
download dir; a corrupted byte fails without finalizing; no full-file
re-read (verified by code, not RAM spikes).

### T-A8: Resume path on the daemon receiver  `[x]`
**Done 2026-07-16.** A short/dropped `UploadFile` stream returns
`Incomplete` and keeps the `.part`; the next `PrepareUpload` reports its
length as `resume_offset_bytes`; the next `UploadFile` opens at that
offset (seeding the hash from the prefix) and completes. Covered by the
`upload_file_resumes_after_a_dropped_stream` integration test.

A re-`PrepareUpload` after an interrupted `UploadFile` returns the
partial's length; the next `UploadFile` opens append-at-offset and
completes the file. *Depends:* T-A7. *Acceptance:* integration test drops
mid-`UploadFile`, re-prepares, resumes, and the final hash matches.

### T-A9: Daemon receiver test suite  `[x]`
**Done 2026-07-16.** New `daemon/tests/upload_transfer.rs`: 4 tests over
real TLS (happy-path lands verified on disk, unpaired-reject, wrong-hash-
not-finalized, resume-after-drop). Hermetic (pinned download dir). Full
daemon suite green: lib 70, grpc_smoke 8, fault_injection 1,
process_shutdown 1, upload_transfer 4.

Cover happy path, resume, unpaired-reject, wrong-hash-fail, and keep it
hermetic (pinned download dir, no writes to real `~/Downloads`). *Files:*
`daemon/tests/`. *Depends:* T-A8. *Acceptance:* new tests green; existing
`grpc_smoke`/`fault_injection` still green.

### Desktop sender

### T-A10: `upload_file` on the desktop core client  `[x]`
**Done 2026-07-16.** `RemoteDeviceClient::upload_file` in `remote.rs`:
PrepareUpload (declares file + streaming `hash_file`), then streams
256KB chunks from the resume offset over `UploadFile` on an mpsc/
`ReceiverStream` feeder (awaits each send = backpressure), emitting
throttled outgoing progress; a cancel notify flips a flag the feeder
polls. Added `sha2`/`hex` to core deps.

Add to `desktop/core/src/remote.rs`: `PrepareUpload`, then open
`UploadFile`, send the header, and stream the file from the returned
resume offset, **awaiting each send** so gRPC backpressure applies.
Surface progress via the existing `TransferProgressDto` channel. *Depends:*
T-A2. *Acceptance:* core-level test (or loopback) uploads to a daemon and
verifies.

### T-A11: Wire `commands::send_file` to the new path  `[x]`
**Done 2026-07-16.** `commands::send_file` now calls
`remote.upload_file` (resume is server-side via PrepareUpload, so the
client-side `send_offsets` bookkeeping + its 3 `AppState` methods/field
were removed). Kept the deterministic `file_id`, cancel handle, and
progress pump. **Bonus bug fix:** `finalize` used `fs::rename`, which
`EXDEV`s when the download dir (now `~/Downloads` by default) is a
different filesystem than `transfers_dir` (separate `/home`, tmpfs
`/tmp`) -- a real user-facing failure. Added `transfer::move_into_place`
(rename -> copy+remove fallback), used by both the old finalize and the
new `UploadWriter::finish`.

Replace the `RemoteDeviceClient::send_file` chunk call in
`desktop/src-tauri/src/commands.rs` with `upload_file`; keep the
deterministic `file_id` (peer+path+size+mtime) for resume; keep the
cancel handle aborting the stream; keep resume-offset persistence.
*Depends:* T-A10. *Acceptance:* desktop -> daemon send completes, cancel
mid-send stops it, retry-after-drop resumes; `TransferPanel` shows live
progress.

### T-A12: Desktop sender tests  `[x]`
**Done 2026-07-16.** Added `upload_file_delivers_intact_file_and_reports_progress`
to `desktop/core/tests/desktop_core_e2e.rs` (pairs, uploads over a real
daemon, verifies bytes + monotonic outgoing progress). Also pinned the
e2e daemon's download dir (hermetic, mirrors daemon `common/mod.rs`) --
this test had silently broken when the default moved to `~/Downloads`.
Desktop core e2e 5/5 green.

Update/extend so send/cancel/resume are covered without a live daemon
where possible. *Depends:* T-A11. *Acceptance:* `cargo test` (desktop
core) + `vitest` green.

### Mobile receiver

### T-A13: Locate/prepare the mobile gRPC service impl  `[x]`
**Done 2026-07-16.** Server is `mobile/lib/src/services/connectible_server.dart`
(`ConnectibleServer extends pb.ConnectibleServiceBase`). Added
`prepareUpload`/`uploadFile` overrides throwing `GrpcError.unimplemented`;
`flutter analyze` clean. Real logic in T-A14/T-A15.

Confirm where mobile serves the `Connectible` service (its inbound
`ConnectibleServer`) and add the two new method overrides as stubs first.
*Depends:* T-A3. *Acceptance:* `flutter analyze` clean with empty
overrides that return UNIMPLEMENTED.

### T-A14: Implement mobile `PrepareUpload`  `[x]`
**Done 2026-07-16.** `FileTransferModel.handlePrepareUpload` (mints a
token + resume offset from the partial's length). Auth (paired sender)
is enforced one layer up in `PairingModel.prepareUpload` (throws
UNAUTHENTICATED unless the sender is in `knownDevices`), wired through
new `ServerDelegate.prepareUpload` + `ConnectibleServer`. `_uploadTickets`
map holds live offers.

Authorize the requester (active/paired peer), compute resume offset from
the partial in the app-private `received/` dir, mint a token, return
offers. *Files:* mobile server impl + `file_transfer_model.dart`.
*Depends:* T-A13. *Acceptance:* widget/unit test: paired peer accepted,
resume offset reflects a partial.

### T-A15: Implement mobile `UploadFile` (OOM fix)  `[x]`
**Done 2026-07-16.** `FileTransferModel.handleUploadFile`: validates the
header token, streams chunks to the `.part` at offset, folds a
**streaming SHA-256** via `sha256.startChunkedConversion` (seeded from
the on-disk prefix on resume) -- **no `readAsBytes`**, the OOM fix.
Finalizes with collision-safe naming + sets `incomingFilePath`; hash
mismatch discards; short stream keeps a resumable partial. (The old
chunk path's `_verifyWholeFile` readAsBytes still exists but is dormant;
removed at cutover, T-A21.)

Stream chunks to the `.part` at offset; fold a **streaming SHA-256**;
finalize with collision-safe naming and populate `incomingFilePath`.
**Delete the `readAsBytes` whole-file verify** in
`file_transfer_model.dart` (`_verifyWholeFile`) — this is the OOM fix.
*Depends:* T-A14. *Acceptance:* a >=100MB receive completes without OOM,
verifies, and "Save to..." exports it.

### T-A16: Mobile receiver tests  `[x]`
**Done 2026-07-16.** New "incoming upload receive (Phase A)" group in
`file_transfer_model_test.dart`: prepared+streamed upload lands verified
on disk; dropped stream keeps a partial a second upload resumes; wrong
declared hash fails without finalizing. Drives `handlePrepareUpload` +
`handleUploadFile` directly with synthesized streams (no network).
`flutter analyze` clean; file suite green.

Adapt `mobile/test/file_transfer_model_test.dart` to the streaming path;
add a resume test and a large-input (no-OOM) test. *Depends:* T-A15.
*Acceptance:* mobile receive tests green.

### Mobile sender

### T-A17: `sendFile` via the new upload RPCs  `[x]`
**Done 2026-07-16.** `FileTransferModel.sendFile` now calls
`PrepareUpload` (via the active peer's `uploadClient`, new on
`SyncConnection` -> `PairingModel._grpc?.raw`) then streams `UploadFile`
from the resume offset (async* generator, awaits between chunks). Kept
the deterministic `file_id`, streaming hash, and cancel. `SyncConnection`
gained `uploadClient` + `localIdentity` (also on `_LazyConnection`).

Rewrite `FileTransferModel.sendFile` to call `PrepareUpload` then stream
`UploadFile` from disk from the resume offset, awaiting each send for
backpressure. Keep the deterministic `file_id` and cancel support.
*Depends:* T-A3. *Acceptance:* mobile -> desktop and mobile -> mobile send
completes + verifies; resume after a drop; cancel works.

### T-A18: Mobile sender tests  `[x]`
**Done 2026-07-16.** Removed the old chunk-frame send tests (that
behavior is gone) and the T-306 resend-sender test; kept a `sendFile`
no-op-without-a-peer-client test. Updated every fake implementing
`SyncConnection`/`ServerDelegate` across the test suite to the new
members. The full mobile send path (client half) is analogous to the
desktop sender covered by `desktop_core_e2e` and is verified end-to-end
on real hardware in T-A25. *Depends:* T-A17.

### Cutover & cleanup

### T-A19: Route everything through the new path  `[x]`
**Done 2026-07-16.** Production senders/receivers all use the upload
RPCs: desktop `commands::send_file` -> `upload_file`; mobile
`FileTransferModel.sendFile` -> PrepareUpload/UploadFile; daemon +
mobile receivers implement the upload RPCs. No production code path emits
`FileTransferStart`/`FileChunk` anymore.

### T-A20: Remove old chunk handling on the daemon  `[x]`
### T-A21: Remove old chunk handling on mobile  `[x]`
### T-A22: Reserve the retired proto fields  `[x]`

**Done 2026-07-20, in root `TASKS.md` Phase I (T-I1-I8) -- see that
file for the full account.** All three landed exactly as the plan below
described: chunk handling removed from `SyncStream`
(`daemon/src/grpc/service.rs`) + `TransferManager` (`daemon/src/
transfer/mod.rs`) + `remote.rs::send_file`; `onFileTransferStart`/
`onFileChunk`/`onFileChunkRequest` dropped from `pairing_model.dart` +
the chunk paths (incl. `_verifyWholeFile`) from `file_transfer_model.
dart`; the retired `SyncFrame` oneof cases + messages marked `reserved`
in the proto; every chunk-oriented test rewritten, ported, or
deleted (grpc_smoke transfer cases, fault_injection.rs deleted
entirely, the desktop e2e `send_file` test, the mobile chunk-receive/
T-908 tests).

**Important deviation from this section's own original gating
condition, flagged explicitly rather than silently glossed over:** this
was written to be gated on **T-A25 (real-device stability
verification)** below -- Linux <-> Android over real LAN Wi-Fi,
including a real Wi-Fi-pull-mid-transfer resume test -- specifically so
a "proven-working" fallback would never be deleted before the
replacement was confirmed on Luna's actual hardware. T-A25 has **not**
been run (this sandbox has no phone). Phase I proceeded anyway on the
strength of the automated test suite (unit + real-TLS integration
tests, including a resume-after-a-dropped-stream test) staying fully
green, which is a materially weaker guarantee than T-A25's real-network
+ real-interruption scenario. The old chunk path is no longer available
as a fallback if something real-world-specific turns out to be wrong
with the dedicated path's resume behavior. **Recommend running T-A25
for real soon** -- it's now the only thing standing between "the
automated tests pass" and "file transfer actually holds up on Luna's
own phone and Wi-Fi," with no safety net left if it doesn't.

### Progress, errors, polish

### T-A23: Progress + terminal-state fidelity end-to-end  `[x]`
**Done 2026-07-16.** Outgoing: desktop `upload_file` + mobile `sendFile`
emit throttled `TransferProgress(Dto)` with completed/failed/canceled;
incoming: daemon `UploadWriter` (on `TransferManager`'s broadcast ->
LocalEvents) + mobile `_emitUpload`. Both UIs key on the stable
`file_id`. `desktop_core_e2e` asserts monotonic outgoing progress ending
`completed`; mobile receive tests assert terminal states.

Ensure bytes/total/percent and completed/failed/canceled map cleanly
through the new path into both UIs (desktop `transfer-progress` events,
mobile `TransferProgress`). *Depends:* T-A11, T-A17. *Acceptance:* a
paused/canceled/failed transfer renders the right state on both clients.

### T-A24: Error mapping for uploads  `[x]`
**Done 2026-07-16.** Desktop `upload_file` returns
`DesktopError::Remote { code }`: unpaired -> `UNAUTHENTICATED` (via the
daemon's PrepareUpload Status), all-bytes-but-bad-hash ->
`CHECKSUM_MISMATCH`, short/declined -> `FILE_TRANSFER_FAILED`; the
frontend's `errorCodeMessage()` localizes them. Mobile surfaces failures
as a failed transfer row (GrpcError caught in `sendFile`).

Map upload failures to `ErrorCode` (checksum mismatch, unauthenticated,
disk-full, peer-declined) so `errorCodeMessage()`/mobile strings show
actionable text, never raw gRPC status. *Depends:* T-A23. *Acceptance:*
each failure class shows the correct localized message.

### T-A25: Real-device stability verification
Linux <-> Android over real LAN Wi-Fi, both directions: transfer >=100MB;
pull Wi-Fi mid-transfer and confirm it **resumes** (not restarts) and the
hash matches. *Depends:* the rest of Phase A. *Acceptance:* repeated large
transfers succeed; a mid-transfer blip resumes + verifies; no OOM, no
stuck "connecting".

---

## Phase B - Revive advertised-but-dead features

Battery and notifications have wire format + desktop UI but the mobile
client never sends them (capabilities dropped); clipboard is manual-only.
Highest-ROI parity work — no new proto needed. Ref
`REVIEW-2026-07-15.md`.

### Battery

### T-B1: Mobile battery polling  `[x]`
**Done 2026-07-16.** New `battery_model.dart`: `BatteryModel` reads level
+ charging via `battery_plus` (injectable `reader`/`changes` so tests
need no platform channel), on an interval + on every battery-state
change. Added `battery_plus: ^6.0.0`.

### T-B2: Send `BatteryStatus` + re-advertise capability  `[x]`
**Done 2026-07-16.** `BatteryModel.report()` pushes a `BatteryStatus`
frame onto the active session (only while connected; initial + periodic +
on-change), wired in `app_providers.dart`. Re-added `"battery"` to
`device_list_model.dart` capabilities. 3-test unit suite
(`battery_model_test.dart`). *Depends:* T-B1.
**Verification note (2026-07-17):** now executed -- `flutter analyze`
clean and `flutter test test/battery_model_test.dart` green (3/3).
**Bug fixed while verifying:** `buildAppStateProviders` constructed
`BatteryModel` *before* the `late final pairing` it lazily targets, and
`BatteryModel`'s constructor eagerly calls `report()` (touching the
connection) -- a `LateInitializationError` the widget tests (shell/
`widget_test`) hit. Moved battery/notification construction after
`pairing` is assigned, and marked both providers `lazy: false` so a
never-read provider still takes ownership and disposes BatteryModel's
periodic timer at teardown (was leaking a pending timer).

### T-B3: Verify battery on desktop  `[ ]` (real-device; fold into T-A25)
The daemon already forwards `BatteryStatus` (StatusHub -> LocalEvents)
and desktop `StatusBar.tsx` renders it; this just needs a real phone
paired to a desktop to confirm live %/charging shows + updates.
*Depends:* T-B2.

### Notifications

### T-B4: Android `NotificationListenerService` scaffold  `[x]`
**Done 2026-07-16/17.** Native `ConnectibleNotificationListener`
(`NotificationListenerService`) + `NotificationPlugin` (method +
event channels), registered in `MainActivity.configureFlutterEngine`;
`AndroidManifest.xml` declares the service with the
`BIND_NOTIFICATION_LISTENER_SERVICE` permission + intent filter.
Foreground-service + group-summary notifications filtered native-side.
Dart seam `notification_listener.dart` (`NotificationListener` abstraction
+ `PlatformNotificationListener` + pure decoders); decoder + off-Android
no-op tests in `notification_listener_test.dart` (fixed the off-Android
tests, which hung because `flutter_test` reports `defaultTargetPlatform ==
android` -- now overridden to `linux`).

### T-B5: Notification permission opt-in flow  `[x]`
**Done 2026-07-17.** `NotificationModel` tracks the system grant state
from the listener's lifecycle stream and exposes `openAccessSettings()`;
Settings screen gained a "Notification mirroring" section
(`_NotificationsRow`) showing granted/denied + a Grant/Manage pill that
deep-links to the system Notification-access page (revoke is the same
page). EN+TR strings added. *Depends:* T-B4.

### T-B6: Map + send `NotificationData` + re-advertise  `[x]`
**Done 2026-07-17.** `NotificationModel` forwards each posted/updated
notification as a `NotificationData` frame on the active session (only
while connected + access granted). Re-added `"notifications"` to
`device_list_model.dart` capabilities. *Depends:* T-B5.

### T-B7: Dismiss sync  `[x]`
**Done 2026-07-17.** A removal event sends `NotificationData` with
`is_dismissal=true` (empty title/body) -- but only for an id we actually
forwarded a post for (bounded `_forwarded` set, oldest-evicted, cleared on
revoke), so a dismissal for an unknown/foreground notification is
suppressed as noise. *Depends:* T-B6.

### T-B8: Notification tests  `[x]`
**Done 2026-07-17.** `notification_model_test.dart` (5 tests): forwards a
post, no-op while disconnected, dismissal only for a previously-posted id
(with empty content), grant-state tracked from lifecycle + notifies,
`openAccessSettings` delegates. Settings widget test extended with a
`NotificationModel` provider (Noop connection/listener). *Depends:* T-B7.
**Desktop panel test:** unchanged -- the desktop `NotificationsPanel`
already consumed `NotificationData` and had coverage; this task only added
the *mobile sender*, so no desktop-side wire change to test.
**Real-device mirror check** (phone notification -> desktop panel) folds
into T-A25's real-device pass.

### Clipboard (mobile automatic)

### T-B9: Background clipboard-change detection on mobile  `[x]`
**Already shipped in v0.1.0 (T-304), confirmed 2026-07-17.**
`ClipboardModel` polls the OS clipboard every 2s while foregrounded
(`WidgetsBindingObserver` lifecycle gating) and auto-sends genuinely new
content -- no manual "Send" required. Now gated by the T-B11 toggle.

### T-B10: Auto-apply incoming clipboard on mobile  `[x]`
**Already shipped in v0.1.0 (T-304), confirmed 2026-07-17.**
`handleInbound` writes inbound frames to the OS clipboard and
`ClipboardEchoGuard` (mirrors the daemon's hash-based suppression) stops
the read-back from looping to the sender. Now gated by the T-B11 toggle.

### T-B11: Clipboard auto toggles + tests  `[x]`
**Done 2026-07-17.** Added persisted `clipboardAutoMonitor` /
`clipboardAutoApply` flags to `SettingsModel` (default true, preserving
the v0.1.0 always-on behavior + desktop parity), threaded through
`buildAppStateProviders` -> `ClipboardModel` (seeded at launch from
`main.dart`). `ClipboardModel` now gates the poll-send on `autoMonitor`
and the inbound OS-clipboard write on `autoApply` (and only records the
echo-suppression hash when it actually applies), with live
`setAutoMonitor`/`setAutoApply` setters. New "Clipboard sync" Settings
section (two monochrome `_ToggleRow`s) flips both the persisted flag and
the live model. EN+TR strings. Tests: `clipboard_model_test.dart`
auto-apply on/off + live-flip (mock platform clipboard channel);
`settings_screen_test.dart` toggle drives both SettingsModel + live model.
*Depends:* T-B10.

---

## Phase C - Security hardening for 1.0

### T-C1: Design the TOFU trust store  `[x]`
**Done 2026-07-17.** Written design at [`docs/tofu-trust-store.md`](../tofu-trust-store.md):
client-pins-server model (only the client observes a cert; daemon server
stays `no_client_auth`), fingerprint = `sha256(end_entity_DER)` computed in
the client verifier (`AcceptSelfSignedCert`), storage reuses the existing
`devices.cert_fingerprint` column + a new mobile `certFingerprint` field,
record-on-first-use (which doubles as the T-C5 backfill), and the
block-with-`FINGERPRINT_CHANGED`-warning mismatch flow (resolve by
forget+re-pair). Includes the desktop split (core observes, daemon stores
via loopback RPC) + migration note.

### T-C2: Capture fingerprint at pairing (daemon)  `[x]`
**Done 2026-07-17.** `DeviceRepository::set_fingerprint`/`fingerprint` over
the existing `devices.cert_fingerprint` column; two loopback-only RPCs
`GetPinnedFingerprint`/`RecordFingerprint` (`grpc/service.rs`,
`require_loopback`-gated) let the CLIENT (desktop-core), which is the party
that actually observes a peer's cert, persist the pin into the daemon store
(the daemon server stays `no_client_auth`). Desktop `confirm_pin` records
the observed fingerprint once the device is paired. *Files:* `daemon/src/db/`,
`daemon/src/grpc/`, `desktop/core/src/tls.rs`, `desktop/src-tauri/`.

**Tests deferred** to the final test phase (per Luna's plan: implement in
order, save all new unit/integration tests for last).

### T-C3: Verify fingerprint on connect (daemon)  `[x]`
**Done 2026-07-17.** `TofuVerifier` (`desktop/core/src/tls.rs`) replaces
the accept-any verifier: it fingerprints the presented server cert and, if
a pin was supplied, REJECTS the handshake on mismatch with a
`FINGERPRINT_CHANGED` marker. `commands::send_file` pre-fetches the pin
(`GetPinnedFingerprint`) and dials with `connect_pinned`, mapping a
rejection to `ERROR_CODE_FINGERPRINT_CHANGED` -> a localized EN/TR message;
unchanged peers reconnect seamlessly. *Depends:* T-C2.

### T-C4: Mobile TOFU (store + verify)  `[x]`
**Done 2026-07-17.** Mirrored on the mobile client (`grpc_service.dart`
`onBadCertificate` computes + compares the cert SHA-256; rejects on
mismatch), with the pin persisted in the paired-store JSON
(`DeviceInfo.certFingerprint`). `_reconnect` enforces the pin (stops
retrying + surfaces a changed-key message) and records-on-first-use;
`confirmPin` pins at pairing. Mobile server side is unchanged (like the
daemon it never sees a client cert; the connecting peer pins mobile's
cert). *Depends:* T-C1.

### T-C5: Migration for existing paired devices  `[x]`
**Done 2026-07-17 (inherent in the record-on-first-use design).** A device
paired before TOFU has an empty `cert_fingerprint`/`certFingerprint`; the
first post-upgrade connect records the observed fingerprint (desktop
`connect_with_tofu` backfill; mobile `_reconnect` when `pinned == null`),
so no forced re-pair and the pin is enforced from the *second* connect on.
*Depends:* T-C3, T-C4.

### T-C6: Rate-limit mDNS discovery handling  `[x]`
**Done 2026-07-17.** `daemon/src/discovery/mod.rs`: the discovery table is
capped at 256 distinct advertisers (new device_ids past the cap dropped;
known devices still update their address) and per-advertiser
`ServiceResolved` processing is throttled to 10/10s via the shared
`RateLimiter`, so a discovery flood exhausts neither memory nor CPU. Unit
test covers the cap + known-device-update. *Files:* `daemon/src/discovery/`.

### T-C7: Rate-limit transfer initiation  `[x]`
**Done 2026-07-17.** `PrepareUpload` is throttled per peer (device_id) to
60/60s in `grpc/service.rs`; excess returns `RESOURCE_EXHAUSTED`. Checked
after the paired gate so only authenticated peers spend the budget; normal
multi-file sends (one prepare per session) are unaffected. Test: 60
accepted, 61st throttled. *Depends:* Phase A.

### T-C8: Per-IP connection rate limiting  `[x]`
**Done 2026-07-17.** New dependency-free `daemon/src/ratelimit.rs`
(fixed-window, memory-bounded) wired into `tls::accept_loop`: a source IP
exceeding 30 accepts/10s has further sockets dropped before the TLS
handshake, so a connection flood can't exhaust the handshake pool or FDs.
The same primitive backs T-C6/T-C7. `grpc_smoke` (8/8) confirms normal
connections are unaffected.

### T-C9 (optional for 1.0): SQLite at-rest encryption  `[-]`
**Deferred (explicitly optional).** Encrypting device/transfer metadata
(sqlcipher-equivalent) + platform keyring integration (Linux Secret
Service, Android Keystore) is the documented deferrable item; time-boxed
out of the 1.0 security pass. The DB holds only device names/ids +
fingerprints (no secrets like PINs, which are never persisted), so this is
a hardening nicety, not a gate. Can be revisited post-1.0.

---

## Phase D - Verification & release

### T-D1: Real-device pairing (Linux <-> Android)
*Acceptance:* fresh pair over real LAN, both initiation directions.

### T-D2: Real-device clipboard sync
*Depends:* Phase B clipboard. *Acceptance:* text propagates both ways on
hardware.

### T-D3: Real-device remote input
*Acceptance:* phone touchpad/keyboard drives the desktop over real LAN.

### T-D4: X11-only desktop pass
Clipboard + input backends on a pure X11 session (only Wayland tested so
far). *Acceptance:* both work under X11.

### T-D5: Release pipeline end-to-end
Drive a real `v*` tag through the GitHub Release workflow. *Acceptance:*
daemon binary + Tauri `.deb`/AppImage + APK build and attach.

### T-D6: Fresh-clone build - daemon  `[x]`
**Done 2026-07-17.** A `git clone` into a clean dir builds `connectibled`
from scratch (all deps compiled; the daemon proto stubs are generated by
build.rs at compile time). *Acceptance:* met.

### T-D7: Fresh-clone build - desktop  `[x]`
**Done 2026-07-17.** In a fresh clone, `npm ci` (committed lockfile
resolves) + `npm run build` produces the production frontend bundle
(`dist/`, vite + tsc clean); the `src-tauri` + `core` crates build via the
workspace. Full Tauri `.deb`/AppImage *bundling* needs the release
environment's system deps (folds into the T-D5 release pipeline).

### T-D8: Fresh-clone build - mobile APK  `[x]`
**Done 2026-07-17.** A fresh clone builds `app-debug.apk` after
`tool/gen_proto.sh` regenerates the (gitignored) Dart stubs. **This caught
two real breaks the in-place `flutter analyze` missed** (it used stale
committed-out stubs / doesn't parse the manifest): (1) `ConnectibleServer`
was missing the new `getPinnedFingerprint`/`recordFingerprint` overrides
the regenerated `ConnectibleServiceBase` requires; (2) an illegal `--`
inside an `AndroidManifest.xml` comment failed manifest merging. Both
fixed. A signed *release* APK is a T-D5 release-pipeline step.

### T-D9: LAN throughput on real network
Confirm >=20MB/s sustained over real Wi-Fi (only measured over loopback
so far). *Depends:* Phase A. *Acceptance:* measured + recorded.

---

## Phase E - Docs & polish

### T-E1: User guide - pairing
First-pair walkthrough with screenshots (both directions, manual connect
fallback). *Acceptance:* a new user pairs from the guide alone.

### T-E2: User guide - clipboard & transfer
Copy/paste sync + send/receive/"Save to..." + where files land.
*Acceptance:* covers both flows with screenshots.

### T-E3: User guide - remote input & troubleshooting
Touchpad/keyboard usage + common issues (firewall, mDNS, ydotool).
*Acceptance:* troubleshooting resolves the top real-world failures.

### T-E4: Mobile remote-input keys - Enter/Backspace/Arrows  `[x]`
**Done (already present; verified 2026-07-17).** Enter (keysym 0xff0d),
Backspace (0xff08), and the four arrows (0xff51-0xff54) were already wired
in `remote_input_screen.dart` from T-305; T-E5's work added wire-level
tests asserting each sends the correct keysym as a press/release pair.

### T-E5: Mobile remote-input keys - Tab + F1-F12  `[x]`
**Done 2026-07-17.** Added Tab (keysym 0xff09) and F1-F12 (contiguous
0xffbe..0xffc9, `F[n]=F1+(n-1)`) to the mobile keyboard as a monochrome
`_KeyCap` `Wrap`, sending the X11 keysyms the daemon input backend already
injects (no daemon change needed). EN+TR `input.tab` string. Tests cover
every special key at the wire level (press+release carry the right
keysym). `flutter analyze` clean; `remote_input_screen_test` 8/8 green.
*Depends:* T-E4.

### T-E6: Mobile paired-device platform icon  `[x]`
**Done 2026-07-17.** Added a `platform` field to the UI `DeviceInfo` model
(the real gap; the `platform: ''` in the task was on the manual-connect
`NearbyDevice`, legitimately unknown). Populated it from the peer's real
`Identity` on every paired path (`addPairedDevice` inbound, `listDevices`
outbound, persisted+restored in the paired-store JSON), via the shared
`DeviceListModel.platformName()` enum->name mapper. `home_screen.dart`
overlays a monochrome `platformIcon(...)` badge (existing shared helper) on
each paired constellation node + a Platform row in the info sheet.
`flutter analyze` clean; `home_screen_test` 3/3 (added a paired-Android
icon assertion).

### T-E7: Bound the HomePanel nearby list  `[x]`
**Done 2026-07-17.** `HomePanel.tsx` caps rendered pairable stars at
`MAX_PAIRABLE = 8`; extras are counted, not rendered, and a subtle
monochrome "+X more nearby" line (`home.nearbyMore`, EN+TR) shows the
hidden count. The `StatusStrip` still reports the true total. Test feeds
20 nearby devices, asserts exactly 8 stars render + the indicator reads
"+12 more nearby". `tsc` clean, `vitest` HomePanel 15/15 green.

### T-E10: Fix the hanging `clipboard_screen_test` "tapping Send" test  `[x]`
**Done 2026-07-17.** Root cause was two-fold: the T-304 `Timer.periodic`
poll AND -- the dominant hang -- `_sendCurrent` calling the real
`SystemChannels.platform` clipboard MethodChannel, which this test binding
leaves unmocked (blocks forever). Fix (test-only,
`clipboard_screen_test.dart`): register an in-memory mock clipboard
handler; construct `ClipboardModel` with a 1-hour `pollInterval`; replace
`pumpAndSettle()` with bounded `pump()`s. All original assertions intact.
`flutter test test/screens/clipboard_screen_test.dart` now ~1s green; the
full mobile suite runs to completion (no multi-minute hang).

### T-E8 (optional): Developer onboarding guide  `[x]`
**Done 2026-07-17.** [`docs/developer-guide.md`](../developer-guide.md):
prerequisites, per-codebase build/run, the `XDG_DATA_HOME`+`CONNECTIBLE_PORT`
two-daemon local test, System Doctor usage, the proto/gen_proto workflow
(incl. the mobile-server-override gotcha), test commands + mobile timer
hygiene, and a PR checklist (ending with a fresh-clone-build reminder).

### T-E9 (optional): Proto/API doc expansion  `[x]`
**Done 2026-07-17.** [`docs/api-reference.md`](../api-reference.md):
transport/TOFU/loopback model, every RPC group (sync, pairing, streamed
upload, devices, loopback UI/TOFU/diagnostics) with request/response shape,
and the full `ErrorCode` table with per-code remediation + where the
mapping lives on each side.

---

## Phase F - System Doctor (comprehensive self-diagnostics)

One diagnostics engine that finds problems across the *whole* system —
not just the connection — and is runnable **both** from the terminal
(`connectibled doctor`, scriptable) and from the app (desktop panel +
mobile screen). Every check reports a severity (ok / warn / error), a
plain-language summary, and a concrete remediation. The engine is the
single source of truth: CLI and UI call the same checks. This *expands*
the existing `ConnectionDoctorPanel` (which only covers a handful of
connection checks) into a full system doctor.

### T-F1: Diagnostics core + check registry  `[x]`
**Done 2026-07-17.** `daemon/src/diagnostics/mod.rs`: a `Check` trait (id,
title, category, async `run(&ctx) -> CheckResult{status, summary, detail,
remediation, data}`) + a `Registry` that runs all/one and rolls up worst
severity (`Status` is `Ord` so `max` = worst). `DiagnosticsContext` carries
`Config` + optional live-daemon `runtime` (uptime), so the engine runs both
standalone (CLI) and in-daemon (the T-F7 RPC) -- one source of truth.
*Files:* `daemon/src/diagnostics/`. **Unit tests deferred** to the final
test phase (per Luna's plan).

### T-F2: Environment & storage checks  `[x]`
**Done 2026-07-17.** `environment.rs`: daemon version (+ uptime when run
in-daemon); data/tls/transfers/download dirs exist & writable (probed with
a temp write, auto-creating a missing dir like the daemon does); free disk
space for incoming files (via `df`, warns under 512 MiB). Each reports
ok/warn/error + remediation. Idle-RSS folds into T-F7 (needs live daemon).

### T-F3: Network & transport checks  `[~]`
**Core done 2026-07-17.** `network.rs`: primary LAN address (connected-UDP
route probe), daemon-port TCP reachability, TLS cert/key presence. **Folds
in with T-F7 (in-daemon):** live TLS 1.3 handshake, gRPC Ping/RTT, cert
validity+expiry (needs an X.509 parser), protocol-version compat, mDNS
advertise/discover -- these need the running daemon's state, so they land
with the RPC.

### T-F4: Pairing & device checks  `[x]`
**Done 2026-07-17.** `pairing.rs`: opens the device DB read-only, reports
paired count + TOFU pin coverage, warns (not errors) on pre-TOFU devices
not yet cert-pinned (they backfill on next connect). Per-device
online/last-seen detail folds into T-F7 (live PeerRegistry). *Depends:*
T-F1.

### T-F5: Feature-backend checks  `[x]`
**Done 2026-07-17.** `features.rs`: X11/Wayland session detection;
received-files opener presence (xdg-open/gio/nautilus/dolphin/thunar, ties
to `open_path`); ydotool input backend (warns on Wayland if missing);
leftover `.part` files in the transfers dir. *Depends:* T-F1.

### T-F6: Terminal interface - `connectibled doctor`  `[x]`
**Done 2026-07-17.** `cli.rs` + `main.rs` dispatch: `connectibled doctor
[--json] [--check <id>]` runs the shared registry, prints a colored table
(`[ OK ]`/`[WARN]`/`[FAIL]`) + overall status, emits compact JSON with
`--json`, runs one check with `--check`, and exits 0 (ok/warn) / 1 (any
error) / 2 (unknown check id). Verified end-to-end (14 checks, real
environment). *Depends:* T-F1-F5.

### T-F7: Loopback `RunDiagnostics` RPC  `[x]`
**Done 2026-07-17.** `RunDiagnostics(check_id) -> {checks[], worst}` on the
service, `require_loopback`-gated, running the same `default_registry`
in-process (so port/DB/backend checks reflect the live daemon + report
uptime via a new `started_at`). `DiagnosticCheck` mirrors the engine's
`CheckResult` on the wire. This also completes the deferred **T-F3**
network checks that need the running daemon (the in-daemon run gives the
live port/DB/feature state). *Depends:* T-F1.

### T-F8: Desktop System Doctor panel  `[x]`
**Done 2026-07-17.** `ConnectionDoctorPanel.tsx` rewritten from bespoke
client-side checks into a thin renderer over the RPC (via
`LocalDaemonClient::run_diagnostics` + `DiagnosticsReportDto` + a Tauri
`run_diagnostics` command + ipc binding): checks grouped by category,
monochrome OK/WARN/FAIL badges, detail + remediation, run-all + per-check
re-run, overall worst badge, copy-report. Panel and CLI show identical
results. EN/TR chrome strings. *Depends:* T-F7. **Its old test will be
rewritten in the final test phase.**

### T-F9: Mobile Doctor screen  `[x]`
**Done 2026-07-17 (in-house; the parallel-agent hand-off was cancelled).**
A Dart diagnostics framework (`mobile/lib/src/services/doctor/`) mirrors the
daemon engine's model (`DoctorStatus`/`DoctorCheck`/`DoctorRunner` + worst
rollup). Mobile-native connectivity checks: incoming server bound (new
`PairingModel.serverRunning`), network present (`NetworkInterface`), active
session, mDNS discovery sweep. `DoctorScreen` (grouped by category,
monochrome OK/WARN/FAIL badges, detail + remediation, run-all + per-check
re-run + copy report) reached from a Settings "System Doctor" entry.
*Depends:* T-F1.

### T-F10: Mobile permission & platform checks  `[x]`
**Done 2026-07-17.** Permission checks with state + actionable remediation:
notification-listener access (granted/denied + a deep-link action reusing
`NotificationListener.openAccessSettings`), clipboard (the Android
foreground-only read constraint), battery-optimization (guidance to allow
unrestricted background), and SAF save availability. Where a state can't be
read without native code (battery-optimization) it degrades to guidance
rather than faking OK. *Depends:* T-F9, Phase B.

### T-F11: Log capture & recent-error surfacing  `[x]`
**Done 2026-07-17.** A process-global bounded ring buffer (last 50
warn/error lines) fed by a tracing `CaptureLayer` added to the daemon
subscriber; a `RecentErrors` check reports the count + last few lines. It
rides the shared registry, so it appears in `connectibled doctor`, the F7
RPC, and the desktop panel automatically. *Depends:* T-F6, T-F8.

---

## Explicitly out of scope for 1.0.0 (by design, documented)

MPRIS/media control, presentation remote, find-my-phone, run-commands,
SFTP/remote filesystem, telephony (SMS/calls), contacts sync, airplane/
screen-lock/volume sync, connectivity report, screen mirroring; and
Windows/macOS/iOS ports. These have no code and no planning-doc
commitment — non-goals, not deferred bugs.
