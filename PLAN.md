# Connectible - Implementation Plan

Cross-platform device synchronization tool (KDE Connect alternative).
Components: Rust daemon (tokio + tonic + rustls + sqlx), Tauri v2 +
React desktop UI, Flutter mobile app. Shared contract: `connectible.proto`.

Status: MVP planning. Target: v0.1.0 in 4-6 weeks (200-220 hours).

See also: [TASKS.md](TASKS.md) for the granular task breakdown,
[RULES.md](RULES.md) for coding/testing/security standards,
[ARCHITECTURE.md](ARCHITECTURE.md) for topology and sequence diagrams,
[proto/connectible.proto](proto/connectible.proto) for the wire protocol.

---

## 1. Goals and non-goals

### Goals (MVP / v0.1.0)
- Discover paired-capable devices on the local network via mDNS.
- Pair two devices using a 6-digit PIN, TLS 1.3-encrypted from the
  first byte.
- Sync clipboard (text) bidirectionally with echo suppression.
- Transfer files in resumable 65 KB chunks with corruption detection.
- Inject remote mouse/keyboard input from phone -> desktop.
- Forward battery status and notifications, one direction each (phone
  reports battery; phone -> desktop notification mirroring).
- Ship a single static daemon binary, a Tauri desktop app, and a
  Flutter mobile app that all interoperate.

### Non-goals (explicitly deferred)
- Public key pinning / trust-on-first-use certificate storage (v1.0).
- Message-level signing beyond TLS (optional, post-MVP).
- SQLite at-rest encryption (MVP stores plaintext; flagged as a known
  gap in the security checklist, not silently ignored).
- Internet/relay-based sync (WAN); MVP is LAN-only.
- Multi-hop routing between more than two paired devices per session.
- Windows/macOS input-injection backends (Linux X11/Wayland only for
  MVP; desktop UI still builds cross-platform, but remote-input is
  gated behind a capability flag from `Identity.capabilities`).

---

## 2. Component overview

| Component        | Stack                                                                 | Deliverable                          |
|-------------------|------------------------------------------------------------------------|---------------------------------------|
| `daemon/`         | Rust, tokio, tonic (gRPC/HTTP2), rustls, sqlx+SQLite, mdns-sd          | Single static binary (`connectibled`) |
| `desktop/`        | Tauri v2, React 18, TypeScript, Tailwind, shadcn/ui                    | Native app bundle (Linux first)       |
| `mobile/`         | Flutter, Dart, Provider                                                 | Android APK (iOS follow-up)           |
| `proto/`          | Protocol Buffers v3                                                     | `connectible.proto`, generated stubs  |

The daemon is the only process that speaks raw gRPC over TLS to other
daemons. The desktop UI talks to its *local* daemon over gRPC-Web
(loopback, still TLS) rather than implementing the sync protocol
itself. The mobile app embeds daemon-equivalent client logic directly
in Dart (no local daemon process on mobile) and speaks the same
`connectible.proto` service to the desktop/laptop daemon it pairs
with.

---

## 3. Critical path

```
mDNS discovery (T-003..005)
        |
proto schema frozen (T-001..002)
        |
gRPC server skeleton (T-006..009)
        |
device pairing (T-010..016)  <-------- SQLite storage (T-017..019)
        |
   +----+----+--------------+
   |         |               |
clipboard  file transfer   remote input      (T-020..031, parallelizable
   |         |               |                once pairing lands)
   +----+----+--------------+
        |
desktop UI panels (T-032..041) -- mobile screens (T-042..048)
        |
integration / E2E tests (T-049..052)
        |
CI/CD + release artifacts (T-053..054+)
```

Everything under "clipboard / file transfer / remote input" can be
built in parallel by different people once pairing + SyncStream frame
routing exists, because each feature is an independent `SyncFrame`
oneof case. Desktop UI and mobile UI work can start as soon as the
gRPC server responds to `ListDevices`/`Pair`/`Ping` with real data --
they do not need to wait for clipboard/file/input to be finished, only
stubbed/echoing.

---

## 4. Week-by-week breakdown

### Week 1 - Foundations
- Finalize and review `connectible.proto` (T-001, T-002).
- Scaffold `daemon/` cargo workspace, `desktop/` Tauri+React project,
  `mobile/` Flutter project; wire up proto codegen for all three
  (tonic-build for Rust, protoc-gen-grpc-web for TS, protoc plugin for
  Dart) (T-003).
- Implement mDNS advertisement + discovery (`mdns-sd`) (T-004, T-005).
- Stand up tonic gRPC server over rustls with a self-signed
  certificate generated on first run (T-006..T-009).
- SQLite schema + sqlx migrations for `devices` table (T-017, T-018).

**Week 2 deliverable checkpoint:**
- Proto schema reviewed and frozen for v0 (no further breaking changes
  without a version bump).
- Daemon skeleton compiles, runs, and serves `Ping`/`ListDevices` over
  TLS.
- mDNS discovery demonstrably finds a second daemon instance on the
  same LAN (manual two-machine or two-VM test).

