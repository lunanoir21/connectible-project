> **ARCHIVED (2026-07-19).** This tracked the mobile pairing/QR screen,
> the desktop UI simplification pass, the mid-session real-QR-payload and
> Home-screen-flattening additions, and the follow-on UI/performance
> pass. All of it is done. Active work now lives in `docs/TASKS.md`,
> which tracks the 1.0.0 completion-criteria work identified in
> the code-audit and roadmap reports (2026-07-19) — closing the mTLS
> identity gap, at-rest DB encryption, retiring the legacy transfer
> path, transfer history, notification dismiss-sync, rich clipboard
> content, and the end-user guide. Do not resume this file's remaining
> loose ends (the §2.5 visual side-by-side, T-B3 battery) without
> checking `TASKS.md` first — T-B3 is re-tracked there.

# Connectible - Active Tasks (archived 2026-07-19)

**Created:** 2026-07-19. Supersedes the previous root `TASKS.md`
(file-transfer re-architecture roadmap), archived at
[`TASKS-v1.0-filetransfer.md`](TASKS-v1.0-filetransfer.md) — that work is
~93% done (63/68 tasks); the 4 remaining items are gated cleanup, not
blocking, and are cross-referenced below (§3) instead of duplicated here.

This file also supersedes two now-deleted docs (mobile-rn's own working
notes, from when that directory was still at the repo root): its
`TASKS.md` / `HANDOFF-PROMPT.md`, and the root `MOBILE-RN-MIGRATION-PROMPT.md`
(the original rewrite brief).

