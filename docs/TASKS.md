# Connectible - Hidden Weaknesses: Error Handling, UI Gaps, Message Quality

**Created:** 2026-07-24. Supersedes the previous `docs/TASKS.md` (the
"Road to v1.0.0: Completion Criteria" roadmap, Phases G through N),
archived at
[`TASKS-v1.0-completion-roadmap.md`](archive/TASKS-v1.0-completion-roadmap.md)
— Phases G through M there are all complete; only Phase N (real-device
battery measurement) remains open, re-tracked at the bottom of this
file too so it isn't lost, still parked pending Luna's go-ahead.

## Why this exists

Connectible's automated tests and static analysis have been green for
a while, and the feature-completion roadmap (the archived file above)
is done. That doesn't mean the codebase has no weak points left — it
means the weak points left are the kind tests don't catch: a caught
exception that never reaches a log or a user, an error message that
shows raw Rust/Dart exception text instead of a translated sentence, a
project doc that quietly drifted out of sync with reality. Luna asked
for a dedicated pass over exactly this category — "görünmeyen
zayıflıklar": error handling, UI gaps, error messages.

This file's source material is two investigation passes done
2026-07-24:

1. A full-codebase sweep (grep for `TODO`/`FIXME`/stub markers, plus
   every gap the project's own docs already admit to in plain
   language) — written up in `luna-space/weak-spots-report.html`
   (private, gitignored, not published — see that file for the full
   23-item list with file:line references and direct quotes).
2. A follow-on, more targeted read specifically comparing how desktop
   and mobile surface failures to the user — this is what surfaced the
   concrete finding driving most of the "Error Message Consistency"
   phase below: desktop's `ErrorState` component is disciplined about
   *only* ever showing text from `errorCodeMessage()` (verified: all 6
   of its call sites), while mobile's `PairingModel._setError` shows
   raw, un-localized exception text for every `ErrorCode` except the
   two (`FingerprintChanged`, `PairingRejected`) that got a dedicated
   string during earlier audit work.

Not everything from `luna-space/weak-spots-report.html` is re-tracked
here — this file is scoped to error handling, UI feedback, and message
quality specifically, per Luna's own scoping. The report's other
findings (the accepted corrupted-chunk-resend trade-off, the mobile
TOFU client-cert asymmetry, the permanently-decided QR-parity
asymmetry, and the backlog of real-device-only verifications) are
tracking debt of a different kind — feature completeness and hardware
validation, not error handling/UI — and stay tracked only in that
report and in `docs/context/known-issues.md`'s existing sections, so
they aren't duplicated or allowed to drift into two different states
across two files.

## How to work this file

One phase at a time. Every task is small on purpose: it should be
completable and verifiable on its own. Check a task off only when its
**Acceptance** holds. Keep every stack compiling green after each task.

**Status keys:** `[ ]` todo, `[~]` in progress, `[x]` done, `[-]` cut/skip.
**Field keys:** *Files* = where the work lands; *Depends* = must land first;
*Acceptance* = definition of done.

Task IDs in this file are short mnemonic prefixes tied to the phase
they belong to (`DOC-`, `ERR-`, `MSG-`, `UI-`), not sequential letters
— each phase has a real name, not a letter, since this file tracks a
different kind of work than the completion-criteria roadmap it
replaces.

## Working style (Luna)

- Reply in **Turkish** in chat; keep all code, comments, and docs
  **English/ASCII**.
- Phase-grind: finish a whole phase without asking for per-task
  confirmation; only stop for steps that need a real device, or a
  decision flagged **ASK FIRST**.
- The "Deferred" phase at the end (battery, real-device) stays parked
  — don't start it unprompted.

---

## Phase: Documentation & Diagnostics Accuracy

**Why:** a stale trap-and-dead-end doc is worse than no doc at all —
it sends the next debugging session chasing bugs that are already
fixed. `docs/context/known-issues.md`'s "Open defects (tracked)"
section still lists six issues (T-X1/T-X2/T-X3/T-X5/T-X6/T-X8/T-X9/
T-X20) as open; every one of them is marked `[x]` in
`docs/TASKS-audit-fixes.md`. The file was last touched in the same
commit (`2c959e5`) that opened those issues and never updated once
they closed, even though the working tree has since moved through the
entire G-M roadmap on top of that.

