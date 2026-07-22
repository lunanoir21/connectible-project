> **FROZEN REFERENCE — DO NOT EDIT, DO NOT BUILD FROM HERE.**
>
> This directory is a read-only snapshot of `desktop/`, taken before the
> desktop UI was simplified to match the plain, low-density design language
> of the Orca reference screenshots (see `TASKS.md` at repo root). This is a
> visual/UX simplification pass, not a framework or protocol change — the
> live app stays `desktop/` throughout — but the snapshot exists so the
> pre-simplification layout, spacing, and screen density can be restored or
> diffed against if a specific change turns out to be the wrong call.
>
> - The live, evolving desktop app is `desktop/`. See `TASKS.md` at repo
>   root for the simplification plan.
> - This backup does **not** get deleted as part of the simplification
>   work, even after it's judged done. Removing it is a deliberate call
>   for the user to make later.
> - Build artifacts (`node_modules/`, `dist/`, `src-tauri/target/`,
>   `src-tauri/gen/`, `core/target/`) were intentionally excluded from this
>   snapshot; it is source-only. Run `npm install` inside this directory if
>   you ever need to actually build from it.

---

Original `desktop/README.md` follows, unmodified, as a starting point:

# Connectible Desktop

Tauri v2 + React 18 + TypeScript + Tailwind desktop app for Connectible.
Dark theme, cool-toned (blue) accent -- no gold/amber anywhere.

## Layout

```
desktop/
  core/          connectible-desktop-core: daemon-client logic, NO webview dep
    src/
      local.rs   local daemon client (loopback TLS, cert pinned from data dir)
      remote.rs  remote device client (pairing, file send, remote input)
      tls.rs     MVP accept-self-signed verifier for remote daemons
      dto.rs     proto -> camelCase serde DTOs for the frontend
    tests/       end-to-end tests against a real in-process daemon
  src-tauri/     thin Tauri shell: commands, events, system tray
  src/           React frontend (panels, hooks, IPC wrappers)
  docs/          ADR-001 (why we don't use gRPC-Web)
```

See [docs/ADR-001-desktop-transport.md](docs/ADR-001-desktop-transport.md)
for why the UI talks to the daemon from the Tauri Rust core rather than
via gRPC-Web.

## Prerequisites

- Node.js 18+ and npm
- Rust (stable)
- A running `connectibled` daemon (the app connects to it on loopback;
  it reads the daemon's self-signed cert from the daemon data dir to
  pin it).
- **System webview libraries for the Tauri shell (Linux):**
  `webkit2gtk-4.1` (GTK3) and its development headers. Tauri v2 stable
  targets the 4.1 (GTK3) series. On distros that ship only
  `webkitgtk-6.0` (GTK4), install the 4.1 packages as well, e.g.:
  - Debian/Ubuntu: `libwebkit2gtk-4.1-dev`
  - Fedora: `webkit2gtk4.1-devel`
  - Arch: `webkit2gtk-4.1`

  The `desktop/core` crate and the React frontend build and test
  **without** these libraries; only the `src-tauri` shell needs them.

## Develop and test

```sh
# Frontend deps
npm install

# Type-check (strict) and unit/component tests -- no daemon or webview needed
npm run typecheck
npm test

# Desktop core integration tests -- spins up a real daemon in-process
cargo test -p connectible-desktop-core

# Run the full app (requires webkit2gtk-4.1 and a running daemon)
npm run tauri dev
```

## Frontend <-> backend contract

The React app never opens a network connection. It calls Tauri commands
and listens for Tauri events, all wrapped in
[`src/lib/ipc.ts`](src/lib/ipc.ts):

- Commands: `get_local_state`, `list_devices`, `ping_daemon`,
  `pair_with_device`, `confirm_pin`, `send_file`, `daemon_connected`.
- Events: `local-event` (pairing prompts, battery, notifications,
  clipboard, transfer progress), `daemon-status` (connected/reconnecting),
  `transfer-progress` (outgoing sends).

## Known MVP limitations (desktop)

- Requires the daemon to be running; the app shows a "Connecting…" state
  and retries with exponential backoff (500ms -> 30s) if the daemon is
  down or restarts.
- Remote input in the MVP is receive-only on the desktop (a paired phone
  drives this computer); driving another machine from the desktop is a
  post-MVP stretch and not exposed in the UI.
- Notification mirroring is one-way (phone -> desktop); the panel is
  read-only and says so.
