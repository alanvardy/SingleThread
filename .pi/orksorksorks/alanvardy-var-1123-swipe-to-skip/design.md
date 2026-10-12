# Design Discussion — VAR-1123 "Swipe to skip"

## Current State

The iOS swipe surface is a two-outcome gesture backed by shared, pure logic in
`SingleThreadCore`:

- `SwipeGestureOutcome = .complete | .skip | .none` — `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift:4`;
  `releaseDistance = 72` (`:15`); `outcome(for:threshold:)` maps a released
  horizontal drag (`:21-33`) and `revealedOutcome(forOffset:)` maps the live
  offset sign (`:34-40`).
- The only consumer is iOS. `SwipeToActModifier` wraps a card, renders an
  optional `SwipeRevealPanel`, and fires `onOutcome` (`SingleThread/SwipeToActModifier.swift:88-123`).
  `SwipeRevealPanel` maps `.complete` → `SharedStrings.completeAction` +
  `checkmark.circle.fill` + `CardPlate.completeHintColor` (`:55-59`) and
  `.skip` → `SharedStrings.skipAction` + `circle.slash` + `CardPlate.skipHintColor`
  (`:60-64`); anchor is `.trailing` for `.skip`, else `.leading` (`:34-36`).
  It carries `accessibilityAction(completeAction)` (`:114`) and
  `accessibilityAction(skipAction)` (`:117`).
- Dispatch is at `SingleThread/ContentView.swift:459-467`: `.complete` →
  `completeCurrentReminder()`, `.skip` → `skipCurrentReminder()` directly,
  `.none` → break. So **a left swipe skips immediately with no menu.**

The Skip / Reschedule / Delete menu already exists on every platform, gated by
one shared enum:

- `ActionMenuGate.showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder)`
  = logical AND (`SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:7,12`),
  called by iOS (`ContentView+ActionMenu.swift:18-24`) and macOS (`:84-91`).
- iOS presents `.confirmationDialog(SharedStrings.reminder, isPresented: $isShowingActionMenu)`
  (`ContentView+ActionMenu.swift:46`) with Skip (no role), `Button("Reschedule")`
  (id `rescheduleButton`), Delete (`.destructive`, id `deleteButton`) (`:47-59`).
  The bottom-bar `skipButton` opens it when `showActionMenu`, else skips directly
  (`:25-36`).
- macOS uses a native `Menu` with the same three items (`:101-111`); when the
  toggle is OFF it shows separate Skip/Delete buttons.
- Watch presents the same three items via `.confirmationDialog`
  (`SingleThreadWatch/WatchReminderView.swift:211-221,277`).
- "Reschedule" is a hardcoded literal on all three platforms
  (`ContentView+ActionMenu.swift:50,117`, `WatchReminderView.swift:214`), not a
  `SharedStrings` member; "Skip"/"Delete"/"Complete" live in Core
  (`LocalizedString+Shared.swift:16,31,38`) and are backed by the Core String
  Catalog.

`enableActionButtons` is a stored preference (`@AppStorage(..., store: AppGroup.defaults)`,
`ContentView.swift:100`) mirrored into `ContentViewModel` (`:74-77`) and used
only for the `showsActionButtons` render gate (`ContentViewModel.swift:96-97`).
The watch reimplements the same AND inline (`WatchReminderView.swift:80-84`)
rather than calling the enum.

Tests today: `SwipeGestureDecisionTests` (`:10-56`), `SwipeToActModifierTests`
(`:11-40`), `ActionMenuGateTests` (`:10`), `ActionButtonTests` (`:21-62`),
`AppLanguageTests` (`:77-82`, shared keys × 6 languages). No UI test drives the
swipe-left or action-menu paths; the only swipe UI test is a right-swipe
complete (`SingleThreadUITests.swift:73-115`).

## Desired End State

On iOS, a left swipe past the 72 pt release threshold presents the existing
action menu (Skip / Reschedule / Delete) instead of skipping immediately. The
swipe-revealed label reads **"More"** (not "Skip") with an `ellipsis.circle.fill`
glyph, and the swipe's accessibility action is likewise named "More". The
bottom-bar action button's accessibility label also reads "More"; the menu's
first *item* remains "Skip". The menu presented from the swipe is the **same**
`confirmationDialog` the bottom bar presents, with the same reminder capture and
the same gating.

