# Implementation Plan

## Overview

On iOS, a left swipe past the 72 pt release threshold presents the existing
Skip / Reschedule / Delete `.confirmationDialog` instead of skipping directly.
The swipe reveal panel and both "More" triggers read a new shared `More` key
(with an `ellipsis.circle.fill` glyph); the menu's first item stays "Skip".
macOS and the watch stay behaviorally unchanged.

## Pre-flight notes (read before Phase 1)

1. **The dialog host must move.** Today `.confirmationDialog` is attached to
   `skipButton` (`ContentView+ActionMenu.swift:38-59`), which only renders when
   `viewModel.showsActionButtons` is true (toggle ON + entitlement + mutable +
   visible reminder). Design decision 2 makes the swipe **unconditional**, so a
   dialog bound to `skipButton` cannot present when the toggle is OFF (or the
   fake `/` entitlement / `canMutate` gate closes). The single dialog binding is
   therefore hosted on `ContentView.body` (always rendered); the button list is
   extracted to a `@ViewBuilder` var in the iOS extension. Still **one** dialog
   binding and **one** capture helper — no duplication.
2. **macOS compiles the same dispatch.** `.swipeToAct` (`ContentView.swift:459`)
   is *not* behind `#if os(iOS)`, and `SingleThread/SwipeToActModifier.swift`
   compiles for macOS too. `.more` on macOS must keep the current skip behavior
   (design decision 9), so the dispatch branches `#if os(iOS)` inside the
   `case .more` arm.
3. `presentActionMenu()` must be **internal**, not `private`: the dispatch in
   `ContentView.swift` calls it across files (same pattern as `skipButton`).

---

## Phase 1: Walking skeleton — left swipe opens the action menu

End to end: a left drag past 72 pt yields `.more`, and iOS presents the same
Skip / Reschedule / Delete dialog the bottom bar presents, through one presenter.
The reveal panel and a11y names are **not** relabelled yet (Phase 2).

### Changes

#### 1. Rename the shared outcome case
**File**: `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift`
**Action**: modify

```swift
public enum SwipeGestureOutcome: Equatable {
    case complete
    case more
    case none
}
```

In `outcome(for:threshold:)` change both `return .skip` → `return .more`
(`:27`, `:39`), and update the comment on `revealedOutcome(forOffset:)` from
"negative (left) → skip" to "negative (left) → more".

#### 2. Update the iOS modifier to the renamed case (presentation unchanged)
**File**: `SingleThread/SwipeToActModifier.swift`
**Action**: modify

- `alignment(for:)`: `outcome == .skip ? .trailing : .leading` →
  `outcome == .more ? .trailing : .leading`.
- `presentation` switch arm: `case .skip:` → `case .more:`, **keeping** the
  current render data (`SharedStrings.skipAction`, `"circle.slash"`,
  `CardPlate.skipHintColor(for: colorScheme)`).
- a11y action: keep `SharedStrings.skipAction` as the name, but the handler must
  fire the new case — `onOutcome(.skip)` → `onOutcome(.more)`.
- Update the `swipeToAct` doc comment "drag-to-complete (right) /
  drag-to-skip (left)" → "drag-to-more (left)" only in Phase 2; leave it here.

#### 3. One presenter + move the dialog to an always-present host
**File**: `SingleThread/ContentView+ActionMenu.swift`
**Action**: modify (inside the existing `#if os(iOS)` block)

Add the presenter and the extracted dialog body:

```swift
/// One entry point for the shared three-action menu: captures the visible
/// reminder and flips the dialog flag. Called by the bottom-bar button when
/// the gate is open and by the left-swipe `.more` outcome (ungated).
func presentActionMenu() {
    actionMenuReminder = viewModel.store.visibleReminders.first
    isShowingActionMenu = true
}

/// The dialog contents. Rendered from the dialog hosted on `ContentView.body`
/// so it presents even when the bottom-bar cluster (`skipButton`) is not on
/// screen (toggle off / entitlement / mutate gate closed).
@ViewBuilder
var actionMenuDialogButtons: some View {
    Button(SharedStrings.skipAction) {
        viewModel.skipCurrentReminder()
    }
    Button("Reschedule") {
        isShowingActionMenu = false
        isShowingRescheduleSheet = true
    }
    .accessibilityIdentifier("rescheduleButton")
    Button(SharedStrings.deleteAction, role: .destructive) {
        Task { await viewModel.deleteCurrentReminder() }
    }
    .accessibilityIdentifier("deleteButton")
}
```

Then in `skipButton`: remove the attached `.confirmationDialog { … }` block and
change the gate-open branch to call the presenter:

```swift
var skipButton: some View {
    Button {
        if showActionMenu {
            presentActionMenu()
        } else {
            viewModel.skipCurrentReminder()
        }
    } label: {
        Label(SharedStrings.skipAction, systemImage: "circle.slash")
            .labelStyle(.iconOnly)
            .controlPlate()
    }
    .accessibilityLabel(SharedStrings.skipReminderAccessibility)
    .accessibilityIdentifier("skipButton")
    .accessibilityAddTraits(.isButton)
}
```

Leave the direct-skip `else` branch intact (still reachable when `canMutate` is
false); leave `actionMenuRescheduleReminder` and the `#if os(macOS)` half
untouched.

#### 4. Dispatch `.more` to the presenter; host the dialog
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Dispatch (`:459-467`):

```swift
.swipeToAct { outcome in
    switch outcome {
    case .complete:
        Task { await viewModel.completeCurrentReminder() }
    case .more:
        #if os(iOS)
            presentActionMenu()
        #else
            viewModel.skipCurrentReminder()
        #endif
    case .none:
        break
    }
}
```

Dialog host: add to the `body` modifier chain directly after the reschedule
`.sheet` (`:324-328`), as its own platform block:

```swift
#if os(iOS)
.confirmationDialog(SharedStrings.reminder, isPresented: $isShowingActionMenu) {
    actionMenuDialogButtons
}
#endif
```

`isShowingActionMenu` / `actionMenuReminder` are already internal `@State`
(`:129`,`:133`) so the root body and the sibling extension can both use them.

#### 5. Unit tests — swipe decision
**File**: `SingleThreadTests/SwipeGestureDecisionTests.swift`
**Action**: modify

- `leftPastThresholdSkips` → `leftPastThresholdShowsMore`, asserting
  `SwipeGesture.outcome(for: CGSize(width: -80, height: 0)) == .more`.
- `exactlyAtThresholdFires`: second assertion `-72` → `.more`.
- `negativeDragOffsetRevealsSkip` → `negativeDragOffsetRevealsMore`, asserting
  `SwipeGesture.revealedOutcome(forOffset: -12) == .more`.

#### 6. Unit tests — reveal panel (interim: still shows "Skip")
**File**: `SingleThreadTests/SwipeToActModifierTests.swift`
**Action**: modify

Only swap the case so the suite compiles; assertions stay "Skip"/trailing for
this phase:

- `skipPanelShowsSkipLabel`: `SwipeRevealPanel(outcome: .more, progress: 1)`,
  still `#expect(description.contains("Skip"))`.
- `skipPanelAnchorsPlateToTrailingEdge`:
  `#expect(SwipeRevealPanel.alignment(for: .more) == .trailing)`.
- `idleModifierWrapsContentWithoutPanel` unchanged.

#### 7. UI test — left swipe opens the menu
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify

Add after `testOverThresholdSwipeCompletesReminder` (mirrors its seed/geometry,
negative dx):

```swift
/// Left drag past the 72pt release threshold opens the shared action menu
/// instead of skipping. Direction/threshold logic is unit-tested; this test
/// exists because the gesture-layer presentation is not observable headlessly.
@MainActor
func testOverThresholdSwipeOpensActionMenu() throws {
    let app = XCUIApplication()
    app.launchArguments = [
        "--seed",
        // nolint:disable:line_length
        "{\"reminders\":[{\"title\":\"Milk\",\"priority\":5}],\"calendars\":[\"Groceries\"],\"isEntitled\":true}",
        "--ui-testing-noop-settle"
    ]
    app.launch()

    XCTAssertTrue(
        app.staticTexts["Milk"].waitForExistence(timeout: 5),
        "Seeded reminder should render")

    let card = app.descendants(matching: .any)["reminderCard"].firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5),
                  "Reminder card drag target should render")

    let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = start.withOffset(CGVector(dx: -110, dy: 0))
    start.press(
        forDuration: 0.1,
        thenDragTo: end,
        withVelocity: XCUIGestureVelocity(300),
        thenHoldForDuration: 0.1
    )

    XCTAssertTrue(
        app.buttons["rescheduleButton"].waitForExistence(timeout: 5),
        "A ~110pt left drag should open the action menu")
    XCTAssertTrue(app.buttons["deleteButton"].exists,
                  "Action menu should include the destructive Delete item")
}
```

>The `deleteButton` item may collapse into an overflow "…" list when the
>reminder is not marked destructive-critical; if the run shows only
>`rescheduleButton`, assert `app.buttons["Reschedule"].exists` instead and note
>it in the PR. Do not weaken the `rescheduleButton` assertion.

### Verification

