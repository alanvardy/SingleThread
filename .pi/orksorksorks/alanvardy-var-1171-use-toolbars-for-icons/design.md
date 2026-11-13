# Design Discussion

Ticket: VAR-1171 — use toolbars for icons. Branch: `alanvardy-var-1171-use-toolbars-for-icons`.

## Current State

The iOS main screen has **no navigation container and no toolbar**. `ContentView.body`
(`ContentView.swift:168-183`) is a bare `ZStack`: `Color.systemBackground.ignoresSafeArea()`
(`:170`), `BackgroundPhotoLayer(...)` (`:171`), then a content dispatch on
`viewModel.store.loadsReminders` (`:174-178`). Every control is an overlay or inline stack:

- Settings gear: `.overlay(alignment: .topTrailing)` (`:181-197`), an `Image(systemName: "gearshape")`
  + `.controlPlate()` (`:188`) + `.singleThreadButton()` (`:191`), id `settingsButton` (`:193`),
  hand-tuned `.padding(.top, 8).padding(.trailing, 12)` (`:195-196`).
- iOS undo: `.overlay(alignment: .topLeading)` (`:228-249`), id `undoButton`, `.padding(.top, 8).padding(.leading, 12)`.
- iOS action cluster: `HStack(alignment: .center, spacing: 16) { completeButton; micButton; skipButton }`
  (`:571-577`), rendered from `bottomBar` (`:727`, iOS branch `:748-757`) inside a
  `ZStack(alignment: .bottom)` (`:445`, `:462`) with `.padding(.bottom, 16)`.
- Shared chrome: `controlPlate` is a **56×56 circle with a shadow** (`ControlPlateModifier.swift:20-28`);
  `singleThreadButton` is `.buttonStyle(.borderless)` (`SingleThreadButtonModifier.swift:11-13`).
  Both are platform-agnostic; macOS call sites use the same helpers
  (`ContentView+ActionMenu.swift:126-196`).

Repo-wide, `.toolbar` is used **only** as a sheet dismiss affordance (`.cancellationAction` /
`.confirmationAction`, 5 sites, e.g. `SettingsView.swift:203-209`). There is no in-repo precedent
for an action toolbar on a root screen, and no test constructs a `ToolbarItem`.

Apple HIG — *Designing for iPhone Duo* (page dated 2026-09-09) — establishes the missing premise:

- iPhone Duo has an inner and an outer display; **the system places toolbars and tab bars on the
  side** (vertical axis) on the outer display and inner landscape. Apps using standard components
  "receive this layout automatically". Adapt via **size classes** (compact = outer, regular = inner),
  layout margins and safe areas; "avoid fixed widths and display-specific dependencies"; "don't
  reinvent your app when it resizes".
- Vertical controls: top of the axis = primary navigation (Back/Close), then prominent actions
  (Done); overflow runs bottom-to-top with per-item visibility priority; **group related items with
  `ToolbarItemGroup` and never add fixed spacing yourself**; **don't override the default bar
  placement**; **provide both a title and a symbol for each item**; keep text buttons to a minimum;
  use the **system overflow menu** rather than an app-specific one.
- Reserved regions (outer camera/Dynamic Island, inner camera, the fold) are handled by system
  components; custom content may use the `Reserved` API.

Consequence: the ticket's "vertical toolbar layout" is **not code to write**. It is what the OS does
to a standard toolbar, and the app currently cannot benefit because its chrome is overlays.

## Desired End State

1. On iOS the main screen is hosted in a `NavigationStack` and renders a real `.toolbar`:
   `topBarTrailing` gear, `topBarLeading` undo, and one `ToolbarItemGroup(.bottomBar)` with
   complete / mic / skip.
2. Toolbar items are `Label(title, systemImage:)` — title and symbol, no `controlPlate`, no
   `.singleThreadButton()` — so the system supplies bar chrome, chooses the representation, and owns
   spacing and overflow.
3. iPhone Duo support is satisfied by construction: no fixed widths, no display-specific branching,
   standard bars → the system relocates them to the vertical axis on the outer display.
4. macOS is byte-identical: `controlPlate` / `singleThreadButton` / `actionButtons` /
   `MacOSActionButtonChromeTests` are untouched and `make mac-test` is green.
5. Accessibility ids and labels survive unchanged (`completeButton`, `skipButton`, `dictateButton`,
   `settingsButton`, `undoButton`), so the UI smoke test and a11y audit still pass.

**Verification:** `make lint` + `make build` green; targeted `SingleThreadUITests/testLaunchAndRenderSmoke`
(queries `completeButton`/`skipButton`/`dictateButton` + `performAccessibilityAudit`); tapped
`settingsButton` flows (`SingleThreadUITests.swift:207,276`); `make mac-test` green. No Duo proxy run
(decision 9).

## Patterns to Follow