macOS and the watch are behaviorally unchanged: they already present the same
three-item menu on their existing surfaces (native `Menu`; watch
`confirmationDialog`), and no new swipe gesture is introduced on either. They
participate only through the shared localized strings.

Verification: left-drag past threshold produces `.more` and opens the dialog;
the reveal panel renders "More"; the new shared key resolves in all six shipped
languages; and one iOS UI test proves the end-to-end swipe-open-menu flow
against the `--seed` in-memory store.

## Patterns to Follow

- **Shared ≥2-target keys live in `SharedStrings` + the Core catalog**, never
  duplicated into a target catalog (`LocalizedString+Shared.swift:5-6`). A new
  `moreAction` accessor must be added there and catalogued in
  `SingleThreadCore/.../Resources/Localizable.xcstrings` for all six languages,
  and must join the localization fixtures (`AppLanguageTests.swift:77-82`,
  `:50-53`).
- **Right way to gate action surfaces:** call
  `ActionMenuGate.showsActionMenu(...)` (`ActionMenuGate.swift:7`) — the iOS
  and macOS pattern. *Do not follow* the watch's inlined AND
  (`WatchReminderView.swift:80-84`); it is a divergence the research flags
  (no test keeps them in lockstep). This ticket does not fix it, and should not
  copy it.
- **Swipe decisions stay pure and shared** in `SwipeGesture` (no SwiftUI),
  mirroring `SwipeGesture.swift:21-40`; presentation stays in
  `SwipeToActModifier`. Do not move decision logic into `ContentView`.
- **Reuse the existing dialog state** (`isShowingActionMenu` +
  `actionMenuReminder`, `ContentView.swift:126,133`) rather than adding a second
  menu trigger, following the `showActionMenu` helper style in
  `ContentView+ActionMenu.swift:18-24`.
- **Unit tests use Swift Testing** (`import Testing`, `@Test`) and names must
  not start with `test`/`testing` (SwiftFormat strips the prefix); UI tests use
  XCTest and keep `test…`.
- **UI tests are the exception.** When added, drive deterministic write flows
  with `--seed '<json>'` + `--ui-testing-noop-settle` and the `InMemoryEventStore`
  seam, as `testOverThresholdSwipeCompletesReminder` does
  (`SingleThreadUITests.swift:73-115`).
- **A11y on caption-sized/plate controls** needs explicit `.accessibilityLabel`
  and, where the surface is a button, `.isButton` — see the plate patterns at
  `ContentView.swift:493-494` (delete, no trait) vs `:534-536` (complete,
  `.isButton`).

## Design Decisions

1. **Menu mechanism = existing `.confirmationDialog`**: reuse the dialog already
   bound at `ContentView+ActionMenu.swift:46`; do not build a custom centered
   overlay or a new `Menu`. It is the established idiom on iOS and watch and
   makes the swipe and the bottom bar present literally the same menu. The
   ticket's "menu in the middle" is interpreted as "the action menu", not
   "physically centered UI".
2. **Swipe is unconditional; `enableActionButtons` does not gate it**: the left
   swipe always opens the menu. The toggle continues to gate only the
   bottom-bar action cluster (`showsActionButtons`, `ContentViewModel.swift:96-97`)
   and the macOS cluster. This preserves the toggle's meaning ("action buttons")
   and keeps the swipe single-mode.
3. **Rename the shared outcome case `.skip` → `.more`**: `SwipeGestureOutcome`
   becomes `.complete | .more | .none`; `outcome(for:)`/`revealedOutcome(forOffset:)`
   and both switch sites change in lockstep (`SwipeGesture.swift:4,21-40`).
   The shared type then honestly describes "left swipe = more actions". Ripples
   to `SwipeGestureDecisionTests` and `SwipeToActModifierTests`.
4. **Reveal panel: "More" + `ellipsis.circle.fill` + existing `skipHintColor` +
   `.trailing` anchor**: a slash glyph labelled "More" is misleading; the
   ellipsis dot-glyph is the standard "more actions" symbol. Reusing
   `CardPlate.skipHintColor` avoids adding a design token. Trailing anchor is
   unchanged.