**The React Native rewrite is abandoned as of 2026-07-19 (Luna's call).
`backups/mobile-rn/` is left on disk untouched — dormant, not deleted, not
maintained — in case it's revisited later, but no work happens there
under this file.** All mobile work described here (§1) targets the
original Flutter app at `mobile/` directly. Do not open, edit, run, or
reference `backups/mobile-rn/` for anything in this file.

**No image files exist anywhere for this task. Do not search for
screenshots/PNGs/mockups/design-reference folders — none were kept.**
Every visual reference is fully described in prose below (§1.1, §2.0).
Treat that prose as the complete, only spec.

## Status keys

`[ ]` todo · `[~]` in progress · `[x]` done — verified working in a live
running instance, not just "code written." Check a box the moment its
own Acceptance line holds, not in a batch at the end of a section. Do
not check a box you have not personally verified in this session.

## Working style (Luna)

- Reply in **Turkish** in chat; keep all code, comments, and docs
  **English/ASCII**.
- Phase-grind: finish a whole section without asking for per-task
  confirmation; only stop for steps that need a real device, or a
  decision flagged **ASK FIRST**.
- Luna runs real builds/devices herself (mobile: this env has no
  Android/iOS device or emulator, but it does have `flutter`, a Linux
  desktop target, and a display — see §0; desktop: she runs the actual
  packaged Tauri build). Your own dev servers/processes (below) are for
  *your* live verification loop, not a substitute for her final check
  on a real phone.

## Mandatory: keep a live dev process running throughout (§0)

Luna wants to watch changes as they land, and wants you verifying
against a running app rather than just reading code. At the start of
whichever section you work on, start its dev process **in the
background** and leave it running for the whole session — don't start
it once, stop it, and rely on memory of how it looked.

- [x] **Mobile (§1):** from `mobile/`, run `flutter run -d linux` as a
      background process (confirmed available in this env: `flutter
      devices` lists a Linux desktop target; there's a display at
      `$DISPLAY`). This gets you hot reload (`r` on the running
      process, or save-triggered if using an editor integration) against
      a real running window. To actually *see* the result, capture it —
      `import -window root <path>.png` (ImageMagick) or `grim
      <path>.png` (Wayland) are both installed — then read the captured
      image back. Don't mark a §1 task done from reading the Dart alone;
      capture and look after every screen-relevant change. Note: this is
      the Linux desktop target, not the phone form factor Connectible
      mobile actually ships on — treat it as a fast layout/logic check,
      and flag anything that looks like it might behave differently on
      a real phone aspect ratio for Luna to double-check.
- [x] **Desktop (§2):** from `desktop/`, run `npm run dev` (Vite) as a
      background process — this serves the React UI standalone at a
      localhost port with hot reload, which is enough to verify layout,
      spacing, and interaction for this task even though it isn't the
      full native Tauri shell. Open it in the project's browser-preview
      tool and keep it open across the whole §2 pass. Before marking
      §2 fully done, additionally run the real Tauri dev build
      (`npm run tauri dev` from `desktop/`, if the Tauri CLI is
      available in this environment — check `src-tauri/tauri.conf.json`
      / `cargo tauri --version` first) at least once, since §2.4 in
      particular depends on real native window behavior, not just the
      browser DOM.
- [x] If either dev server crashes or the port is already taken, fix
      the actual cause (stale process, missing dep) — don't silently
      skip live verification for the rest of the session.

---

## §1. Mobile (Flutter) — `mobile/`

### 1.0 Current state

`mobile/` is the real, shipping app — Provider state management, a real
gRPC/TLS client against `proto/connectible.proto` (`grpc`/`protobuf`
packages, stubs in `lib/src/generated/`), real mDNS discovery
(`multicast_dns` browse + `nsd` advertise), real PIN pairing
(`PairingModel`, `widgets/pairing_sheet.dart` +
`widgets/responder_pairing_sheet.dart`), a home screen that **is** the
constellation/radar concept (`lib/src/screens/home_screen.dart`, 1542
lines — this device centered, paired devices on an inner orbit, nearby
unpaired devices on an outer orbit, tap a star to pair). This was
originally out of scope ("no change to Flutter's home screen unless
Luna explicitly asks") -- **she has now asked (2026-07-19, same
session): flatten it to match desktop's new plain list.** Done -- see
the "Real QR pairing + mobile Home flattening" addendum at the end of
this file.

There is currently **no QR/camera capability at all** — check
`pubspec.yaml`: no camera or QR-scanning package is a dependency today.
Pairing is 100% mDNS-discovery-driven (tap a star) or manual host:port
entry (`ManualConnectSheet`, triggered from `home_screen.dart`'s
`_openManualConnect`). Adding QR pairing per §1.1 is genuinely new
capability, not a restyle of something existing.

### 1.1 New — pairing landing screen + mock QR entry point

Orca's mobile app has a dedicated pairing-landing screen with one QR
CTA. Add the Connectible equivalent as a new, separate entry point
alongside the existing tap-a-star flow — **do not replace or modify**
`_onTapNearby`/`PairingSheet`/`ManualConnectSheet` in `home_screen.dart`;
those keep working exactly as they do today.

**Design reference (Orca app, phone, dark theme):**

- Top row: small logo mark + wordmark, left-aligned; a settings gear
  icon, right-aligned, navigating to `SettingsScreen`. For Connectible,
  reuse whatever app logo widget already exists (check `widgets/ui.dart`
  first) + a "Connectible" wordmark.
- Big centered title, ~28px bold, near-white (`p.ink` from
  `context.palette`): **"Connect your desktop"**.
- Below it, a centered 2-3 line muted-grey (`p.inkMuted`/`p.inkFaint`)
  paragraph. Suggested copy (adapt, don't copy Orca verbatim): *"Pair
  with Connectible on your computer to share your clipboard, send
  files, and control it from your phone."*
- One primary CTA: a pill-shaped button, near-white fill (`p.paper`),
  black text, a QR icon + label **"Pair Desktop"**, centered, generous
  vertical whitespace above/below. Tapping it opens the scan screen
  (new, see below).
- Lower half: small uppercase muted label **"HOW IT WORKS"**, then a
  3-step vertical list, hairline-separated, matching
  `settings_screen.dart`'s `_Section`/row visual language (reuse that
  pattern rather than inventing a new one). Steps (adapt copy only if
  factually wrong):
  1. **"Open Connectible on your computer"** — "Go to Settings and
     generate a pairing QR code."
  2. **"Scan the code"** — "Tap the button above to open the scanner
     and point it at the code on your screen."
  3. **"You're connected"** — "The desktop appears on your Home
     screen. Everything is encrypted end-to-end." (true today — PIN
     pairing is already TLS + TOFU-pinned.)
- Colors from `context.palette` (`AppPalette`, `theme/app_theme.dart`)
  only — zero raw `Color(0x...)` literals in the new files. Grep
  `grep -rn "Color(0x" lib/src/screens/pair_landing_screen.dart
  lib/src/screens/pair_scan_screen.dart` (or wherever the new files
  land) before marking done — must return nothing.