- **Whole-file / inline `#if os(iOS)` gating** — `ContentView+iOS.swift:10,54,131` (whole file) and
  dense inline gates in `ContentView.swift` (`:9,22,37,…`). The toolbar attachment is iOS-only and
  must use this idiom, not a shared code path.
- **Accessibility contract first** — every action button carries `.accessibilityLabel` +
  `.accessibilityIdentifier` + `.accessibilityAddTraits(.isButton)` (`:558-569`, `:582-592`,
  `:181-197`). Toolbar items keep all three.
- **Shared-string localization** — labels resolve through `SharedStrings` (e.g.
  `SharedStrings.completeAction` `:562`, `SharedStrings.completeReminderAccessibility` `:567`);
  new titles must use localized resources, not literals (`LocalizedNavigationTitle.swift:16-27` shows
  the repo's localization idiom for title-adjacent strings).
- **Swift Testing unit tests + XCUI identifiers** — unit tests are Swift Testing with non-`test`
  names; UI assertions go through accessibility identifiers and `performAccessibilityAudit`
  (`SingleThreadUITests.swift:59-67`).
- **Platform divergence at call sites, not in the modifiers** — `ControlPlateModifier` /
  `SingleThreadButtonModifier` deliberately contain no `#if os`; divergence lives where they're
  applied (see `SingleThreadButtonModifier.swift:3-9` header doc). Keep `controlPlate` free of
  iOS-only branches when iOS stops calling it.

**Do NOT follow:**
- The `.overlay(alignment:)` + hand-tuned `.padding(.top/.trailing)` chrome pattern (`:195-196`,
  undo `:8/12`). That is exactly what the toolbar replaces; do not port those paddings into toolbar items.
- Manual `HStack(spacing: 16)` (`:571-577`) inside a bar — HIG: groups provide spacing, "avoid adding
  fixed spacing yourself".
- Reflection assertions on iOS chrome structure as the *primary* net (they sign modifier chains that
  this change deletes; see decision 5).
- Sheet-dismiss-only `.toolbar` usage (`.cancellationAction`/`.confirmationAction`) as the model for
  placement — our placements are `topBarLeading`/`topBarTrailing`/`bottomBar`.

## Design Decisions

1. **Duo scope = standard chrome, no custom vertical layout.** Rely on system bar relocation; zero
   Duo-specific code, no external-display `UIScene`. HIG: "the system places toolbars and tab bars on
   the side"; "don't override the default bar placement". Rejected: hand-built vertical bar
   (`horizontalSizeClass` swap) and dual code paths — both untestable in this gate and explicitly
   discouraged.
2. **Toolbar host = `NavigationStack` wrapper.** Wrap the root content, hide the navigation bar
   (`.toolbar(.hidden, for: .navigationBar)`, `.toolbarBackground(.hidden, for: .navigationBar)`) so
   only the bottom group shows, and keep `Color.systemBackground` / `BackgroundPhotoLayer` /
   `ignoresSafeArea()` (`:170-171`) plus the manual viewport math (`:425-427`) visually unchanged.
   Plan begins with a **spike**: try `.toolbar` on the nav-free root first (cheap; would shrink the
   diff), and fall back to the `NavigationStack` wrapper if items don't render. Rejected:
   `.safeAreaInset` custom bar (not a toolbar, no automatic Duo placement).
3. **Placement map: two top items + one bottom group.** `ToolbarItem(placement: .topBarTrailing)`
   gear, `ToolbarItem(placement: .topBarLeading)` undo, `ToolbarItemGroup(placement: .bottomBar)`
   { complete, mic, skip }. Removes the `topTrailing`/`topLeading` overlays and `actionCluster`'s
   `HStack`. Deliberate deviation from HIG's "prominent action after navigation": complete is this
   screen's primary action, so it leads the bottom group rather than sitting next to the gear.
   Rejected: ticket-literal (undo stays an overlay — leaves an unbalanced floating plate).
4. **Icon representation = `Label(title, systemImage:)`, no plate.** HIG: provide both title and
   symbol; standard components own the bezel. iOS toolbar items drop `controlPlate` and
   `.singleThreadButton()`; `controlPlate` survives for macOS call sites and the non-toolbar
   `recordingIndicator` (`:594-600`). Rejected: 56pt shadowed plates inside a system bar; and a new
   `controlPlate(size:)` variant that adds a one-platform API.
5. **Regression net = UI layer for iOS, byte-identical macOS reflection.** Keep all a11y ids/labels
   and rely on `testLaunchAndRenderSmoke` + `performAccessibilityAudit` (`SingleThreadUITests.swift:31,46-67`)
   and the `settingsButton` tap flows (`:207,276`). Retire iOS reflection assertions that signed the
   now-deleted chains; add unit tests only for genuinely new logic (label/symbol resolution, gated
   item set). All `#if os(macOS)` tests (`SingleThreadTests.swift:75,109,130`,
   `MacOSActionButtonChromeTests.swift:13,22,29`) stay untouched. Rejected: reflection tests on
   `ToolbarItem` structure (SDK-fragile); full replacement of chrome coverage by UI tests.
6. **Entitlement / toggle gating reproduced exactly.** Inside `ToolbarItemGroup(.bottomBar)`, mirror
   `bottomBar`'s iOS branch (`:748-757`): no entitlement → no action items; free tier → no action
   items and `upgradePrompt` (`:705-724`) still rendered in `body`; else complete/mic/skip when
   `viewModel.showsActionButtons`, mic alone otherwise. Speech-denied mic stays hidden
   (`MicrophoneToggleTests.swift:31`). Rejected: always-present-but-disabled items (contradicts
   today's hide-don't-disable behavior).
7. **Transient dictation/feedback states stay in `body`.** Error / feedback / `recordingIndicator` /
   processing remain in the bottom `VStack` (`:727`), adjusted so they sit above the bar rather than
   duplicating it; only the four persistent actions + undo become toolbar items. Rejected: promoting
   the red pulse plate into the mic's toolbar item (loses the recording affordance, complicates the
   a11y tree); all-states-in-toolbar (largest churn, system may overflow/relocate them on Duo).