5. **Rename scope (B)**: the swipe reveal label, the swipe
   `accessibilityAction` name, and the bottom-bar button's a11y label become
   "More"; the menu's first item keeps "Skip" (`SharedStrings.skipAction`). Both
   "More" triggers open the same menu, so both should read "More"; only the item
   that performs the skip reads "Skip".
6. **New shared key `SharedStrings.moreAction`**: typed accessor in
   `LocalizedString+Shared.swift` + Core catalog translations for all six
   shipped languages, joining `AppLanguageTests` fixtures. No target-catalog
   duplicate.
7. **Keep "Reschedule"**: the ticket's "Schedule" is treated as shorthand; the
   literal, the App-catalog entries (`Localizable.xcstrings:2713,2754`), and
   `RescheduleSheet` are unchanged.
8. **Single menu entry point for both triggers**: the `.more` swipe dispatch
   and the bottom-bar button call one helper that sets `actionMenuReminder =
   visibleReminders.first` and `isShowingActionMenu = true`, mirroring
   `ContentView+ActionMenu.swift:25-36`. No duplicated capture logic and no
   second dialog binding.
9. **Platform scope = iOS behavior only**: macOS `Menu`, watch
   `confirmationDialog`, and the watch's inline gate are untouched except for
   any shared-string propagation. No new gesture on macOS or watch — research
   confirms neither consumes `SwipeGesture`/`SwipeToActModifier`.
10. **Test matrix**: update `SwipeGestureDecisionTests` (left-drag → `.more`,
    reveal mapping) and `SwipeToActModifierTests` (panel shows "More" +
    `ellipsis.circle.fill` + trailing), extend the shared-key localization
    fixtures, and add **one** iOS UI test that swipes left ~110 pt on
    `reminderCard` and asserts `rescheduleButton`/`deleteButton` appear. No watch
    UI test (its dialog is unchanged).

## What We're NOT Doing

- No custom centered overlay menu, no new menu component, no scrim/dismiss
  machinery — the existing `.confirmationDialog` is the menu.
- No new swipe gesture on macOS or watch; no watch swipe-to-open-menu.
- `enableActionButtons` is **not** removed, renamed, or re-scoped; it still
  gates only the bottom-bar/macOS action clusters. No changes to its storage,
  migration (`AppViewModel.swift:141-145`), or WatchConnectivity sync.
- "Reschedule" is **not** renamed to "Schedule"; `RescheduleSheet` and its tests
  are untouched.
- The watch's inlined gate vs `ActionMenuGate` divergence is **not** fixed here
  (recorded as a risk, not scope).
- No changes to the widget, the long-press context menu
  (`ContentView.swift:507-528`), or the macOS toggle-OFF Skip/Delete buttons.
- No child tickets; all work lands on the main ticket branch.

## Open Risks

- **A11y audit surface:** relabelling the bottom-bar button to "More" and
  renaming the swipe accessibility action to "More" changes what the smoke
  audit (`SingleThreadUITests.swift:59`) sees. The audit asserts traits and
  element descriptions, not names, so this should pass — but it must be
  re-run.
- **UI-test flake:** the new swipe-open-menu UI test is a new
  `--seed`-driven interaction; the existing right-swipe test is the only prior
  precedent. Keep the drag geometry identical (~110 pt) and assert on the
  dialog buttons (`rescheduleButton`/`deleteButton`), which are already
  identifier'd.
- **"More" translation quality:** `moreAction` must be added to all six shipped
  languages; `AppLanguageTests.sharedStringResolvesToEveryShippedLanguage`
  (`:77-82`) will fail if any locale is missed. The exact six-locale list should
  be read from that fixture during planning.
- **Panel-vs-dialog layering:** the reveal panel animates back to offset 0
  before `onOutcome` fires (`SwipeToActModifier.swift:105-110`), so the panel
  should not linger under the presented dialog; verify on-device that the
  dialog's presentation doesn't visibly restart the panel animation.
- **Bottom-bar direct-skip branch:** `ContentView+ActionMenu.swift:25-36`
  retains a direct-skip branch when `showActionMenu` is false. With the swipe now
  always showing the menu, that branch's reachability (only via a
  mutate/gate false-negative) is unchanged but worth a note during planning so
  it is not accidentally deleted.
- **Research gaps not in scope:** no watch-catalog fixture for shared action
  keys and no test coupling the watch's inline gate to `ActionMenuGate` — both
  pre-existing, flagged only.