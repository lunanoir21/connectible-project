# Progress Dashboard

Thin, dynamic view of where the project stands. Detail lives in
`docs/TASKS.md` (roadmap) and `docs/TASKS-audit-fixes.md` (campaign).
**Update rule:** flip a row + date when a phase opens/closes — not
per-task (checkboxes in the task files carry that).

Last updated: **2026-07-22**.

## Roadmap phases (`docs/TASKS.md`)

| Phase | Topic | Status |
|---|---|---|
| A-F | v1.0 file-transfer re-architecture | Done (archived: `docs/archive/TASKS-v1.0-filetransfer.md`) |
| G | Bidirectional TOFU (daemon pins client certs) | Done 2026-07-20 |
| H | DB at-rest encryption (AES-256-GCM + key chain) | Done 2026-07-20 |
| I | Legacy chunk-transfer path removal | Done 2026-07-20 |
| J | Persisted transfer history (all surfaces) | Done 2026-07-22 |
| K | Notification dismiss-sync | Not started (note: mobile->desktop dismissal already works end-to-end; see audit) |
| L | Clipboard rich content (images) | Not started |
| M | End-user documentation | Not started |
| N | Real-device battery measurement | Not started |

## Audit-fix campaign (`docs/TASKS-audit-fixes.md`)

| Phase | Topic | Status |
|---|---|---|
| X1 | Mobile critical (pairing persistence, received-file access, Save-to OOM) | Not started |
| X2 | Desktop critical (daemon pipe deadlock, list liveness) | Not started |
| X3 | Desktop medium | Not started |
| X4 | Mobile medium | Not started |
| X5 | Low/cleanup (both) | Not started |
| X6 | Decision-gated (owner input) | Waiting on owner |
| X7 | Close-out + full regression | Not started |

## Standing flags

- **T-A25 real-device transfer/resume verification still not run**
  (flagged since Phase I; the legacy fallback no longer exists).
- Release tags are owner-only; last committed work may trail the
  working tree (owner commits herself).
