# Project Context (read me first)

One-pager for AI sessions and new contributors. Facts only; details
live in the files listed in [file-map.md](file-map.md).

## What this is

**Connectible** — a KDE Connect alternative: LAN-only, no-cloud device
sync between a Linux desktop and an Android phone. Clipboard sync,
file transfer (resumable, hash-verified), notification mirroring,
remote mouse/keyboard, battery status. Everything runs over gRPC on
TLS 1.3 with PIN pairing + bidirectional TOFU certificate pinning.

**Target user:** a technical Linux user (Arch/Hyprland-class) who
wants KDE Connect behavior without KDE, with a refined monochrome
black/grey UI on both ends. The owner (Luna) is that user.

## The three processes

| Piece | Stack | Role |
|---|---|---|
| `connectibled` (`daemon/`) | Rust: tokio, tonic, rustls, mdns-sd, sqlx/SQLite | Always-on daemon on the desktop machine: gRPC/TLS server for peers, mDNS advertise/browse, SQLite device store, clipboard/input backends (X11 + wlroots Wayland) |
| Desktop app (`desktop/`) | Tauri v2 + React 18 + TS + Tailwind; `desktop/core` Rust crate | UI. Talks to its OWN daemon over loopback gRPC (`LocalDaemonClient`) and dials REMOTE peers directly (`RemoteDeviceClient`) for pairing/file sends |
| Mobile app (`mobile/`) | Flutter + Provider; small Kotlin bridges | Single process, no daemon. Runs its own inbound gRPC/TLS server too (pairing is bidirectional). Persists via shared_preferences (no SQLite) |

Key asymmetry to remember: an OUTGOING desktop file send goes
UI-process -> remote peer directly, bypassing the local daemon
entirely (that is why transfer history has two write paths).

## Current state (2026-07-22)

Wire protocol frozen (v1, reserved fields for the removed legacy
chunk path). Phases G-J shipped: bidirectional TOFU, DB column
encryption (AES-256-GCM), legacy transfer path fully removed,
persisted transfer history on all surfaces. Remaining roadmap:
`docs/TASKS.md` Phases K-N; an audit-fix campaign is staged in
`docs/TASKS-audit-fixes.md` (three 2026-07-22 audits; several real
bugs including mobile-critical pairing persistence).

## Entry points

- `make dev` — daemon + desktop together; `make test` — everything.
- Full command/verification list: [conventions.md](conventions.md).
