# File Map — where everything lives

**Maintenance contract:** whenever you create, move, or delete a
file/directory that another session would need to find, update this
map in the same change. This file exists so no AI session has to
rediscover the layout by searching.

## Top-level layout

| Path | What it is |
|---|---|
| `daemon/` | Rust daemon crate `connectibled` |
| `desktop/` | Tauri + React app; `desktop/core` = webview-free Rust client crate; `desktop/src-tauri` = shell/commands |
| `mobile/` | Flutter Android app; `mobile/android/` Kotlin bridges |
| `proto/connectible.proto` | The wire contract (single source of truth; frozen v1) |
| `docs/` | ALL documentation + GitHub Pages root (publishes everything under it) |
| `backups/` | FROZEN snapshots (old desktop, abandoned mobile-rn). Never touch |
| `.claude/`, `.agents/` | Tooling: settings, skills (`frontend-design`) |
| `.github/workflows/` | `ci.yml`, `release.yml`, `pages.yml` |

Root markdown is only `README.md`, `CHANGELOG.md`, `CLAUDE.md` — do
not add more; docs go under `docs/`.

## docs/ layout

| Path | Content |
|---|---|
| `docs/TASKS.md` | ACTIVE roadmap (Phases G-N; G-J done) — the file you mark checkboxes in |
| `docs/TASKS-audit-fixes.md` | Audit-fix campaign task list (Phases X1-X7) |
| `docs/context/` | This folder — AI/system context (context, file-map, decisions, conventions, known-issues, glossary, progress) |
| `docs/RULES.md` | Engineering ground rules ("don't" list; conventions.md here is the "do" list) |
| `docs/ARCHITECTURE.md` | Runtime architecture + sequences (pairing flow etc.) |
| `docs/api-reference.md` | RPC/API contract documentation (daemon <-> UI <-> peers) |
| `docs/tofu-trust-store.md` | Trust/TOFU security model incl. the mobile client-cert asymmetry |
| `docs/developer-guide.md` | Contributor-facing guide |
| `docs/design/` | Design notes/measurements (db-encryption, systemd-service, perf, ...) |
| `docs/archive/` | Superseded: PLAN.md, FINDINGS.md, old TASKS-v* files, old reviews |
| `docs/prompts/` | Operational prompts (e.g. `audit-fix-prompt.md`) |
| `docs/assets/` | README/site images (`architecture.svg`) |

## Load-bearing source files

| File | Why it matters |
|---|---|
| `daemon/src/grpc/service.rs` | Every RPC handler + SyncStream frame dispatch + loopback gating |
| `daemon/src/lib.rs` | Daemon wiring/startup (`run()`) |
| `daemon/src/transfer/upload.rs` | Upload tickets + streaming writer (the only transfer path) |
| `daemon/src/db/` | `repository.rs` (devices, encrypted fingerprints), `history.rs` (transfer history), `keys.rs` (DB key chain), `../migrations/` |
| `daemon/src/tls.rs` | TLS identity + accept-any-client-cert verifier (TOFU happens at app layer) |
| `desktop/core/src/local.rs` | `LocalDaemonClient` (loopback RPCs) |
| `desktop/core/src/remote.rs` | `RemoteDeviceClient` (dials peers: pair, upload_file) |
| `desktop/src-tauri/src/commands.rs` | All Tauri IPC commands (register in `src-tauri/src/lib.rs`) |
| `desktop/src/hooks/useDaemon.ts` | Frontend state hub (events, transfers, devices) |
| `desktop/src/lib/ipc.ts` | Typed command wrappers — every UI->Rust call goes through here |
| `mobile/lib/src/state/pairing_model.dart` | Session owner (requester + responder sides) |
| `mobile/lib/src/state/app_providers.dart` | DI wiring of all models |
| `mobile/lib/src/services/connectible_server.dart` | Phone's own inbound gRPC server |
| `mobile/tool/gen_proto.sh` | Regenerates Dart stubs (generated code is NOT committed) |

## Where state lives at runtime

- Daemon: `~/.local/share/connectibled/` (SQLite DB, TLS certs, key
  file, download-dir override).
- Desktop UI prefs: localStorage (theme/locale).
- Mobile: shared_preferences (device roster `connectible.paired_devices`,
  transfer history `connectible.transfer_history`, settings) + app
  documents `received/` for incoming files.
