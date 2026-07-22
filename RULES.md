# Connectible - Development Rules

These rules apply across all three components (`daemon/`, `desktop/`,
`mobile/`). They override personal style preference where they
conflict. See [PLAN.md](PLAN.md) for schedule and [TASKS.md](TASKS.md)
for the work items these rules govern.

---

## 1. General rules (all languages)

- All source code, comments, commit messages, and identifiers are
  **ASCII-only**. No emoji, no smart quotes, no non-ASCII symbols,
  anywhere in the codebase -- including in generated protobuf comments
  and log message strings.
  - **Scoped exception -- localization resource files.** UI translation
    dictionaries (e.g. `desktop/src/i18n/locales/*.json`, and the mobile
    equivalent) are locale *data*, not code, and MUST use each language's
    correct characters (e.g. Turkish diacritics: c-cedilla, dotless-i,
    g-breve, etc.). This exception is limited to the *values* inside
    those resource files; all keys, code, comments, and identifiers stay
    ASCII. Any non-ASCII outside these resource files is still a defect.
- No mock data anywhere in shipped code paths. If a feature is
  unfinished, it returns an explicit "not implemented" error or is
  hidden behind a capability flag -- it does not fabricate plausible-
  looking fake responses.
- No half-finished implementations: a task is either done to its
  acceptance criteria (see TASKS.md) or not merged. Do not merge a
  feature "mostly working" behind a TODO with no tracking issue.
- Don't add abstractions, config flags, or generality beyond what the
  current task requires. Three similar lines beat a premature helper.
- Single binary daemon deployment: the daemon must build as one
  statically-linked executable with no runtime dependency on a
  dynamically loaded plugin system. Platform-specific backends (X11 vs
  Wayland, ydotool vs wayland-client) are compiled in and selected at
  runtime, not shipped as separate binaries.

---

## 2. Rust (daemon)

### Style
- Functions and variables: `snake_case`. Types (structs, enums,
  traits): `PascalCase`. Constants: `SCREAMING_SNAKE_CASE`.
- Format with `cargo fmt` (default settings) before every commit;
  lint with `cargo clippy --all-targets -- -D warnings` and treat
  warnings as build failures in CI.
- Async code uses `tokio` exclusively -- do not mix in `async-std` or
  a second executor.
- Logging uses the `tracing` crate (`tracing::info!`, `warn!`,
  `error!`, `debug!`), never `println!`/`eprintln!`, so log output is
  structured and filterable. Attach relevant fields (`device_id`,
  `transfer_id`) as structured fields, not string-interpolated into
  the message.

### Error handling
- All fallible functions return `Result<T, E>`; define a project-wide
  `DaemonError` enum (via `thiserror`) rather than passing around
  `anyhow::Error` in library code -- `anyhow` is acceptable only in
  the top-level `main.rs`/binary entry point.
- **No `unwrap()` or `expect()` outside of tests and `main()`
  startup-time invariants that are truly unrecoverable (e.g. failing
  to install a `tracing` subscriber).** Every other fallible call is
  propagated with `?` or handled explicitly.
- Never swallow an error silently (`let _ = fallible_call()`) unless
  the comment directly above explains why the error is genuinely safe
  to ignore in that specific context.
- Prefer narrow, typed errors over `String` error messages so callers
  can match on error kind (this is why `connectible.proto` has a
  dedicated `ErrorCode` enum -- Rust-side errors should map onto it
  cleanly at the RPC boundary).

### Testing
- Unit tests colocated in `#[cfg(test)] mod tests` within the module
  they cover.
- Integration tests (crossing module or process boundaries, e.g. the
  pairing flow in T-016) live under `tests/`.
- Every `[core]`-labeled task in TASKS.md that touches parsing,
  cryptographic comparison, or network fault handling must ship with
  at least one test exercising the failure path, not only the happy
  path.
- No test may depend on real network hardware or external services;
  use loopback and in-process fakes (see T-049's fault-injection
  transport).

### Performance targets
- Clipboard change propagation: under 2 seconds end-to-end on a
  typical home LAN.
