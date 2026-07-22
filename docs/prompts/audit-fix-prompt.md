# Prompt: Audit Fix Campaign executor

Copy-paste everything below the line into a fresh AI coding session
(Claude Code) opened at the repo root.

---

You are working in the Connectible repo — a KDE-Connect-style LAN
device-sync tool: Rust daemon (`daemon/`, crate `connectibled`),
Tauri + React desktop app (`desktop/`, with the `desktop/core` Rust
crate), Flutter Android app (`mobile/`), shared wire protocol
(`proto/connectible.proto`). Docs live under `docs/`; the active
roadmap is `docs/TASKS.md` (context only — NOT your task list).

**Your task list is `docs/TASKS-audit-fixes.md`. Read it fully before
touching anything — its "Ground rules" section is binding. Then
execute Phases X1 through X7 strictly in order, task by task.**

Non-negotiable rules (the task file repeats them with detail):

1. **Re-verify each finding against the current code before fixing.**
   Audit line numbers may have drifted; a finding may already be
   fixed. If so, mark the task `[x]` with a note saying exactly that —
   never "fix" what is not broken.
2. **Mark progress in the file as you go:** each finished task gets
   `[x]` plus a short **Done** note (what changed, which files, which
   tests prove it), matching the file's existing style.
3. **Verification cadence:** lightweight checks while working
   (`cargo check`, `flutter analyze`, `npx tsc --noEmit -p .`); the
   full suites once at the end of each phase:
   - repo root: `cargo test --workspace` and
     `cargo clippy --workspace --all-targets -- -D warnings`
   - from `desktop/`: `npx tsc --noEmit -p .` and `npx vitest run`
   - from `mobile/`: `flutter analyze` and `flutter test`
4. **Conventions:** code, comments, and docs in English, ASCII only.
   The UI is monochrome black/grey — no new colored accents beyond
   the existing danger red. Every new user-visible string gets both
   `en` and `tr` i18n entries on its platform; hardcoded English in
   UI code is a defect.
5. **Never:** run `git commit`/`push`/`tag` (the owner does all git
   herself — the tree already carries her uncommitted work), touch
   `backups/` (frozen), create new `.md` files at the repo root, or
   delete a test without documenting why in the Done note.
6. **Phase X6 is decision-gated:** for each of its tasks, present the
   options and your recommendation, then STOP and wait for the owner.
   Do not implement any option without her explicit go-ahead.
7. **Real-device steps** (e.g. multicast-lock behavior on physical
   Android) cannot run in this environment: implement + unit test,
   then flag the device verification clearly for the owner in the
   Done note instead of claiming it verified.
8. **Report honestly.** If a suite is red — including for reasons you
   did not cause — report the failure verbatim; never paper over it.
   If you discover a NEW defect mid-campaign, append it to the
   relevant phase as a new task rather than fixing it silently.
9. **Converse with the owner in Turkish** (code and docs stay
   English). Give a short Turkish status report at each phase
   boundary, with the verbatim test counts.

Start now: read `docs/TASKS-audit-fixes.md`, then begin Phase X1 with
T-X1.
