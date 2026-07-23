# CLAUDE.md — Connectible

KDE-Connect-style LAN sync tool: Rust daemon (`daemon/`, crate
`connectibled`) + Tauri/React desktop (`desktop/`, Rust core in
`desktop/core`) + Flutter Android app (`mobile/`), one shared proto
(`proto/connectible.proto`), gRPC over TLS 1.3, PIN pairing + TOFU.

**Start here: `docs/context/` — read `context.md` and `file-map.md`
before searching the tree.** Also there: `decisions.md` (settled
choices — do not re-litigate), `conventions.md` (how to write code
here), `known-issues.md` (traps + dead ends — check before debugging),
`glossary.md`, `progress.md`.

## Active work

- `docs/TASKS.md` (created 2026-07-24): hidden weaknesses — silent/
  swallowed error handling, error-message consistency (mobile shows
  raw exception text where desktop shows a localized one), stale
  project docs, UI feedback completeness. Phase names, not letters.
- The "Road to v1.0.0" roadmap (Phases G-N) is done through M and
  archived at `docs/archive/TASKS-v1.0-completion-roadmap.md`; only
  Phase N (real-device battery measurement) is re-tracked (still
  parked, don't start without the owner asking).
- Audit-fix campaign: `docs/TASKS-audit-fixes.md` (Phases X1-X7, all done).
- Mark finished tasks `[x]` with a short Done note in the same session.

## Commands

- `make dev` (daemon + desktop) · `make test` (everything) · `make proto`
- Full verification set (run all at phase ends):
  - root: `cargo test --workspace` ; `cargo clippy --workspace --all-targets -- -D warnings`
  - `desktop/`: `npx tsc --noEmit -p .` ; `npx vitest run`
  - `mobile/`: `flutter analyze` ; `flutter test`
- vitest does not typecheck — a green run never excuses a red tsc.
- After proto edits: mobile stubs via `mobile/tool/gen_proto.sh`
  (needs `PATH="$PATH:$HOME/.pub-cache/bin"`); stubs are uncommitted.

## Hard rules

- Code/comments/docs: English, ASCII. Chat with the owner: Turkish.
- **Never** `git commit`/`push`/`tag` unless the owner explicitly
  asks — she owns git; the tree carries her uncommitted work.
- Never touch `backups/` (frozen). `mobile-rn` is dead.
- No new root-level `.md` files — docs go under `docs/` (design ->
  `docs/design/`, retired -> `docs/archive/`, prompts ->
  `docs/prompts/`).
- UI is monochrome black/grey (danger red is the only accent); every
  new user-visible string gets `en` + `tr` i18n keys.
- New UI-only daemon RPCs are `require_loopback`-gated; removed proto
  fields become `reserved`; every unbounded map/table gets a cap.
- Report failures verbatim; document deviations/skipped checks in the
  task file — never silently.
- `luna-space/` (repo root, gitignored) is Luna's private scratch
  space for one-off reports she explicitly asks for (audits,
  investigations, ...). Write requested reports there, not under
  `docs/` and not at repo root — it's never committed or published.
- `CHANGELOG.md` (root) and `docs/changelog.html` (its styled GitHub
  Pages mirror, linked from `docs/index.html`'s nav/footer) must both
  be updated **every time** a phase/feature/fix lands — not deferred
  to release time. Add the entry (Added/Changed/Fixed/Security,
  Keep-a-Changelog style, newest-first) under `## [Unreleased]` in
  `CHANGELOG.md` in the same session the work lands, then mirror the
  same entry into `docs/changelog.html`'s matching `<section
  class="phase">` block (same monochrome style as the rest of `docs/`
  — copy an existing phase block's markup rather than inventing new
  CSS). Both files drifting out of sync with reality is exactly the
  staleness this rule exists to prevent.

## Maintenance contract

When you add/move/delete files another session must find, update
`docs/context/file-map.md`. When a phase opens/closes, update
`docs/context/progress.md`. When you hit or resolve a trap, update
`docs/context/known-issues.md`.