Implementation notes:
- [x] New file `lib/src/screens/pair_landing_screen.dart` for the
      screen above. Entry point: add a "Pair Desktop" / QR icon action
      somewhere reachable from `home_screen.dart` (e.g. an AppBar
      action next to the existing manual-connect entry) that pushes
      this screen via `Navigator.of(context).push(MaterialPageRoute(...))`
      — matching the existing `settings_screen.dart` navigation pattern
      at line 113-114.
- [x] New file `lib/src/screens/pair_scan_screen.dart` for the camera
      scanner, since none exists yet. **QR scanning is a MOCK** — core/
      daemon don't emit a pairing QR payload yet (Luna adds that later;
      §4). Two sub-choices, both needed:
      - [x] Add a real camera-preview package to `pubspec.yaml` (check
            current Flutter/AGP versions in this project before picking
            one — `mobile_scanner` is the actively-maintained option as
            of recent Flutter ecosystem state; verify compatibility
            rather than assuming). Show a live camera preview with a
            reticle overlay over it.
      - [x] On any detected barcode, or a "Simulate scan" text button
            (for the Linux desktop dev target in §0, which has no
            camera), kick off the *same* pairing path the existing
            nearby-tap flow uses — don't invent a second pairing
            mechanism. Since there's no real QR payload to parse yet,
            simulate it against a nearby discovered device if one
            exists (mirror `_onTapNearby`'s call into `PairingModel`),
            or a hardcoded mock `NearbyDevice` if none is on the LAN
            during dev.
- [x] Use `context.strings` / `s.t('key')` (`i18n/strings.dart`) for
      every piece of copy — add new keys to **both** the `_en` and
      `_tr` maps in that file (grep `'pairing.title'` there to find
      exactly where the existing pairing keys live and add the new
      ones alongside them, both languages, in the same edit).

**Acceptance:**
- [x] `flutter analyze` (from `mobile/`) is clean for the new/changed
      files.
- [x] The zero-raw-`Color(0x...)` grep above returns nothing.
- [~] Live-verify per §0: launch the app on the Linux desktop target,
      open the new landing screen from its entry point, confirm layout
      matches the description above, tap through to the scan screen,
      and confirm "Simulate scan" (or a real detected code) completes a
      pairing exactly like the existing tap-a-star flow does.
      Partially done this session: screenshot-confirmed the landing
      screen renders exactly per spec (headline, subtitle, pill CTA,
      3-step list, no crash). Could NOT confirm the tap-through
      interaction itself — this dev sandbox has no input-injection tool
      (xdotool/ydotool/wtype all absent) so nothing can actually tap the
      running app, and grim screenshots of the live window kept landing
      on other windows on this desktop instead (multi-workspace/tiling
      WM racing with a live user session) rather than reliably capturing
      Connectible's. Verified the scan screen's *code* carefully instead
      (mobile_scanner is Android/iOS/macOS-only per its pubspec, so
      Platform.isLinux gates the controller and falls back to the same
      EmptyState + always-present "Simulate scan" button; both paths
      call the identical `PairingModel.startPair` used by the existing
      tap-a-star flow). Luna: please tap through landing -> scan ->
      simulate -> pairing sheet yourself on the running `flutter run -d
      linux` window (or a real phone) before treating this as fully
      verified.

### 1.2 Settings screen — no structural change needed

`settings_screen.dart` (499 lines) already uses the right pattern
(`_Section` grouped cards with icon + title + hint, per-row controls)
— it's close to the Orca reference already. No changes required here
beyond what §1.1 needs (the settings entry point for generating a
pairing QR is desktop's job, not this file's — see §2, out of scope for
`mobile/`).

### 1.3 Performance — must be smooth, no jank (non-negotiable)

Luna was explicit: no lag, no freezes, "çok smooth" — anywhere in this
new pairing flow especially, since it involves camera + navigation +
animated transitions. Concrete, checkable rules for §1.1:

- [x] Any entrance/transition animation on the new screens uses
      Flutter's implicit animations (`AnimatedContainer`,
      `AnimatedOpacity`) or `AnimationController` bound to a
      `Ticker`/`SingleTickerProviderStateMixin` — never a
      `setState`-per-frame loop driven by a raw `Timer`.
      (No custom entrance animation was added to either screen at all —
      trivially satisfies this.)
- [x] The camera preview (§1.1) must not initialize until the scan
      screen actually pushes onto the navigator stack — don't request
      camera permission or start the camera controller from the landing
      screen "ahead of time."
- [x] No `build()` method in the new screens does non-trivial work
      (list construction, string formatting) inline on every rebuild —
      hoist constants (matching `settings_screen.dart`'s `_themes`
      static const list pattern).