### DOC-1: Rewrite known-issues.md's stale "Open defects" section `[ ]`
Replace the six stale entries with the project's actual current open
items in the same category (error-handling/UI/message-quality gaps
this file tracks, plus anything else genuinely still open — cross-
check against `docs/TASKS-audit-fixes.md` for anything closed and
`luna-space/weak-spots-report.html` bucket A for what's still real).
*Files:* `docs/context/known-issues.md`.
*Acceptance:* every entry in the section names a bug that is
verifiably still open as of the edit (checked against
`TASKS-audit-fixes.md` and this file), not a memory of what used to be
true.

### DOC-2: Re-verify the "Outstanding real-device verifications" section `[ ]`
This section (unlike "Open defects") reads as accurate today — it
already lists T-A25, the multicast-lock confirmation, notification
cancel-on-receipt, Phase N battery, and the mobile image-clipboard
round trip as unconfirmed-on-real-hardware. Confirm each line is still
true (nothing here silently got confirmed on real hardware since
2026-07-23) and fix anything that's drifted.
*Files:* `docs/context/known-issues.md`.
*Depends:* DOC-1 (touching the same file once, not twice).
*Acceptance:* each bullet cites a task id that's genuinely still open;
none reference a task now closed by real-device confirmation.

### DOC-3: Audit docs/design/error-code-mapping.md against both platforms' real code `[ ]`
This doc is the design record for how `ErrorCode` maps to user-facing
text. Given the MSG-phase finding below (mobile doesn't consistently
follow the mapping it's supposed to), check whether the doc itself
still accurately describes both platforms' actual behavior, or whether
it was written assuming parity that was never fully implemented on
mobile.
*Files:* `docs/design/error-code-mapping.md`.
*Depends:* none (can happen before or after the MSG phase; informs it
either way).
*Acceptance:* the doc's description of mobile's error-message path
matches what MSG-1 through MSG-4 either confirm or change it to.

### DOC-4: Add a phase-close reminder to check known-issues.md relevance `[ ]`
DOC-1 happened because nothing in the maintenance workflow forces a
check. `CLAUDE.md`'s maintenance contract already says "when you hit
or resolve a trap, update known-issues.md" — that's necessary but
wasn't sufficient here, since the six stale entries were never
individually "hit" again after being fixed elsewhere. Add one line to
the phase-close verification habit (either in `CLAUDE.md` itself or
this file's own "How to work this file" section, whichever reads more
naturally) prompting a quick skim of known-issues.md's "Open defects"
list against whatever task file just closed a phase.
*Files:* `CLAUDE.md` or `docs/TASKS.md` (this file).
*Depends:* DOC-1.
*Acceptance:* a concrete, short instruction exists somewhere a future
session will actually read at phase-close time — not a vague aspiration.

---

## Phase: Silent & Weak Error Handling

**Why:** every item below is a `catch` block that either does nothing
observable or logs only to a developer console (`debugPrint`), never
reaching a user or a persistent log. None of these are catastrophic on
their own — that's exactly why they survive review — but a Doctor
check that silently swallows its own exception, or a mobile frame
handler with no case at all for an inbound error, are exactly the kind
of gap that turns into a confusing bug report with no trail to follow.

### ERR-1: Mobile SyncStream has no case for an inbound `error` frame `[ ]`
`PairingModel._onInboundFrame`'s frame-kind switch
(`mobile/lib/src/state/pairing_model.dart:561-568`) has no arm for an
`error` payload at all — unlike a unary RPC failure (which throws a
`ConnectibleException` a caller can catch), a protocol-level error
arriving over the open streaming connection is dropped with zero
signal, not even a log line. Already flagged once as a "materially
bigger gap" in `docs/TASKS-audit-fixes.md` T-X33a's own note, but never
opened as its own task.
*Files:* `mobile/lib/src/state/pairing_model.dart`.
*Acceptance:* an inbound `error` frame is at minimum logged
(`debugPrint` or the project's existing logging convention) with its
`ErrorCode` and message; decide during implementation whether it also
warrants a user-visible signal (e.g. the same snackbar path
`_setError` already drives) or whether that's out of scope for a
frame this rare — document the decision either way in the code comment.
*Depends:* MSG-1/MSG-2 land first if the decision above is "make it
user-visible," so the new error frame can use the same localized
mapping instead of introducing a second raw-text path.

### ERR-2: file_transfer_model.dart's nested best-effort cleanup catches `[ ]`
Two spots (`mobile/lib/src/state/file_transfer_model.dart:541-545` and
`:581-585`) wrap `raf?.close()` and a corrupt-partial `File(...).delete()`
in a bare `catch (_) { // best-effort }` with no logging at all —
unlike the outer catches in the same file, which at least
`debugPrint` the exception (see ERR-6). If either of these genuinely
fails, a file handle could stay open or a corrupt partial could stay
on disk to confuse a later resume attempt, and there would be no trace
of it anywhere.
*Files:* `mobile/lib/src/state/file_transfer_model.dart`.
*Acceptance:* both catches log the swallowed exception at minimum;
investigate (don't just log-and-ignore) whether a failed delete of a
corrupt partial should actually block/warn the next resume attempt for
that `file_id`, and either fix it or document why it's safe not to.

### ERR-3: home_screen.dart's local-IP-address lookup catch `[ ]`
`mobile/lib/src/screens/home_screen.dart:1205-1219` wraps local
network-interface enumeration (used to display this phone's own LAN
address) in `catch (_) { ip = null; }` — silent, no log. Low risk
(display-only, already handles the null case gracefully in the UI),
but worth a one-line fix for diagnosability.
*Files:* `mobile/lib/src/screens/home_screen.dart`.
*Acceptance:* the caught exception is logged (`debugPrint`) before
falling back to `null`; UI behavior on failure is unchanged.

### ERR-4: main.dart's device-name fallback catch `[ ]`
`mobile/lib/main.dart:41-49`'s `_defaultDeviceName()` catches every
exception from `Platform.localHostname` and silently falls back to a
hardcoded `'Connectible Phone'`. Same shape as ERR-3: low risk, but a
platform-hostname failure mode is currently untraceable.
*Files:* `mobile/lib/main.dart`.
*Acceptance:* the caught exception is logged before falling back;
fallback behavior is unchanged.

### ERR-5: doctor/checks.dart's swallowed exception inside a Doctor check `[ ]`
`mobile/lib/src/services/doctor/checks.dart:121` has a `catch (_)`
inside a System Doctor check. This one is more important than ERR-3/
ERR-4's UI-cosmetic catches: the entire point of a diagnostic check is
to surface problems, so an exception inside the check itself failing
silently could hide the exact class of problem the check exists to
catch, and the user sees either a false "ok" or a generic failure with
no explanation.
*Files:* `mobile/lib/src/services/doctor/checks.dart`.
*Acceptance:* identify which check this is and what triggers the
catch; the check either surfaces a `warn`-level result explaining what
went wrong (matching every other check's existing pattern in this
file) instead of silently passing, or the catch is proven genuinely
unreachable/inconsequential and left with a comment explaining why —
not fixed blindly without understanding what it's guarding against
first.

### ERR-6: Sweep file_transfer_model.dart's debugPrint-only catches for resume-safety `[ ]`
Beyond ERR-2's two silent catches, the same file has several more
(`:75`, `:226`, `:262`, `:359`, `:533`, `:635`) that at least
`debugPrint` the exception before recovering — better than silent, but
still dev-console-only, never reaching a log a real user's bug report
could include. Read each one specifically for whether the recovery
path is actually safe for the resume/dedup logic described elsewhere
in this file (the `file_id` determinism comments), not just whether it
avoids crashing.
*Files:* `mobile/lib/src/state/file_transfer_model.dart`.
*Depends:* ERR-2 (same file, same read-through).
*Acceptance:* a short written note (in this task's Done entry once
complete) confirming each of the six catches either has no
resume-safety implication, or gets a fix alongside ERR-2's.

---

## Phase: Error Message Consistency & Quality

**Why:** desktop is disciplined here by construction — `ErrorState.tsx`'s
own doc comment says message text "must come from errorCodeMessage(),
never a raw error string," and all 6 of its real call sites
(`ClipboardPanel`, `NotificationsPanel`, `TransferPanel`, `HomePanel`,
`DeviceListPanel`, `RemoteInputPanel`) actually do this — verified by
reading each, not assumed. Mobile has no equivalent mapping at all:
`PairingModel._setError` shows `ConnectibleException.message` (raw
peer/transport text) directly for every `ErrorCode` except the two
that earned a dedicated string during earlier audit work
(`FingerprintChangedException`, and the literal string `'Pairing was
rejected'` for a rejection). Worse, the outermost bare `catch (e)` at
`pairing_model.dart:459-461` shows `'$e'` — Dart's raw exception
`toString()`, which can include things like
`SocketException: Connection refused (OS Error: Connection refused,
errno = 111), address = ..., port = ...` verbatim to a Turkish-reading
user.

### MSG-1: Design a mobile ErrorCode -> localized message mapping `[ ]`
Mirror `desktop/src/lib/errors.ts`'s shape: a `Map`/`switch` from each
`pb.ErrorCode` variant to a `strings.dart` i18n key, with a documented
fallback for `ERROR_CODE_UNSPECIFIED` (mirrors desktop's
`errors.unspecified`). Decide what to do with the raw peer `message`
text desktop currently discards entirely in favor of the mapped
string — desktop's own precedent is "never a raw error string," so
default to matching that unless there's a concrete case where the
peer's specific text is more useful than a curated one (e.g. surfacing
it only in a debug/detail view, never as the primary message).
*Files:* design notes can live in this task's Done entry; no doc file
needed for a decision this scoped (matching how T-L1 in the archived
roadmap handled a similarly small scope decision).
*Acceptance:* a clear mapping table (ErrorCode -> i18n key) written
down before MSG-2 starts implementing it.

### MSG-2: Implement the mapping + i18n keys `[ ]`
New keys under both `en` and `tr` in `mobile/lib/src/i18n/strings.dart`
for every `ErrorCode` not already covered (`UNAUTHENTICATED`,
`DEVICE_NOT_FOUND`, `FILE_TRANSFER_FAILED`, `CHECKSUM_MISMATCH`,
`UNSUPPORTED_PLATFORM`, `INTERNAL`, `PROTOCOL_VERSION_MISMATCH`,
`RATE_LIMITED`, `UNSPECIFIED`); a new function (e.g.
`connectibleExceptionMessage(ConnectibleException, Strings)`) that maps
each exception's `.code` to the right translated string, matching
desktop's `errorCodeMessage()` signature/shape as closely as Dart
idiom allows.
*Files:* `mobile/lib/src/i18n/strings.dart`, new or existing service
file (e.g. alongside `connectible_exception.dart`).
*Depends:* MSG-1.
*Acceptance:* key-set parity between `en`/`tr` (same enforcement style
already used elsewhere in this file — a compile-time `keyof`-equivalent
check or an explicit test, matching the project's existing convention).

### MSG-3: Wire PairingModel's generic ConnectibleException branch through it `[ ]`
`pairing_model.dart:455-458`'s `on ConnectibleException catch (e)`
branch (both occurrences, lines ~455 and ~507) currently calls
`_setError(e.message)`. Route it through MSG-2's new mapper instead,
keeping the existing dedicated `FingerprintChangedException` and
rejection-string branches as-is (they're already correct).
*Files:* `mobile/lib/src/state/pairing_model.dart`.
*Depends:* MSG-2.
*Acceptance:* a widget/unit test drives each `ErrorCode` through
`PairingModel` and asserts `lastError` is the translated string, not
the raw peer message; existing fingerprint-changed/rejected tests
still pass unmodified.

### MSG-4: Replace the bare `catch (e) { _setError('$e'); }` fallback `[ ]`
`pairing_model.dart:459-461` — the outermost catch, reached when a
failure never made it to the proto layer at all (DNS/socket/TLS/decode
errors). These have no `ErrorCode` to map, so MSG-2's mapper doesn't
directly apply; decide on a generic, translated "couldn't connect"-
style message (matching desktop's `UNSPECIFIED`/connection-failure
handling for the analogous case) instead of the raw Dart exception
string, while keeping enough detail server-side/logged (`debugPrint`)
for debugging.
*Files:* `mobile/lib/src/state/pairing_model.dart`,
`mobile/lib/src/i18n/strings.dart`.
*Depends:* MSG-1 (the fallback-message decision belongs in the same
design pass).
*Acceptance:* a real socket-level failure (test via an unreachable
address) shows the new translated generic message in `lastError`, and
the original exception text is still visible in logs for debugging.

### MSG-5: Tests for the new mapping `[ ]`
Mirror `desktop/src/lib/errors.test.ts`'s coverage shape: every
`ErrorCode` maps to a non-empty, correctly-keyed string in both
languages; an unrecognized/future code falls back to the `UNSPECIFIED`
path instead of throwing.
*Files:* new `mobile/test/.../connectible_exception_test.dart` or
alongside existing `pairing_model_test.dart` coverage (whichever this
project's existing test-file convention favors — check how
`errors.test.ts` is organized relative to `errors.ts` on desktop for
the precedent).
*Depends:* MSG-2, MSG-3, MSG-4.
*Acceptance:* `flutter test` green with the new cases included.

### MSG-6: Update docs/design/error-code-mapping.md for accuracy `[ ]`
Once MSG-1 through MSG-5 land, the doc's description of mobile's
behavior needs to match reality (see DOC-3, which may have already
flagged the specific stale claims).
*Files:* `docs/design/error-code-mapping.md`.
*Depends:* MSG-2 through MSG-5 (describe what actually shipped, not
the plan).
*Acceptance:* the doc accurately describes both platforms' mapping
behavior as implemented, including the MSG-4 fallback-message decision.

---

## Phase: UI Feedback Completeness Audit

**Why:** the MSG phase above was found by checking one specific path
(pairing errors) closely. This phase is the broader sweep — confirming
(or fixing) that the same discipline holds everywhere else, on both
platforms, rather than assuming the one gap found is the only one.

### UI-1: Confirm every mobile screen's error-surfacing path `[ ]`
`mobile/lib/src/screens/{pair_scan,remote_input,clipboard,transfers,home}_screen.dart`
each use some error/empty-state widget from `mobile/lib/src/widgets/ui.dart`.
A targeted grep during this file's own investigation found no direct
`$e`/`.toString()` leaks into any screen's visible `Text`/`SnackBar`
content outside of `PairingModel` — confirm that holds for real by
reading each screen's actual error-display call sites (not just
grepping for the obvious patterns), since MSG's fix only touches
`PairingModel`; `ClipboardModel`, `FileTransferModel`, and
`DeviceListModel` each have their own error paths that weren't part of
this investigation's close read.
*Files:* the five screen files above, plus
`mobile/lib/src/state/{clipboard_model,file_transfer_model,device_list_model}.dart`.
*Acceptance:* a written account (in this task's Done entry) of every
error-display call site found, confirming each shows curated/localized
text — or a new task opened per gap found, same shape as the MSG phase.

### UI-2: Regression-guard desktop's ErrorState discipline `[ ]`
Desktop's "always route through errorCodeMessage()" convention is
currently upheld by discipline and a doc comment, not by a lint rule
or test. Add a lightweight guard (a test asserting no component passes
a non-`errorCodeMessage()`-derived string to `ErrorState`'s `message`
prop, or — simpler — a code-review-time grep documented in
`docs/RULES.md`/`docs/context/conventions.md` if a real automated
check isn't practical) so a future panel doesn't quietly reintroduce a
raw string the way mobile's pairing path did.
*Files:* `desktop/src/components/ErrorState.tsx` and/or
`docs/context/conventions.md`.
*Acceptance:* either a passing test that would fail if a future
`<ErrorState message={someRawString}>` landed, or (if that's not
practical without real static analysis) a clearly written convention
note a reviewer would actually check against.

### UI-3: Decide the UX for truly-unclassified transport failures `[ ]` **ASK FIRST**
MSG-4 picks a generic message for mobile's socket/DNS/TLS-layer
failures with no `ErrorCode`. Desktop likely has the same category of
failure (a `RemoteDeviceClient` call that never reaches the daemon at
all) — confirm how desktop currently handles it, and decide (with
Luna, since this is a real UX call, not a mechanical fix) whether both
platforms should converge on the same generic phrasing/behavior, or
whether platform-specific wording is fine as long as neither shows raw
exception text.
*Files:* investigation + design decision; implementation files depend
on the decision.
*Depends:* MSG-4 (need to see mobile's chosen wording first for a
real side-by-side comparison).
*Acceptance:* a decision recorded (matching how T-L1/T-M8 recorded
their scope/policy decisions in the archived roadmap file), then
implemented consistently on whichever platform(s) it applies to.

### UI-4: Decide whether a failed-transfer row needs a visible reason `[ ]`
Checked directly: both platforms already show only a generic
localized "Failed" status on a failed transfer row today (desktop:
`transfers.statusFailed` via `statusLabel()`; mobile: the underlying
exception is `debugPrint`-only, never reaching the row itself) — this
is symmetric, existing, intentional-looking behavior, not a newly
found asymmetry. Worth one explicit decision task rather than silently
leaving it alone: is "Failed" alone sufficient (current behavior,
consistent with the project's general aversion to raw error text), or
does a tap-to-expand/subtitle reason add real value without
reintroducing raw text? If the latter, it would need the same
ErrorCode-mapped-message discipline as the rest of this phase, not a
regression back to showing something raw.
*Files:* `desktop/src/components/TransferPanel.tsx`,
`mobile/lib/src/state/file_transfer_model.dart`,
`mobile/lib/src/screens/transfers_screen.dart`.
*Acceptance:* a decision recorded either way; if "add detail," a
follow-up task opened with the same rigor as the MSG phase rather than
implemented ad hoc inside this task.

---

## Deferred

### T-N1: Real-device battery impact measurement `[ ]`
Re-tracked from the archived roadmap file purely so it isn't lost —
**do not start without Luna's explicit go-ahead.** Run the mobile app
with an active paired session over several hours on a real Android
phone; compare battery drain against a baseline (app not running, or
running without an active sync session). Full protocol:
`docs/design/battery-measurement.md`; helper script:
`mobile/tool/battery_measure.sh start|stop <label>`.
*Files:* n/a (measurement task; results recorded in this file once done).
*Depends:* Luna's go-ahead.
*Acceptance:* a written measurement (not a pass/fail guess) showing
the drain is within a reasonable margin of the baseline, or a concrete
follow-up task opened if it isn't. See
`archive/TASKS-v1.0-completion-roadmap.md`'s own T-N1 entry for the
prior session's progress note (tooling prepared, no phone was attached
that session).

---

## Phase order and dependencies

Documentation & Diagnostics Accuracy has no code dependency on the
other phases and can run first or in parallel — DOC-3 specifically
benefits from running *after* the Error Message Consistency phase
lands (so it documents what actually shipped), but can also run first
as a "here's what the doc currently claims" baseline. Silent & Weak
Error Handling is independent of Error Message Consistency except for
ERR-1, which should land after MSG-1/MSG-2 if the "make it
user-visible" branch is chosen. UI Feedback Completeness Audit is
last on purpose — UI-1 and UI-2 are cheapest to run once the Error
Message Consistency phase has actually changed the code they're
auditing, and UI-3/UI-4 explicitly depend on decisions made during
that phase. The Deferred section stays parked regardless of ordering.