#### Automated
- [x] `make build` passes
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` green
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeCompletesReminder` still green (right swipe unchanged)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeOpensActionMenu` green

#### Manual
- [ ] On `iPhone 17` simulator (`SIM=` pinned from `.simulator_id`): left-drag the card past ~half its width → the Skip / Reschedule / Delete action sheet appears; the card is not skipped (same reminder still visible after dismissing).
- [ ] Right-drag past threshold still completes the reminder.
- [ ] Under-threshold left drag and a vertical-dominant drag open nothing.
- [ ] Settings → action-buttons toggle **OFF**, relaunch: left swipe still opens the action sheet; the bottom bar shows the mic only. Tap Reschedule in that sheet → the reschedule sheet presents (no stuck dialog).
- [ ] Simultaneously drag left and release while the reminder is mid-scroll: List scrolling still works (vertical dominance guard).

---

## Phase 2: "More" — relabel the swipe surface and bottom-bar button

End to end: the reveal panel reads **More** with `ellipsis.circle.fill`, both
"More" triggers announce "More" to VoiceOver, and the key resolves in all six
shipped languages. The menu item stays "Skip".

### Changes

#### 1. Add the shared key accessor
**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify

Add next to `skipAction` (`:31`):

```swift
/// "More" — the left-swipe reveal label, the swipe accessibility action, and
/// the bottom-bar action button's accessibility label. Opens the shared
/// Skip/Reschedule/Delete menu; the menu's Skip item keeps `skipAction`.
public static var moreAction: LocalizedStringResource {
    LocalizedStringResource("More", table: "Localizable", bundle: .module)
}
```

Keep `skipAction` (still the dialog item title and the bottom-bar visual label).

#### 2. Catalogue "More" in the Core String Catalog
**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify

Insert this key alphabetically between `"Monthly"` and `"No Reminders"` (match
the file's existing formatting; no trailing commas):

```json
"More" : {
  "extractionState" : "manual",
  "localizations" : {
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Mehr" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "More" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Más" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Plus" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "その他" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "更多" } }
  }
},
```

(Existing entries place `en` first then the rest; either ordering is legal —
Xcode normalises on save. Match the `"Skip"` entry's locale set exactly:
`en, zh-Hans, es, ja, de, fr`.) Validate with:

```bash
python3 -c "import json; json.load(open('SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings'))"
```

#### 3. Relabel the reveal panel and swipe a11y action
**File**: `SingleThread/SwipeToActModifier.swift`
**Action**: modify

Add a testable glyph mapping beside `alignment(for:)`:

```swift
/// SF Symbol for the revealed direction. Extracted alongside `alignment(for:)`
/// because a runtime `systemImage` string is not recoverable from SwiftUI's
/// reflected view description.
static func systemImage(for outcome: SwipeGestureOutcome) -> String {
    switch outcome {
    case .complete: "checkmark.circle.fill"
    case .more: "ellipsis.circle.fill"
    case .none: "circle"
    }
}
```

`.more` presentation arm becomes:

```swift
case .more:
    Presentation(
        title: SharedStrings.moreAction,
        systemImage: Self.systemImage(for: outcome),
        tint: CardPlate.skipHintColor(for: colorScheme))
```

a11y action:

```swift
.accessibilityAction(named: Text(SharedStrings.moreAction)) {
    onOutcome(.more)
}
```

Update the file/`swipeToAct` doc comments ("drag-to-skip (left)" →
"drag-to-more (left)"; the header comment's "Complete/Skip hint colours" →
"Complete/More"). Keep `CardPlate.skipHintColor` (design decision 4).

#### 4. Relabel the bottom-bar button for VoiceOver
**File**: `SingleThread/ContentView+ActionMenu.swift`
**Action**: modify

In `skipButton`, `.accessibilityLabel(SharedStrings.skipReminderAccessibility)`
→ `.accessibilityLabel(SharedStrings.moreAction)`. Keep the
`"skipButton"` identifier (the smoke test queries it) and keep the visual
`Label(SharedStrings.skipAction, systemImage: "circle.slash")`.

#### 5. Unit tests — reveal panel final state
**File**: `SingleThreadTests/SwipeToActModifierTests.swift`
**Action**: modify

- `skipPanelShowsSkipLabel` → `morePanelShowsMoreLabel`:
  `#expect(description.contains("More"))` and
  `#expect(description.contains("CardPlateModifier"))`.
- Add `morePanelUsesEllipsisGlyph`:
  `#expect(SwipeRevealPanel.systemImage(for: .more) == "ellipsis.circle.fill")`.
