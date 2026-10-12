# Structure Outline

## Approach

Three vertical slices on one branch: (1) rename the shared swipe outcome
`.skip` → `.more` and rewire the iOS dispatch so a left swipe past threshold
presents the **existing** action menu instead of skipping; (2) relabel the
swipe surface and bottom-bar button to a new shared `moreAction` key ("More" +
`ellipsis.circle.fill`), catalogued in all six shipped languages; (3) hardening —
a11y audit, panel/dialog layering and lint/periphery. No horizontal phase: the
localization key ships inside the slice that consumes it.

---

## Phase 1: Walking skeleton — left swipe opens the action menu

End to end: a left drag past 72 pt on `reminderCard` yields `.more`, and iOS
presents the same Skip/Reschedule/Delete `.confirmationDialog` the bottom bar
presents. Ah — design decision 8 requires one presenter: the swipe dispatch and
the bottom-bar branch both call it.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift`,
`SingleThread/SwipeToActModifier.swift`, `SingleThread/ContentView.swift`,
`SingleThread/ContentView+ActionMenu.swift`

**Key changes**:
- `SwipeGestureOutcome { case complete, more, none }` — rename `.skip` → `.more`;
  `outcome(for:)` / `revealedOutcome(forOffset:)` updated in lockstep
- `SwipeToActModifier.body` — `.onEnded` fires `onOutcome(.more)`; the panel
  switch arm for `.more` **temporarily** keeps the old presentation
  (`SharedStrings.skipAction`, `circle.slash`, `skipHintColor`) and the a11y
  action keeps its old name; relabel is Phase 2
- `ContentView` dispatch (`:459-467`) — `.more` → `presentActionMenu()` instead
  of `viewModel.skipCurrentReminder()`
- `ContentView+ActionMenu.swift` — new `presentActionMenu()` (sets
  `actionMenuReminder = visibleReminders.first` + `isShowingActionMenu = true`);
  the bottom-bar `skipButton` branch (`:25-36`) calls it. *Naming note*: the
  existing gate is the Bool `showActionMenu` (`:19`) — the new presenter is
  `presentActionMenu()` to avoid a collision

**Contract**: `SwipeGestureOutcome.more` exists; a `.more` swipe calls the one
`presentActionMenu()` presenter. Phase 2 may depend only on the case name and
the dialog being presented — never on dispatch internals.

**Tests**: `SwipeGestureDecisionTests.leftPastThresholdSkips` → `.more` (rename
+ assert), reveal mapping for negative offsets; new UI test
`testOverThresholdSwipeOpensActionMenu` (`--seed` + `--ui-testing-noop-settle`,
110 pt left drag, asserts `rescheduleButton`/`deleteButton` appear) covering the
happy path, and `underThresholdDoesNothing`/`verticalDominantDragDoesNothing`
as the sad paths.
**Verify**: `make build`; `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests`;
`scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeOpensActionMenu`.

---

## Phase 2: "More" — relabel the swipe surface and bottom-bar button

End to end: the swipe reveal panel reads **More** with an
`ellipsis.circle.fill` glyph, both swipe and bottom-bar triggers announce
"More" to VoiceOver, and the new key resolves in en / zh-Hans / es / ja / de /
fr. The menu's first *item* stays "Skip".

**Files**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`,
`SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`,
`SingleThread/SwipeToActModifier.swift`, `SingleThread/ContentView+ActionMenu.swift`

**Key changes**:
- `public static var moreAction: LocalizedStringResource` — new, key `"More"`,
  alongside `skipAction` (`LocalizedString+Shared.swift:31`)
- Core catalog `"More"` entry — six locales, joining the fixture convention
- `SwipeRevealPanel.presentation` — `.more` → `SharedStrings.moreAction` +
  `"ellipsis.circle.fill"` + `CardPlate.skipHintColor`; `.trailing` anchor
  unchanged
- `SwipeToActModifier` — `.accessibilityAction(SharedStrings.moreAction)`
  replaces the skip-named action
- `ContentView+ActionMenu.swift` — bottom-bar `skipButton` gains
  `.accessibilityLabel(SharedStrings.moreAction)`; dialog item text remains
  `SharedStrings.skipAction`

**Contract**: `SharedStrings.moreAction` resolves in all six locales; the swipe
panel, swipe a11y action and bottom-bar a11y label all read it. The menu item
key `skipAction` is untouched.

**Tests**: `SwipeToActModifierTests` — panel label = More, glyph =
`ellipsis.circle.fill`, anchor = trailing (sad path: complete panel unchanged);
`AppLanguageTests` — extend `sharedStringResolvesToEveryShippedLanguage` (or a
sibling test) with `moreAction` across all six languages, plus the
explicit-locale fixture.
**Verify**: `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests`;
`scripts/test-one.sh SingleThreadTests/AppLanguageTests`.

---

## Phase 3: Hardening & verification

No new capability — proof the two slices hold under the audit and the real
gate. Re-run the smoke a11y audit (`.sufficientElementDescription`, `.trait`)
now that the button/swipe labels changed; on-device/simulator confirm the
reveal panel animates back before the dialog presents (no restarting/lingering
panel) and that `enableActionButtons` still gates only the bottom-bar cluster
while the swipe always opens the menu.

**Files**: none expected (small a11y/label fixes only if the audit or a manual
check demands one)

**Key changes**: none anticipated; the direct-skip branch at
`ContentView+ActionMenu.swift:25-36` is **kept** (only reachable on a gate
false-negative).

**Tests**: `SingleThreadUITests.testLaunchAndRenderSmoke` (a11y audit),
`testOverThresholdSwipeOpensActionMenu` re-run; `make format` + `make lint`
clean; `make periphery` after a clean `DerivedData/`.
**Verify**: `make lint`; `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke`;
then the full `./scripts/test.sh` ONCE via the `run-gate` skill.

---

## Testing Checkpoints

- **After Phase 1**: `SwipeGestureDecisionTests` green and the new swipe-open-menu UI test green — no Phase 2 work until the dispatch+presenter path is proven.
- **After Phase 2**: `SwipeToActModifierTests` green (More + ellipsis + trailing) and `AppLanguageTests` green for all six locales — no Phase 3 until the key resolves everywhere.
- **After Phase 3**: smoke a11y audit, `make lint`, and `make periphery` clean; then hand off to the one-shot full gate. If Phase 1's swipe UI test fails twice, CI is authority (repo AGENTS).