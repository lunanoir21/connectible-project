# Conventions — "do it this way"

`docs/RULES.md` is the "don't" list; this is the "do" list. Follow
both.

## Language & communication

- Code, comments, commit messages, docs: **English, ASCII only.**
- Conversation with the owner: **Turkish.**
- Doc comments explain *why*/constraints, not what the next line does.

## Git

- **The owner does all commits, tags, and pushes herself.** Never
  commit unless she explicitly asks; never push or tag. The working
  tree routinely carries her uncommitted work — do not stash/clean it.

## Task tracking

- Active roadmap: `docs/TASKS.md`. Audit campaign:
  `docs/TASKS-audit-fixes.md`. Status markers `[ ]` / `[~]` / `[x]`.
- Finish a task -> flip its checkbox in the same session with a short
  **Done** note (what changed, files, proving tests). Deviations,
  accepted gaps, and skipped verifications are written down
  prominently, never silently absorbed.
- Task ids: `T-<phase letter><n>` (`T-J4`, `T-X12`). New phases get
  the next free letter; audit campaign uses the `X` prefix.

## Verification cadence

- While working: `cargo check`, `flutter analyze`,
  `npx tsc --noEmit -p .` — cheap and often.
- At every phase end, the full set:
  - repo root: `cargo test --workspace` and
    `cargo clippy --workspace --all-targets -- -D warnings`
  - `desktop/`: `npx tsc --noEmit -p .` and `npx vitest run`
  - `mobile/`: `flutter analyze` and `flutter test`
- vitest does NOT typecheck (esbuild) — green tests never excuse a
  red `tsc`.
- Tests are ported or deleted with documented reasoning, never
  silently dropped. Real-device-only checks are flagged for the
  owner, not claimed as verified.

## Code patterns to copy

- **Daemon:** typed `Result<T, DaemonError>`, no panics on malformed
  input; new UI-only RPCs get `require_loopback`; unbounded growth is
  a defect — every map/table gets a cap (see `ratelimit.rs`,
  `history.rs::MAX_ROWS`, upload `MAX_TICKETS`).
- **Proto:** removing a field = `reserved` number + name, never
  reuse. After proto changes: daemon regenerates on build; mobile
  needs `./tool/gen_proto.sh` (stubs uncommitted).
- **Desktop:** every UI->Rust call goes through `src/lib/ipc.ts`
  typed wrappers returning `Result`; commands return `CmdError`
  ({code, message}) and the UI renders `errorCodeMessage(code)` —
  never raw gRPC text. New commands: `commands.rs` + register in
  `src-tauri/src/lib.rs` + `ipc.ts` wrapper + types in
  `src/lib/types.ts` (camelCase serde).
- **Mobile:** state = `ChangeNotifier` models wired in
  `app_providers.dart` (constructor injection, `_LazyConnection` for
  cycles); persistence mirrors `DeviceListModel`'s
  shared_preferences JSON pattern (load-on-construct with defensive
  try/catch, save-on-mutation, hard cap).
- **i18n:** any new user-visible string lands in BOTH locales the
  same change (desktop `src/i18n/locales/{en,tr}.json`; mobile
  `lib/src/i18n/strings.dart`). Hardcoded UI English is a defect.

## UI style

- Monochrome black/grey; hairline borders; existing danger red is
  the only accent. Reuse the "tie/star" motif for connection and
  transfer visuals. Match the existing component idioms
  (`desktop/src/components/*`, `mobile/lib/src/widgets/ui.dart`)
  before inventing new ones.

## File placement

- New markdown: under `docs/` (design notes -> `docs/design/`,
  retired plans -> `docs/archive/`, prompts -> `docs/prompts/`).
  Never at repo root. Update `docs/context/file-map.md` when the
  layout changes; update `progress.md` when a phase closes.