8. **macOS protection by construction.** `.toolbar { … }` is attached under `#if os(iOS)`; no shared
   toolbar, no change to `actionButtons` (`ContentView+ActionMenu.swift:104`), `controlPlate`, or
   `singleThreadButton`. If `ContentView.swift` grows unwieldy, the toolbar moves to a whole-file
   `#if os(iOS)` `ContentView+Toolbar.swift` (matching `ContentView+iOS.swift`) as a pure refactor.
9. **Duo verification = none beyond standard-component correctness** (user-selected). No iPad proxy
   run and no Duo-specific test: the obligation is "be a standard component and be resizable", which
   `make build` + existing destinations cover. This is the one knowingly-unverified claim, recorded
   under Open Risks.
10. **No `Reserved` API.** The screen is a `List`/`ScrollView` + background photo + system toolbar;
    nothing custom overlaps a reserved region and HIG says system components arrange themselves.

## What We're NOT Doing

- **No external-display / additional-`UIScene` machinery** (no `UIApplicationSupportsMultipleScenes`,
  no `UIWindowSceneSessionRoleExternalDisplay`, no scene delegate, no Info.plist scene manifest). The
  outer display is the same scene at a different size class.
- **No custom vertical toolbar** — no `horizontalSizeClass` branch, no `VStack` action stack, no
  `UIVertical*`/Device Hub detection, no per-pose layouts.
- **No `Reserved` API / fold-region handling.**
- **No app-overflow migration.** HIG says move app overflow into the system overflow menu; the up-drag
  reschedule/delete action menu (`SingleThreadUITests.swift:190-197`) and `rescheduleButton`/
  `deleteButton` stay as-is. Separate ticket if wanted.
- **No `controlPlate` redesign** — no size variants, no toolbar-specific plate style, no changes to
  `ControlPlateModifier`/`SingleThreadButtonModifier` bodies.
- **No macOS chrome changes** — no toolbar on macOS, no touch to `actionButtons`/`macActionMenu`, no
  edits to macOS reflection tests.
- **No Settings/`MenuBarExtra`/watch changes**, no new navigation titles, no `localizedNavigationTitle`
  adoption on the main screen.
- **No new test target, no scheme/pbxproj structural edits** (only synchronized-group source additions,
  if any).
- **No orientation-lock or `AppDelegate` changes** (`AppDelegate.swift:32-58` stays).
- **No UI-test expansion** beyond keeping the existing smoke + `settingsButton` flows green.

## Open Risks

- **Duo behavior is unverified by construction** (decision 9): if SwiftUI's side-bar relocation needs
  a non-default configuration we cannot observe, it surfaces only on real Duo hardware.
- **Toolbar-without-host uncertainty** (decision 2): whether `.bottomBar` items render on the nav-free
  root is undocumented; the spike decides between the nav-free and `NavigationStack` shapes. If the
  wrapper is required, watch for (a) a top safe-area strip where the gear used to float, (b) the
  background photo no longer reaching the top edge, (c) the manual viewport math (`:425-427`)
  double-counting insets.
- **Bottom-bar items may render smaller/differently than the current 56pt plates**, changing the
  screen's visual weight and possibly the local `.hitRegion` audit (the audit runs stricter locally
  than in CI — a local hit-region failure may be local-only).
- **Retiring iOS reflection assertions** could remove the only fast signal on iOS chrome; mitigated by
  keeping ids + audit, but a purely structural iOS regression (wrong placement) would pass.
- **Entitlement branch reconstruction** (`:748-757`) has three states plus speech-denial; a
  transcription slip changes paywall behavior silently — cover with a unit test on the item-set logic.
- **`upgradePrompt` and transient states now share vertical space with a system bar**; spacing/padding
  may need adjustment that is not size-class-neutral.
