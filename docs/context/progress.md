# Progress Dashboard

Thin, dynamic view of where the project stands. Detail lives in
`docs/TASKS.md` (active), `docs/archive/TASKS-v1.0-completion-roadmap.md`
(superseded roadmap), and `docs/TASKS-audit-fixes.md` (campaign).
**Update rule:** flip a row + date when a phase opens/closes — not
per-task (checkboxes in the task files carry that).

Last updated: **2026-07-24**. (Roadmap file archived; new active
`docs/TASKS.md` opened, scoped to hidden weaknesses: error handling,
error-message consistency, UI feedback completeness, stale docs.)

## Completion-criteria roadmap — ARCHIVED 2026-07-24

Was `docs/TASKS.md`, now `docs/archive/TASKS-v1.0-completion-roadmap.md`.
Phases G-M all done; only N stays open, re-tracked (still parked) in
the new active `docs/TASKS.md`.

| Phase | Topic | Status |
|---|---|---|
| A-F | v1.0 file-transfer re-architecture | Done (archived: `docs/archive/TASKS-v1.0-filetransfer.md`) |
| G | Bidirectional TOFU (daemon pins client certs) | Done 2026-07-20 |
| H | DB at-rest encryption (AES-256-GCM + key chain) | Done 2026-07-20 |
| I | Legacy chunk-transfer path removal | Done 2026-07-20 |
| J | Persisted transfer history (all surfaces) | Done 2026-07-22 |
| K | Notification dismiss-sync | Done 2026-07-23 |
| L | Clipboard rich content (images) | Done 2026-07-24 — implementation landed 2026-07-23, full test run (`cargo test` 134/134, `vitest` 137/137, `flutter test` 182/182) completed 2026-07-24, one stale test assertion fixed (T-L3's intentional image-first MIME order vs. an un-updated test name/assertion) |
| M | End-user documentation | Done 2026-07-23 (`docs/user-guide.md` + a full multi-page guide site at `docs/guide/`, linked from README + Pages landing) |
| N | Real-device battery measurement | **Not done** — tooling/protocol ready (`docs/design/battery-measurement.md`, `mobile/tool/battery_measure.sh`); re-tracked as-is in the new active `docs/TASKS.md`'s "Deferred" section; still needs Luna's go-ahead to actually run |

## Active: hidden weaknesses (`docs/TASKS.md`, opened 2026-07-24)

Source material: a full-codebase investigation pass (`luna-space/weak-spots-report.html`,
private/gitignored) plus a follow-on targeted read comparing desktop's
vs. mobile's error-message discipline. Phases are named, not lettered;
task ids are mnemonic prefixes.

| Phase | Topic | Status |
|---|---|---|
| Documentation & Diagnostics Accuracy | `known-issues.md`'s stale "Open defects" section (lists issues already closed in `TASKS-audit-fixes.md`) + related doc accuracy checks | Not started |
| Silent & Weak Error Handling | Six catch-and-drop/log-only spots, mostly mobile (`file_transfer_model.dart`, `home_screen.dart`, `main.dart`, `doctor/checks.dart`), plus a missing inbound-`error`-frame case in `pairing_model.dart` | Not started |
| Error Message Consistency & Quality | Mobile's `PairingModel._setError` shows raw/un-localized exception text where desktop's `ErrorState` always routes through `errorCodeMessage()` — build the missing mobile mapping | Not started |
| UI Feedback Completeness Audit | Broader sweep confirming (or fixing) the same message discipline holds outside the one path already checked closely | Not started |

## Audit-fix campaign (`docs/TASKS-audit-fixes.md`)

**Status: complete (2026-07-23).** All seven phases (X1-X7) done,
including all four of X6's decision-gated items (T-X36-T-X39). See
the file's own "Kampanya Özeti" summary at its top for the campaign-
level report and final regression counts.

| Phase | Topic | Status |
|---|---|---|
| X1 | Mobile critical (pairing persistence, received-file access, Save-to OOM) | Done |
| X2 | Desktop critical (daemon pipe deadlock, list liveness) | Done |
| X3 | Desktop medium | Done |
| X4 | Mobile medium | Done |
| X5 | Low/cleanup (both) | Done |
| X6 | Decision-gated (owner input) | Done — all 4 decisions recorded and implemented |
| X7 | Close-out + full regression | Done |

## Standing flags

- **`docs/context/known-issues.md`'s "Open defects (tracked)" section
  is stale** (found 2026-07-24): it still lists six issues
  (T-X1/T-X2/T-X3/T-X5/T-X6/T-X8/T-X9/T-X20) as open; all are `[x]` in
  `docs/TASKS-audit-fixes.md`. Fix tracked as `docs/TASKS.md`'s DOC-1.
- **Phase L, T-L7 known gap (still open, not part of the new active
  file):** mobile's manual "Send" button is still text-only
  (`Clipboard.getData(kTextPlain)`); an image can only be pushed via
  the automatic background poll, not manually when auto-monitor is
  off.
- **T-A25 real-device transfer/resume verification still not run**
  (flagged since Phase I; the legacy fallback no longer exists).
- **Real-device confirmation still pending** for: T-X20's Android
  multicast-lock fix (mDNS field-discovery reliability) and Phase K's
  `cancelNotification` (does it actually clear the OS notification, not
  just succeed as an API call). A phone was connected to this machine
  on 2026-07-24 (adb-visible), so these are now practically runnable —
  not yet run.
- Release tags are owner-only; last committed work may trail the
  working tree (owner commits herself).