### Week 2 - Pairing + storage
- Implement `Pair` / `ConfirmPin` RPCs end-to-end, including the
  30-second PIN expiry timer (T-010..T-016).
- Persist paired devices with timestamps; implement `ListDevices`
  fully (online/offline detection via last-seen + open connection
  check) (T-017..T-019).
- Begin desktop UI shell (Tauri window, dark theme tokens, shadcn/ui
  install, gRPC-Web client wiring against the loopback daemon)
  (T-032..T-034).
- Begin mobile app shell (Flutter project structure, Provider setup,
  mDNS discovery screen) (T-042..T-044).

### Week 3-4 - Feature build-out (parallel tracks)
- **Clipboard sync** (T-020..T-023): x11-clipboard read/write,
  wayland-client read/write, change-detection loop, echo suppression
  via `content_hash`, clipboard history ring buffer.
- **File transfer** (T-024..T-027): chunked sender/receiver, resume
  logic keyed by `transfer_id` + `resume_offset_bytes`, SHA-256 whole-
  file verification, CRC32 per-chunk verification with re-request on
  mismatch.
- **Remote input** (T-028..T-031): ydotool backend for X11, wayland-
  client (virtual-keyboard/pointer-constraints protocols) backend for
  Wayland, input event batching/rate-limiting from the mobile sender.
- **Battery + notifications** (T-020a/T-023a, folded into the
  clipboard/notification tasks list, see TASKS.md T-030/T-031 area):
  battery polling on mobile, forwarding over SyncStream; notification
  listener on mobile, forwarding + dismissal echo.
- Desktop UI: device list, clipboard history panel, file transfer
  progress panel, remote-input toggle/touchpad view, system tray icon
  with quick actions (T-035..T-041).
- Mobile UI: pairing PIN dialog, device list, clipboard sync toggle,
  file picker + upload/download screen, remote touchpad/keyboard
  screen (T-045..T-048).

**Week 4 deliverable checkpoint:**
- All daemon features (clipboard, file transfer, remote input,
  battery, notifications) implemented and manually verified between
  two daemon instances.
- Desktop UI has all five panels rendering real (non-mock) data from
  the local daemon.
- Mobile app can discover, pair, and drive clipboard/file/input
  against a desktop daemon.
- Integration tests covering pairing and clipboard round-trip are
  green in CI.

### Week 5 - Hardening + integration testing
- Network-interruption handling: reconnect/backoff logic in the
  SyncStream client wrapper on both daemon and mobile; file-transfer
  resume verified by killing the connection mid-transfer (T-049).
- File-corruption handling: inject bit-flips in test fixtures, verify
  CRC32/SHA-256 rejection and re-request path (T-050).
- Clock-skew handling: verify `captured_at_ms`/`reported_at_ms`
  comparisons degrade to a logged warning, never a hard failure
  (T-050a, see TASKS.md).
- Cross-platform manual test pass: Linux X11 <-> Linux Wayland <->
  Android, at least one full pairing + all-features run per pair.
- Fix bugs surfaced by the above; no new features this week.

### Week 6 - Documentation, CI/CD, release
- Full README, daemon operator docs, desktop/mobile user docs
  (T-053 area).
- CI pipeline: `cargo test` + `cargo clippy -D warnings` for daemon,
  `tsc --noEmit` + `vitest` for desktop, `flutter test` for mobile, all
  gated on PR (T-054).
- Static-linked release build of the daemon (musl target on Linux),
  Tauri bundle, Flutter APK; tag `v0.1.0` and attach artifacts.

**Week 6 deliverable checkpoint:**
- End-to-end automated tests passing in CI (not just manual runs).
- Documentation complete enough that a new contributor can build and
  run all three components from a clean checkout.
- CI/CD pipeline green on the release tag.
- v0.1.0 artifacts (daemon binary, Tauri bundle, APK) attached to the
  GitHub release.

---

## 5. Dependency graph (task-level, see TASKS.md for IDs)

```
T-001 proto draft ----> T-002 proto review/freeze
                              |
                              v
T-003 workspace scaffold + codegen (Rust/TS/Dart)
      |            |                    |
      v            v                    v
T-004 mDNS adv   T-006 tonic server   T-042 Flutter shell
      |            |    + T-007 rustls        |
      v            v                          v
T-005 mDNS disc  T-008 TLS self-signed cert   T-043 Provider setup
      \            |
       \           v
        \      T-009 SyncFrame routing skeleton
         \         |
          \        v
           \   T-010..016 Pairing (Pair/ConfirmPin, PIN timer)
            \      |
             \     v
              \  T-017..019 SQLite storage
               \    |
                +---+---------------------------+
                |         |          |           |
                v         v          v           v
          T-020..023 T-024..027 T-028..031  T-032..041 Desktop UI
          Clipboard  File xfer  Remote input      |
                |         |          |            v
                +----+----+----------+     T-042..048 Mobile UI
                     |                            |
                     v                            v
              T-049..052 Integration / E2E tests
                     |
                     v
              T-053..054 Docs + CI/CD + release
```

