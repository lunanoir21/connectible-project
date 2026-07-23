# Known Issues, Traps, and Dead Ends

Read before debugging something "weird" — it may already be mapped.
When you hit (or resolve) one, update this file.

## Open defects (tracked)

The 2026-07-22 audit campaign (`docs/TASKS-audit-fixes.md`) is the
live list. Highest-impact until fixed:

- **Mobile: phone-initiated pairing never persists** (T-X1..T-X3) —
  no TOFU pin in that direction, pairing lost on restart,
  desktop->phone push rejected with UNAUTHENTICATED.
- **Mobile: received files unreachable after restart** (T-X5) and
  "Save to..." loads whole file into RAM (T-X6).
- **Desktop: UI-spawned daemon can deadlock once ~64KB of logs fill
  the unread stdout pipe** (T-X8).
- **Desktop: device/nearby lists never refresh on their own** (T-X9).
- **Mobile: no multicast lock -> mDNS discovery unreliable on real
  devices** (T-X20).

## Tried and failed — do not retry

- **`requestClientCertificate: true` on Dart's `SecureServerSocket`.**
  dart:io unconditionally chain-verifies presented client certs
  (`CERTIFICATE_VERIFY_FAILED: self signed certificate`); there is no
  accept-any-cert hook (unlike rustls). Attempted in Phase G; broke
  every real pairing test with 60s timeouts surfacing as
  "PairingModel used after being disposed"; reverted. Mobile inbound
  identity check stays app-layer (paired device_id). Details:
  `docs/tofu-trust-store.md` + `docs/TASKS.md` T-G6.
- **`keyring` crate 4.1.5** fails to resolve on this machine's
  registry mirror (`apple-native-keyring-store ^1.0.1` missing even
  though inactive). Pinned to **4.1.4** in `daemon/Cargo.toml` — do
  not bump without checking the mirror first.

## Test-writing traps (hit before, in this repo)

- **`sqlite::memory:` + sqlx pool with >1 connection**: every pooled
  connection gets its OWN empty in-memory DB. Multi-connection tests
  must use a temp-file DB (see
  `concurrent_fingerprint_writes_all_round_trip_correctly`).
- **vitest does not typecheck** (esbuild transpile-only): a green
  vitest run can hide real TS errors — always run
  `npx tsc --noEmit -p .` too. (Bit us in Phase J: 3 type errors in a
  test mock, 114/114 tests green.)
- **`vi.fn(() => ...{ value: [] })`** infers `never[]`; annotate mock
  return types explicitly.
- **Dart protoc plugin**: regen needs
  `PATH="$PATH:$HOME/.pub-cache/bin"`; stale stubs can MASK missing
  abstract-method implementations until regenerated (bit us in Phase
  I: `preArmPairingCode`; bit us again in Phase K, this time worse --
  `mobile/lib/src/services/connectible_server.dart` was missing
  `recordTransferHistory`/`listTransferHistory` entirely, a real gap
  dating back to Phase J that nobody had noticed because the checked-
  out stubs simply predated those RPCs. Regenerate proactively after
  *any* proto edit, in the same session, not just once at the end).
- **mobile pairing tests** run a real loopback TLS server; slow
  machines can flake on tight timeouts — investigate before blaming
  the code.

## Outstanding real-device verifications (no phone in the sandbox)

- **T-A25** (flagged in `docs/TASKS.md` T-I7): real Linux<->Android
  transfer with a Wi-Fi drop mid-transfer — the legacy fallback path
  is gone, so resume behavior on real Wi-Fi is unproven.
- Multicast-lock discovery behavior (T-X20 landed 2026-07-22; whether
  it actually fixes field discovery on a real device is still
  unconfirmed).
- Notification cancel-on-receipt (Phase K, T-K4): `cancelNotification`
  succeeding as an API call is confirmed by design (see the finding in
  `ConnectibleNotificationListener.kt`'s doc comment), but whether it
  actually clears the OS notification on a real device is unconfirmed.
- Battery drain measurement (roadmap Phase N).
- Mobile image clipboard round-trip (Phase L, T-L7): `super_clipboard`
  read/write compiles and analyzes clean, but was never exercised on a
  real device/emulator (no `flutter test` run this session either, see
  `docs/TASKS.md` T-L9). If it fails at runtime on Android specifically,
  check the `SuperClipboardDataProvider` `<provider>` entry in
  `AndroidManifest.xml` exists and the authority string matches the
  app's actual `applicationId` first.

## Operational quirks

- `docs/` is the GitHub Pages root; `.github/workflows/pages.yml`
  excludes `docs/archive/` from the deployed artifact (T-X38, decided
  and implemented 2026-07-22/23) via a staging step, not a native
  include/exclude option on `upload-pages-artifact`.
- Generated Dart gRPC stubs are intentionally NOT committed
  (regenerate via `mobile/tool/gen_proto.sh`).
- `backups/` contains a frozen pre-rewrite desktop and the abandoned
  mobile-rn migration — reference material only, never build targets.