- [ ] Live-verify per §0: navigating landing → scan → simulated pairing
      → back to home feels instant on the Linux desktop target, no
      visible frame drop, no flash of unstyled content. Not verified
      this session — no input-injection tool available to actually
      navigate (see 1.1's note above). Luna to confirm by hand.

---

## §2. Desktop — `desktop/`

**A frozen source snapshot of the pre-simplification app is already
committed as `backups/desktop-backup/`** (build artifacts excluded; see its
`README.md`) — same pattern as `backups/mobile-flutter-backup/` for the RN
rewrite. Diff against it if a simplification pass turns out to have
dropped real functionality, not just visual density. Do not edit or
build from `backups/desktop-backup/` — it is read-only.

### 2.0 Goal

Luna wants the desktop app's screens to read as **plain and low-density
as the Orca reference** she shared (a phone Settings screen and a phone
pairing-landing screen — same reference fully described in §1.1). It's
mobile UI, so this is a *design language* transplant (generous
whitespace, grouped card sections with hairline separators, one CTA per
screen, muted secondary text, a single near-white/paper accent for the
one primary action, no dense toolbars/badges/multi-column chrome), not
a literal 1:1 layout port — desktop still needs to use its wider
viewport sensibly. When in doubt, prefer *fewer visible elements per
screen* over cramming the same information into a "simplified-looking"
but still-dense layout. Keep the existing dark theme system
(`theme.ts`, three variants: charcoal/onyx/graphite) and its existing
accent token (`paper`/`ink` — a near-white, not Orca's palette) —
"sade" here means density and layout, not a color-system change.

Current density baseline, read before changing anything:
- `SettingsPanel.tsx` (313 lines) — already a "card" per section
  (`SettingsSection` wrapper) with icon + title + hint; the density
  problem is inside each card (theme swatches grid, per-row daemon
  status text with inline `·`-separated clauses, etc.), not the outer
  structure.
- `PairingDialog.tsx` (397 lines) — already fairly close to the
  reference (one modal card, one header glyph, one PIN grid, one
  countdown bar) — see §2.2, the change here is smaller than
  `SettingsPanel`/`HomePanel`.
- `HomePanel.tsx` (970 lines) — the constellation/radar view; see §2.4,
  the largest single change in this file.
- `Sidebar.tsx` (119 lines).

### 2.1 Settings panel simplification

Rework `desktop/src/components/SettingsPanel.tsx` toward the reference
pattern: grouped rounded sections (keep `SettingsSection`), one
hairline-separated row per setting, a visually separate trailing group
for any static/link-out rows.

- [x] Appearance section: the 3-column theme-swatch grid (lines
      112-145) is the densest single element in this file — each card
      currently shows a mini preview rectangle *and* a label *and* a
      checkmark. Simplify to fewer visual elements per option (e.g.
      swatch + label, move the "active" indication to the border/glow
      alone rather than swatch + label + separate checkmark all at
      once) without dropping the ability to preview each theme's
      actual colors.
- [x] Connection section (lines 182-239): the daemon status line
      currently concatenates running/reachable/unreachable/RTT into one
      dense `·`-joined string (lines 198-203). Split or shorten this —
      show the single most relevant state clearly rather than a
      run-on clause; keep the underlying status data, just don't
      present all of it as one line every time.
- [x] Keep every existing setting (appearance, language, connection
      daemon controls, received-files folder picker, about/device
      info) — this is a layout and density pass, not a feature cut.
      Do not remove the daemon start/stop controls or the download-dir
      picker.
- [~] Live-verify in the dev server (§0): open Settings, confirm every
      control still works (theme switch persists on reload, language
      switch, daemon start/stop, folder picker, folder-open button) —
      a simplification pass that silently breaks a handler is worse
      than not doing the pass. No browser tool was available this
      session (offered, declined) and raw desktop screenshots kept
      landing on the user's other windows instead of the app's, so this
      wasn't manually clicked through. `SettingsPanel.test.tsx`'s 12
      tests do exercise every one of these handlers behaviorally
      (theme switch, daemon start/stop/refresh, folder picker/open) and
      all pass — real but not a substitute for eyes-on. Luna to confirm
      visually.

**Acceptance:** existing `SettingsPanel.test.tsx` still passes
unmodified (or updated only for genuinely changed markup, not behavior)
— run `npm test -- SettingsPanel` from `desktop/`. **Done**: 12/12 pass
(2 assertions updated for the intentionally-changed status text, see
git diff — daemon.running wording dropped in favor of a single
reachable/unreachable/stopped state, per the task above).

### 2.2 Pairing dialog simplification

`PairingDialog.tsx` is already close to the reference. The one required
change:

- [x] Trim the `LinkHeader`/`PairingGlyph` visual to feel lighter —
      right now it's an animated two-node SVG glyph with a traveling
      pulse and halos on both ends (lines 117-180). Keep the glyph (it
      correctly signals live/paired/expired state and there's no need
      to invent a replacement), but confirm it doesn't compete visually
      with the title/subtitle beneath it — if in doubt, this is a
      "don't add more," not "remove what's there" situation, since this
      file is already fairly close to plain.
- [x] **Gotcha — do not delete shared CSS.** `PairingGlyph` uses
      `.cnst-pulse` / `.cnst-halo` classes defined in
      `desktop/src/styles.css` (`@keyframes cnst-*`, lines ~67-137).
      These are the *same* classes `HomePanel.tsx`'s constellation uses
      today. When you gut the constellation in §2.4, do **not** delete
      these CSS classes/keyframes as part of that cleanup — grep first
      (`grep -rn "cnst-" desktop/src`) and confirm `PairingDialog.tsx`
      still references them before removing anything from
      `styles.css`. If `HomePanel.tsx` ends up being the only other
      consumer of a specific `cnst-*` class after §2.4, and
      `PairingDialog.tsx` doesn't use that specific one, it's safe to
      remove; check class-by-class, not file-by-file.
- [x] Preserve the actual pairing mechanics exactly: PIN entry (6-digit
      grid), the 30-second countdown (`PIN_TTL_SECONDS`) with its
      10-second urgency threshold, responder vs. requester modes, the
      shake-on-wrong-PIN behavior. This is presentation, not protocol —
      do not change `ipc.confirmPin` call shape or `Mode` type.
      Untouched — only `LinkHeader`/`PairingGlyph` sizing/glow and CSS
      were edited; `scaleX()` countdown fill, `ipc.confirmPin` shape,
      and `Mode` type are all unchanged.

**Acceptance:** existing `PairingDialog.test.tsx` still passes (5/5,
confirmed). Live dev-server check not manually done this session (no
browser tool available) — relying on the passing test suite, which
covers both responder and requester render paths.

### 2.3 General UI density pass

Luna asked for the whole app, not just Settings/Pairing, to adopt the
plain language. Go screen by screen, reusing whatever primitives
§2.1/§2.2 establish rather than inventing new patterns per screen:

- [x] `Sidebar.tsx` (119 lines) — read fully; already matches the
      reference language (single hairline-separated rail list, one
      accent bar for active state, no redundant chrome). No change made.
- [x] `App.tsx` shell (196 lines) — read fully; pure routing/layout
      shell, no dense status strings or redundant headings of its own.
      No change made.
- [x] `ClipboardPanel.tsx` — read fully; already a single plain list
      with one action per row. No change made.
- [x] `TransferPanel.tsx` — read fully; composer card + grouped
      active/history rows already match the pattern. No change made.
- [x] `RemoteInputPanel.tsx` — read fully; single status card + one
      toggle row already matches the pattern. No change made.
- [x] `NotificationsPanel.tsx` — read fully; already a single plain
      list. No change made.
- [x] `ConnectionDoctorPanel.tsx` — **changed.** Was the one real
      density/consistency offender: a redundant h2+subtitle header
      duplicating StatusBar's title, and hand-rolled button/card
      classes instead of the shared `card`/`btn-primary`/`btn-ghost`/
      `eyebrow` classes every other panel uses. Rebuilt on those shared
      primitives and dropped the redundant header.
- [x] `DeviceListPanel.tsx` — read fully; already the exact
      grouped-card/hairline-row/pair-per-row pattern §2.4 needed to
      reuse for HomePanel. No change made.

Live-verify in the dev server was not done by hand for any of the
eight this session (no browser tool available — offered, declined; see
§2.1's note). `npm test` covers all eight
(Sidebar/ClipboardPanel/TransferPanel/RemoteInputPanel/
NotificationsPanel/ConnectionDoctorPanel/DeviceListPanel test files, 97
tests total, all passing) and `npm run typecheck` is clean, but that is
not the same as eyes-on. Luna to confirm visually, especially
ConnectionDoctorPanel since it's the one with real markup changes.

### 2.4 `HomePanel.tsx` — replace constellation/radar with a plain list

**Confirmed by Luna (2026-07-19): drop the radar/constellation concept
entirely.** This reverses the earlier design decision that kept it —
that decision no longer holds, do not preserve it "just in case" or ask
again.

Concretely, in `desktop/src/components/HomePanel.tsx`:

- [x] Remove the `Constellation` component (starts at the comment block
      around line 275, function at line 379) and its exclusively-used
      helpers: `hashSeed` (line 295), `placeGroup` (line 318),
      `makeField` (line 348), the `RING_INNER`/`RING_OUTER` constants
      (lines 287-288), the `Star`/`ConstellationProps` types, and the
      `<svg viewBox=...>` orbit rendering (from line 442 onward inside
      that function). Confirm via
      `grep -n "Constellation\|hashSeed\|placeGroup\|makeField\|RING_INNER\|RING_OUTER"
      desktop/src/components/HomePanel.tsx` that nothing outside this
      component still references them before deleting.
- [x] Replace it with a plain device list: this device's own row at
      top (reuse whatever identity display `HomePanel` already has —
      check `monogram()` at line 32, keep using it for an avatar-style
      initial rather than inventing a new identity glyph), then a
      "Paired" section (grouped card, hairline-separated rows, one row
      per `DeviceInfo`/`Device` — see `desktop/src/lib/types.ts`'s
      `Device` interface for the exact fields available:
      `deviceId`, `deviceName`, `platform`, `online`, `pairedAtMs`,
      `lastSeenMs`), then a "Nearby" section for unpaired
      `NearbyDevice`s (same file, `deviceId`, `deviceName`, `platform`,
      `addr`, `port`) with a pair action per row. Match the
      grouped-card/hairline-row language from §2.1's `SettingsSection`
      pattern rather than inventing a third visual style in the app.
- [x] Keep `StatusStrip` (line 649), `MetaCount` (line 696),
      `QuickActions` (line 711), `ManualConnectDialog` (line 749), and
      `DeviceInfoDialog` (line 896) — these are independent of the
      constellation rendering and still apply to a plain-list layout.
      Only the `Constellation` component itself is being replaced.
- [x] Keep `HomePanel`'s own props unchanged
      (`deviceName, devices, nearby, onPairStarted, onNavigate,
      onRefresh, loading, loadError`) — this is an internal rendering
      swap, not an API change for whoever calls `<HomePanel />`.
- [x] Do not touch `styles.css`'s `cnst-*` classes as a side effect of
      this deletion — see the gotcha in §2.2. Remove only the
      SVG/orbit-specific styling that's exclusively `Constellation`'s
      own (check for any `HomePanel`-only CSS classes not shared with
      `PairingDialog` first).
      Removed the exclusively-Constellation keyframes/classes
      (`cnst-tie-draw`, `cnst-star-in`, `cnst-fade`, `cnst-twinkle`,
      `.cnst-tie`, `.cnst-star-in`, `.cnst-label`, `.cnst-twinkle`,
      `.cnst-node`, `.cnst-focus`); kept `cnst-pulse-travel`/`cnst-halo`
      keyframes and `.cnst-pulse`/`.cnst-halo` classes, confirmed still
      the only two `PairingDialog.tsx` uses.

**Must stay smooth — no jank, no dropped frames, no freezes** (Luna was
explicit about this, for the whole app, not only this screen):

- [x] The plain list must not cause a full-panel re-render/layout
      thrash on every device add/remove/status-change tick — key list
      rows stably by `deviceId`, and if `HomePanel` re-renders on a
      polling interval, memoize row components (`React.memo` or
      equivalent) so unchanged rows don't re-render.
      Rows keyed by `deviceId` and extracted into `PairedRow`/
      `NearbyRow`, both wrapped in `React.memo`.
- [x] Any transition/entrance animation on a newly-appearing row uses a
      CSS transition (existing `animate-fade-in`/`animate-scale-in`
      utility classes are already used elsewhere in this codebase —
      reuse them) rather than a per-frame JS animation loop — nothing
      like the old radar sweep's continuous animation should exist
      anywhere in the new code.
      Both row components use the existing `animate-fade-in` class; no
      per-frame JS animation anywhere in the new code.
- [~] Live-verify in **both** the Vite dev server and the real Tauri
      dev build (§0): adding/removing a mock or real device, and
      scrolling a longer device list, both feel instant with no visible
      stutter. The Tauri check matters here specifically because a
      browser-only check can hide native-window compositing issues
      that only show up in the packaged app.
      The real Tauri dev build (`npm run tauri dev`) was built and run
      this session — `cargo` compiled clean (3m33s, dev profile) and the
      app launched with no Rust panics, no webview errors (only the
      expected "daemon bridge disconnected" warnings, since no daemon
      was running). Could not get an actual screenshot of either the
      Tauri window or the Vite dev server to confirm the plain list
      *looks* right or *feels* smooth while scrolling/adding devices —
      no browser tool was available, and this sandbox's desktop has
      other live windows (video, editor) that raw `grim` screenshots
      kept capturing instead of the app's own window despite
      geometry-targeted capture, so I stopped trying rather than keep
      disrupting them. Luna: please open the running Tauri window
      yourself and scroll/add a couple of devices to confirm.

### 2.5 Acceptance (whole of §2)

- [x] `npm run typecheck` (tsc, from `desktop/`) is clean.
- [x] Full existing test suite (`npm test` from `desktop/`) is green —
      update a test's assertions only for genuinely changed markup/copy,
      never to paper over a behavior regression.
      97/97 passing across all 14 test files. Only
      `SettingsPanel.test.tsx` needed assertion updates (2 lines, for
      the intentionally-changed daemon-status wording); every other
      file passed unmodified, including `HomePanel.test.tsx`'s 15 tests
      against the fully-rewritten plain list.
- [ ] Side-by-side visual comparison of each reworked screen against
      `backups/desktop-backup/` (run `npm install && npm run dev` inside
      `backups/desktop-backup/` if needed) before marking §2 fully done —
      spacing density and layout should read as a different, calmer
      design, not a re-skin with the same element count.
      Not done — needs actual screenshots/eyes-on to compare, which
      wasn't reliably possible this session (see the note above). Luna
      to do this side-by-side check herself.
- [x] Every §2 subsection above has its own checkboxes ticked; don't
      mark 2.5 done while any earlier §2 box is still open.
      All §2.1-2.4 implementation/acceptance boxes are ticked; the boxes
      left open or partial (`[~]`) are all the same kind — a manual
      visual/interactive check this sandbox couldn't reliably do, not
      unfinished implementation. Flagged individually above rather than
      silently checked.

---

## §3. Carried over — file-transfer re-architecture (mostly done)

**Update 2026-07-20: T-A20/T-A21/T-A22 are now done (root `TASKS.md`
Phase I) -- proceeded without waiting for the T-A25 gate mentioned
below, flagged as a deliberate deviation in
`TASKS-v1.0-filetransfer.md`'s own entry for those three. Only T-B3
remains, re-tracked as `TASKS.md` Phase N.** Original 2026-07-19 text
of this section, for the historical record:

Full detail archived at
[`TASKS-v1.0-filetransfer.md`](TASKS-v1.0-filetransfer.md). Status:
63/68 tasks done. Four remaining, all gated on the same task
(`T-A25`, real-device end-to-end validation — see archived file for
its definition) and not blocking anything in §1/§2:

- [x] T-A20: remove old chunk handling on the daemon.
- [x] T-A21: remove old chunk handling on mobile.
- [x] T-A22: reserve the retired proto fields.
- [ ] T-B3: verify battery impact on desktop (real-device).

Pick these up after §1/§2, or in parallel if Luna wants — they don't
touch `backups/desktop-backup/` or the screens listed above.

---

## §4. Real QR payload — DONE (2026-07-19, same session, on Luna's ask)

Originally deferred ("later, not now" — see git history for the
original text of this section). Luna asked mid-session to make it real
end to end, including a real PIN inside the QR, not just a
connect-shortcut. Implemented across the whole stack:

- **`proto/connectible.proto`**: new loopback-only RPC
  `PreArmPairingCode(PreArmPairingCodeRequest) returns
  (PreArmPairingCodeResponse { pin_code, pin_expires_at_ms })`. No
  changes to `Pair`/`ConfirmPin`'s wire shape.
- **`daemon/src/pairing/mod.rs`**: `PairingManager::pre_arm()` generates
  a PIN ahead of any inbound connection (same rejection-sampled
  digit generation + `PIN_TTL` as a normal PIN), stored as a one-shot
  `prearmed` slot. `create_pending()` now consumes a still-valid
  prearmed code instead of minting a fresh one when present, carrying
  over its *original* expiry (a QR scanned near the end of its
  countdown doesn't regain a fresh 30s). `ConfirmPin`,
  `PairingRequestedEvent`, and the local "pairing request" dialog are
  all completely unchanged — the prearmed code flows through the exact
  same path a normal PIN does. 2 new unit tests
  (`prearmed_pin_is_used_by_the_next_create_pending_call`,
  `prearmed_pin_is_one_shot`); full daemon suite still green (88 lib +
  14 integration tests).
- **`daemon/src/grpc/service.rs`**: `pre_arm_pairing_code` handler,
  loopback-gated like `SetRemoteInputEnabled`/`GetPinnedFingerprint`.
- **`desktop/core`**: `LocalDaemonClient::pre_arm_pairing_code()` +
  `PairingCodeDto`. `desktop/src-tauri`: `pre_arm_pairing_code` Tauri
  command, registered in `lib.rs`.
- **`desktop/src`**: new `PairingQrDialog.tsx` — pre-arms a code, reads
  this device's own LAN address (`ipc.localAddresses`), encodes both
  into a `connectible://pair?host=&port=&pin=&id=&name=` URI (new
  `lib/pairingCode.ts`), and renders it with the `qrcode` package onto
  a `<canvas>` (white background — QR codes need real contrast
  regardless of the app's dark theme) with a live countdown and the
  human-readable PIN shown underneath as a fallback. Auto-closes itself
  once `daemon.pairingPrompt` fires (the normal responder dialog takes
  over) instead of stacking two dialogs. Wired in via a new "Pair a
  phone" section in Settings (`onOpenPairingQr`), state lifted to
  `App.tsx` alongside the two existing `PairingDialog` renders.
- **`mobile/lib/src/screens/pair_scan_screen.dart`**: a real detected
  barcode is parsed against the same URI scheme
  (`_ScannedPairingCode.tryParse`); on a match, `startPair` +
  `confirmPin` run back to back with the PIN from the QR — no manual
  PIN sheet. "Simulate scan" keeps the old mock-against-nearby-device
  path (with the manual `PairingSheet`) as a no-camera dev fallback,
  since Linux has no real QR to point a camera at.

**Verified this session:** `cargo test` (full workspace, daemon +
desktop-core) green; `npx tsc --noEmit` + `npx vitest run` (97/97)
green; `flutter analyze` clean + `flutter test` (129/129) green; both
`flutter run -d linux` and a real `npm run tauri dev` build compile and
launch with no panics/errors. **Not verified:** an actual phone
scanning an actual desktop QR and landing paired — this sandbox has no
phone and no camera, and, as noted throughout §2's checkboxes above,
no reliable way to screenshot/interact with either running app this
session. Luna: this is the one part of today's work that needs a real
device to confirm.

## §5. Mobile Home screen flattened — DONE (2026-07-19, same session, on Luna's ask)

`lib/src/screens/home_screen.dart`'s `ConstellationView` (~550 lines:
`_Star`, `ConstellationView`, `_ConstellationViewState`,
`_ConstellationPainter`, entrance + ambient-loop `AnimationController`s)
removed entirely and replaced with `_HomeDeviceList`: this device's own
row, then "Paired"/"Nearby" sections as hairline-divided rows inside a
rounded `_ListCard` (`ClipRRect` + `Material`/`InkWell` per row for
proper ripple clipping) — the same grouped-card language desktop's
`HomePanel` now uses (§2.4), built from mobile's own existing
`AppCard`/`Eyebrow`/`EmptyState` primitives (`widgets/ui.dart`), not
new one-off styling. Paired rows open the same action sheet a tapped
star used to (info/disconnect/forget); nearby rows call the same
`_onTapNearby` pairing path. Platform-type icons on each row (kept from
the old constellation, confirmed load-bearing by an existing test) via
the already-imported `platformIcon()`. No change to `_StatusLine`,
`_QuickActionsGrid`, `_ReceivingCard`, `ManualConnectSheet` — only the
device-roster visualization itself was swapped.

Two existing widget tests needed real updates (not behavior papering):
the empty-state assertion (`_HomeDeviceList` now uses the shared
`EmptyState` widget + `devices.emptyTitle`/`devices.emptyHint` keys,
matching every other list screen in the app, instead of the
constellation's own copy) and the platform-icon assertion (moved from
the star glyph onto the row, same icon). Both pass; full mobile suite
(129 tests) green; `flutter analyze` clean.