- `skipPanelAnchorsPlateToTrailingEdge` → `morePanelAnchorsPlateToTrailingEdge`
  (assertion already `.more == .trailing`).
- `idleModifierWrapsContentWithoutPanel`:
  `!description.contains("Skip")` → `!description.contains("More")`.
- `completePanelShowsCompleteLabel` unchanged (sad path: complete untouched).

#### 6. Unit tests — localization fixtures
**File**: `SingleThreadTests/AppLanguageTests.swift`
**Action**: modify

Extend `localizedStringResourceResolvesInExplicitLocale`:
```swift
let more = LocalizedStringResource("More", table: "Localizable", bundle: Bundle.core)
#expect(more.resolved(in: Locale(identifier: "de")) == "Mehr")
#expect(more.resolved(in: Locale(identifier: "fr")) == "Plus")
```

Add a sibling all-locale test:
```swift
@Test
func moreActionResolvesToEveryShippedLanguage() {
    let expected: [String: String] = [
        "en": "More", "zh-Hans": "更多", "es": "Más",
        "ja": "その他", "de": "Mehr", "fr": "Plus"
    ]
    for (identifier, value) in expected {
        #expect(
            SharedStrings.moreAction.resolved(in: Locale(identifier: identifier)) == value,
            "More in \(identifier)")
    }
}
```

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green
- [x] `scripts/test-one.sh SingleThreadTests/AppLanguageTests` green (all six locales resolve)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeOpensActionMenu` still green

#### Manual
- [ ] Swipe left partway on the card: the reveal plate at the trailing edge reads **More** with an ellipsis-in-circle glyph.
- [ ] VoiceOver on the card: the left-swipe rotor action is announced "More"; the bottom-bar action button announces "More"; inside the opened menu the first item is still announced "Skip".
- [ ] Switch the language picker to Deutsch/日本語/Français: the reveal plate reads Mehr/その他/Plus.

---

## Phase 3: Hardening & verification

No new capability. Prove the two slices hold under the accessibility audit, the
lint/periphery gates, and the one-shot full gate. No files expected to change;
small a11y/label fixes only if a check demands one.

### Changes

None anticipated. **Do not delete** the direct-skip `else` branch in
`ContentView+ActionMenu.swift` (still the `canMutate == false` path).

### Verification

#### Automated
- [x] `make format` then `make lint` clean (SwiftFormat + `swiftlint --strict`)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` green — the smoke's `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` re-passes with the renamed labels and the relocated dialog
- [x] `rm -rf DerivedData && make periphery` clean after a fresh build index (the new `moreAction` accessor and `systemImage(for:)` must show as used)
- [ ] Full `./scripts/test.sh` run ONCE via the `run-gate` skill (never `nohup`; phase subagents must not re-run it)

#### Manual
- [ ] Swipe left: the reveal plate animates back to offset 0 and does **not** linger/restart under the presented action sheet.
- [ ] With the toggle OFF, swipe-open menu still works, and `enableActionButtons` still hides only the bottom-bar cluster (Settings toggle ON/OFF round-trip).
- [ ] `canMutate == false` (e.g. reminders access revoked) + left swipe: no crash; the gate-redirect path behaves as before.
- [ ] VoiceOver full pass: card, action button, and dialog items all announce sensibly; nothing announces "Skip" on the two "More" triggers.

---

## Testing Checkpoints (from `structure.md`)

- **After Phase 1**: `SwipeGestureDecisionTests` green and the swipe-open-menu
  UI test green; no Phase 2 work until the dispatch + presenter path is proven.
- **After Phase 2**: `SwipeToActModifierTests` green (More + ellipsis + trailing)
  and `AppLanguageTests` green for all six locales; no Phase 3 until the key
  resolves everywhere.
- **After Phase 3**: smoke a11y audit, `make lint`, and `make periphery` clean;
  then hand off to the one-shot full gate. If the Phase 1 swipe UI test fails
  twice, CI is authority.

## Deviations from `structure.md`

1. **Dialog host moved to `ContentView.body`** (not stated in the outline).
   Required because the outline's "swipe always opens the menu" (design
   decision 2) cannot present a dialog bound to the conditionally-rendered
   `skipButton`. The button list is extracted to `actionMenuDialogButtons`;
   still one binding, one presenter.
2. **macOS dispatch branch added.** `.swipeToAct` compiles for macOS, so the
   `case .more` arm must fall back to `skipCurrentReminder()` there to keep
   macOS behaviorally unchanged.
3. **`SwipeRevealPanel.systemImage(for:)` extracted** so the glyph can be
   asserted — a runtime `systemImage` string is not recoverable from SwiftUI's
   reflected view description, which the existing reflection tests rely on.