---

## 6. Risk register and mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Wayland input injection has no stable "just works" API (portal permission prompts, compositor differences) | High | High | Scope MVP to wlr-protocols (virtual-keyboard-unstable-v1, pointer-constraints) on wlroots compositors; document GNOME/KDE portal gaps as known limitations rather than blocking the release. |
| mDNS unreliable on some routers (multicast filtering, AP isolation) | Medium | High | Provide a manual "enter IP address" fallback pairing path in both UIs from week 3 onward, not as an afterthought. |
| ydotool requires a running `ydotoold` daemon + udev permissions | High | Medium | Document setup in README with exact udev rule; detect absence at daemon startup and surface a clear UI error rather than a silent failure. |
| Resumable file transfer edge cases (partial last chunk, transfer_id collision) | Medium | Medium | Dedicated test task T-050 with fault-injection harness; transfer_id is UUIDv4, collision probability treated as negligible but offset-based idempotency makes a collision merely confusing, not corrupting. |
| Clock skew between devices breaks last-writer-wins clipboard logic | Medium | Low | Use monotonic local sequence numbers as a tiebreaker in addition to `captured_at_ms`; never hard-fail on skew, only log. |
| TLS cert management complexity creeping into MVP scope | Medium | Medium | MVP explicitly uses self-signed certs generated on first run and accepted without pinning; pinning work is fenced off to v1.0 (T-053 docs must state this as a known MVP limitation, not silently shipped). |
| Scope creep: contributors gold-plating clipboard/file/input beyond MVP acceptance criteria | Medium | Medium | TASKS.md acceptance criteria are the definition of done; anything beyond is a `[optional]`-labeled task, not blocking week 4/6 checkpoints. |
| Single point of failure: one contributor blocked on proto changes blocks everyone | Low | High | Proto frozen at end of week 1 (T-002); any post-freeze change requires updating all three codegen targets in the same PR and is treated as a breaking-change review, not a quick edit. |
| Flutter <-> Rust daemon interop bugs only found in week 5 | Medium | High | Cross-platform manual pairing test happens incrementally from week 2 onward (pairing), week 3-4 (features), not deferred entirely to week 5. |
| SQLite plaintext storage is a real security gap | High (accepted) | Medium | Explicitly documented in RULES.md security checklist and PLAN.md non-goals as an MVP-known limitation; do not let it silently become "the design" -- track it as a v1.0 task. |

---

## 7. Edge cases the implementation must handle

- **Network interruption mid-file-transfer**: sender detects stream
  closure, receiver keeps partial file + records highest contiguous
  offset written; on reconnect, receiver's next `FileTransferStart`
  handling (or a lightweight resume-request the client sends first)
  causes the sender to re-issue `FileTransferStart` with
  `resume_offset_bytes` set, then continues chunking from there.
- **File corruption**: every `FileChunk` carries a CRC32; a mismatch
  triggers a chunk-level re-request (not a full-transfer restart).
  Final `FileTransferStart.file_hash` (SHA-256) is verified once the
  last chunk lands; mismatch marks the transfer failed with
  `ERROR_CODE_CHECKSUM_MISMATCH` and deletes the partial file.
- **Clock skew**: `captured_at_ms` / `reported_at_ms` timestamps are
  informational and used for tie-breaking, never for authorization or
  correctness-critical branching. A skew warning is logged (via
  `tracing::warn!`) when a peer's timestamp is more than 5 minutes from
  local time, but the operation still proceeds.
- **PIN expiry race**: if `ConfirmPin` arrives after
  `pin_expires_at_ms`, respond with `verified = false` and
  `ERROR_CODE_PAIRING_TIMEOUT`; the requester's UI must restart pairing
  from `Pair`, not silently retry `ConfirmPin`.
- **Duplicate pairing**: `Pair` for a `device_id` already present in
  the `devices` table with a valid session should short-circuit to
  "already paired" rather than generating a fresh PIN, to avoid
  confusing double-dialogs.
- **Daemon restart during an open SyncStream**: client-side stream
  wrapper (desktop and mobile) implements exponential backoff
  reconnect (starting at 500ms, capped at 30s) and re-sends an
  `Identity` frame as the first message after reconnecting.

---

## 8. Definition of done (MVP / v0.1.0)

1. All tasks in TASKS.md tagged `[core]` are complete and their
   acceptance criteria verified.
2. `cargo test`, `cargo clippy -D warnings`, `flutter test`, and the
   desktop `vitest` suite are green in CI on the release tag.
3. A clean-checkout contributor can, using only the README, build and
   run the daemon, desktop app, and mobile app, and complete a full
   pair -> clipboard sync -> file transfer -> remote input flow
   between two machines.
4. Known limitations (no cert pinning, plaintext SQLite, Linux-only
   input injection, LAN-only) are documented, not silently omitted.
5. `v0.1.0` tag exists with daemon binary, Tauri bundle, and Flutter
   APK attached as release artifacts.