- File transfer throughput: sustain at least 20 MB/s over loopback/
  local LAN for the chunked transfer path (chunk size and buffering
  should not be the bottleneck; network/disk may be).
- Remote input latency: under 50ms from `RemoteInputEvent` receipt to
  backend dispatch (excluding network transit time).
- Daemon idle RSS: under 30MB with no active transfers/streams.
- Startup time (cold, including mDNS advertisement and TLS cert
  load/generation): under 1 second on typical hardware.

---

## 3. TypeScript (desktop, Tauri + React)

### Style
- Variables and functions: `camelCase`. React components, types,
  interfaces: `PascalCase`. Component files named after their default
  export (`DeviceList.tsx` exports `DeviceList`).
- `strict: true` in `tsconfig.json`; no `any` without an inline comment
  justifying why (e.g. an untyped third-party callback payload).
- Functional components with hooks only -- no class components.
- Global state: prefer React context + hooks for simple cases; use
  Zustand only when state is genuinely shared across distant parts of
  the tree and prop drilling/context becomes unwieldy (e.g. the
  connected-device list consumed by five+ unrelated panels). Do not
  reach for Zustand by default.
- UI components come from shadcn/ui; do not hand-roll a component that
  shadcn/ui already provides (buttons, dialogs, toasts, progress
  bars). Customize via Tailwind classes and the shadcn theming layer,
  not by forking component source unnecessarily.

### Dark theme rules
- The application ships dark-theme only for MVP. Color tokens live in
  a single CSS-variables block; no component hardcodes a hex color
  inline.
- **No gold, amber, or yellow accent colors anywhere in the palette.**
  The palette is strictly monochrome black/grey (near-white surface,
  near-black text is the one "accent"); no blue, purple, or other hue
  is introduced as a substitute. This is a hard constraint, not a
  placeholder -- verify visually before marking a UI task done.

### Error handling
- Every gRPC-Web call is wrapped so a failure surfaces as a typed
  result (`{ ok: true, data } | { ok: false, error: ConnectibleError }`)
  rather than an uncaught promise rejection reaching a component.
- User-facing errors map `ErrorCode` (from the proto) to a specific,
  actionable message string; do not show raw gRPC status text to end
  users.

### Testing
- Component and unit tests with `vitest` + `@testing-library/react`.
- Every panel task in TASKS.md (T-035..T-041) needs a test asserting
  it renders real data correctly and handles the empty/loading/error
  states distinctly.
- `tsc --noEmit` must pass with zero errors as a CI gate, independent
  of the test suite.

---

## 4. Dart (mobile, Flutter)

### Style
- Class members and functions: `camelCase`. Classes, enums, typedefs:
  `PascalCase`. Files: `snake_case.dart`.
- Run `dart format` before commit; `flutter analyze` must report zero
  issues (treat `analysis_options.yaml` lints as errors in CI, not
  warnings).
- State management via `provider` (`ChangeNotifier` + `Consumer`/
  `Selector`); do not introduce a second state-management library
  (Riverpod, Bloc, GetX) without an explicit decision recorded in this
  file.

### Error handling
- All I/O (network, file, platform-channel calls) uses `async`/`await`
  wrapped in `try`/`catch`, converting platform exceptions into a
  project-defined `ConnectibleException` hierarchy mirroring the
  proto's `ErrorCode` where applicable.
- Never use a bare `catch (e) {}` that discards the exception; at
  minimum log via a structured logger, and surface a user-visible
  state change (error banner, retry button) for anything affecting a
  user-initiated action (pairing, file transfer).

### Testing
- Widget tests for each screen (pairing PIN entry, device list, file
  transfer, remote input surface) using `flutter_test`.
- Model/unit tests for each `ChangeNotifier` (`DeviceListModel`,
  `PairingModel`, `ClipboardModel`, `FileTransferModel`) covering state
  transitions including error and timeout paths (e.g. PIN expiry).
- `flutter test` must be green in CI; treat flaky widget tests as bugs
  to fix, not to `skip`.

