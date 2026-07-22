# Connectible — Developer Onboarding (T-E8)

How to build, run, and hack on Connectible locally. Connectible is three
codebases that speak one gRPC/TLS protocol (`proto/connectible.proto`):

- **`daemon/`** — the Rust background service `connectibled` (gRPC server,
  discovery, clipboard/input backends, SQLite paired-device store, System
  Doctor engine).
- **`desktop/`** — a Tauri app: a Rust `core/` library (client to peers +
  loopback client to the local daemon) and a React/TypeScript frontend
  (`src/`). The Tauri shell is `src-tauri/`.
- **`mobile/`** — a Flutter app that is both a gRPC/TLS **client and
  server** (bidirectional pairing).

## Prerequisites

- Rust (stable) + Cargo.
- Node (for the desktop frontend) — `npm`.
- Flutter SDK + Android SDK (for the mobile app).
- `protoc` and the Dart protoc plugin on `PATH` for regenerating mobile
  stubs (`dart pub global activate protoc_plugin`, then add
  `~/.pub-cache/bin` to `PATH`).
- Linux runtime tools the daemon uses: `xdg-utils` (xdg-open), and on
  Wayland `ydotool` + `ydotoold` for remote input.

## Build

```sh
# Rust workspace (daemon + desktop core + tauri) — must build with --locked in CI
cargo build --workspace

# Daemon only
cargo build -p connectibled

# Desktop frontend
cd desktop && npm ci && npm run build

# Mobile (stubs are gitignored — regenerate first)
cd mobile && PATH="$PATH:$HOME/.pub-cache/bin" ./tool/gen_proto.sh && flutter pub get
flutter build apk --debug
```

## Run

```sh
# Start the daemon (foreground; RUST_LOG controls verbosity)
RUST_LOG=info cargo run -p connectibled

# Desktop app (dev)
cd desktop && npm run tauri dev

# Mobile app
cd mobile && flutter run
```

## Two-daemon local test (no phone needed)

The daemon's gRPC port is set by `CONNECTIBLE_PORT`; its data dir comes from
`ProjectDirs`, which on Linux honours `XDG_DATA_HOME`. Override both to run
two isolated instances on one machine and pair them:

```sh
# Instance A
XDG_DATA_HOME=/tmp/cA CONNECTIBLE_PORT=58231 CONNECTIBLE_DEVICE_NAME=A \
  cargo run -p connectibled

# Instance B (second terminal)
XDG_DATA_HOME=/tmp/cB CONNECTIBLE_PORT=58232 CONNECTIBLE_DEVICE_NAME=B \
  cargo run -p connectibled
```

Each gets its own data dir (`/tmp/cA/connectible/...`) and self-signed cert
under `tls/`. Use
the desktop app's "Connect by address" (or a test harness) to pair A↔B over
loopback. The daemon integration tests (`daemon/tests/`) already spin real
TLS servers this way — read `daemon/tests/common/mod.rs` for the pattern.

## System Doctor

Fastest way to sanity-check an environment:

```sh
connectibled doctor            # colored table, exit nonzero on error
connectibled doctor --json     # machine-readable
connectibled doctor --check tls-cert
```

The same engine (`daemon/src/diagnostics/`) backs the desktop panel and the
mobile Doctor screen via the loopback `RunDiagnostics` RPC — add a check
once, in the registry, and it shows up everywhere.

## Proto workflow

`proto/connectible.proto` is the single source of truth.

- **Daemon/desktop-core (Rust):** stubs are generated at build time by
  `build.rs` (tonic-build) — just `cargo build`.
- **Mobile (Dart):** stubs are **gitignored** and must be regenerated after
  any proto change: `cd mobile && ./tool/gen_proto.sh` (with the Dart protoc
  plugin on `PATH`). Adding a service RPC makes the mobile
  `ConnectibleServiceBase` abstract — implement it in
  `connectible_server.dart` (loopback-only RPCs are stubbed
  `GrpcError.unimplemented`).

Changes must be **additive** (new fields/messages/RPCs); never renumber or
reuse a retired field number.

## Test

```sh
cargo test --workspace                 # daemon + desktop core
cd desktop && npx tsc --noEmit && npx vitest run
cd mobile && flutter analyze && flutter test test/<file>.dart
```

Mobile timer hygiene: never `pumpAndSettle()` with a model that owns a
`Timer.periodic` in the tree — pass a long interval and unmount at test end
(see `settings_screen_test.dart`). `flutter_test` reports
`defaultTargetPlatform == android`; override with
`debugDefaultTargetPlatformOverride` where you need otherwise.

## PR checklist

1. `cargo build --workspace` and `cargo test --workspace` green.
2. `cd desktop && npx tsc --noEmit && npx vitest run` green.
3. `cd mobile && flutter analyze` clean; touched-file `flutter test` green.
4. Proto changed? Regenerated mobile stubs + implemented any new mobile
   server override.
5. New user-facing strings added to **both** locales (desktop
   `i18n/locales/{en,tr}.json`, mobile `i18n/strings.dart`).
6. UI matches the monochrome aesthetic (no color accents).
7. A **fresh-clone build** still works (this catches gitignored-file gaps —
   see `TASKS.md` T-D6/D7/D8).
```