---

## 5. Git conventions

### Commit messages
Follow Conventional Commits:
- `feat: add resumable file transfer chunking`
- `fix: correct PIN expiry race in ConfirmPin`
- `refactor: extract DeviceRepository from daemon main`
- `test: add fault-injection test for chunk corruption`
- `docs: document ydotool udev setup in README`
- `chore: bump tonic to 0.12`

Scope prefix is optional but encouraged for a multi-crate/multi-app
repo: `feat(daemon): ...`, `feat(desktop): ...`, `feat(mobile): ...`.

### Branch naming
- `feature/<short-description>` for new functionality (e.g.
  `feature/resumable-file-transfer`).
- `fix/<short-description>` for bug fixes.
- `refactor/<short-description>` for non-behavioral restructuring.
- `docs/<short-description>` for documentation-only changes.

### PR hygiene
- Reference the TASKS.md task ID(s) a PR addresses (e.g. "Implements
  T-024, T-025") in the PR description.
- A PR that changes `connectible.proto` must update generated code in
  all three components in the same PR (see T-003) and call out that
  it is a protocol change in the title/description.
- Do not merge with failing CI. Do not use `--no-verify` to bypass
  hooks; if a hook is wrong, fix the hook in its own PR.

---

## 6. Security checklist

Apply this checklist to every task touching the network, storage, or
credential-like material (PINs, keys, certs).

- [ ] TLS 1.3 only, no fallback to TLS 1.2 or plaintext for any
      cross-device RPC (loopback desktop<->local-daemon traffic is the
      one exception, and even that should use TLS where the stack
      supports it -- see T-033).
- [ ] No custom cryptographic primitives; use `rustls`/`ring` (Rust),
      platform TLS (Dart's `grpc` package), and standard hashing
      (`sha2`, CRC32 crates) -- never a hand-rolled cipher, hash, or
      "obfuscation" scheme.
- [ ] PIN comparison is constant-time (T-012); PIN generation uses a
      cryptographically secure RNG, not `rand::thread_rng()`'s
      non-CSPRNG paths or a time-seeded PRNG.
- [ ] Private keys and certificates are stored with `0600` permissions
      and never logged, even at `debug`/`trace` level.
- [ ] Public key pinning is **explicitly deferred to v1.0** -- MVP
      trusts a peer's self-signed cert on every connection without
      persisting/verifying it against a prior-seen fingerprint. This
      is a known, documented gap (see PLAN.md non-goals and T-053),
      not a silent omission.
- [ ] Message signing beyond the TLS channel itself is optional and
      not implemented in MVP; do not claim end-to-end signing in user-
      facing docs.
- [ ] SQLite storage is plaintext in MVP. This is an accepted,
      documented limitation -- do not add partial/half-implemented
      encryption that gives a false sense of security. Either do it
      properly (v1.0 task) or leave it plaintext and documented.
- [ ] Rate-limit/lock out repeated failed `ConfirmPin` attempts
      (T-012) to blunt brute-forcing a 6-digit PIN within its 30s
      window (10^6 space, but a naive unlimited-retry loop over a fast
      local connection could still be meaningfully faster than
      intended -- 3-attempt lockout closes this off).
- [ ] Any new RPC or `SyncFrame` case added post-MVP must state, in its
      PR description, whether it is authenticated only by the existing
      paired-connection TLS session or requires additional per-message
      authorization -- do not assume "it's inside the stream, so it's
      trusted" without stating that assumption explicitly.

---

## 7. Documentation requirements

- Every `[core]` task's acceptance criteria in TASKS.md is the
  definition of "done" for review purposes -- reviewers check against
  it directly.
- Any deviation from `connectible.proto` as reviewed/frozen in T-002
  requires updating the proto file's own inline comments in the same
  change, not just an external doc.
- User-facing setup steps that are non-obvious from code alone (udev
  rules, Wayland protocol availability, firewall/mDNS multicast
  requirements) must be captured in T-053's docs, not left as tribal
  knowledge in a PR description or chat log.
