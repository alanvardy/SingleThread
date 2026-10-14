# Implementation Plan

## Overview

Remap the reminder-card swipe (right → Complete, left → Skip, up → open the
existing action menu) by extending the pure `SwipeGesture` rule and the
`SwipeToActModifier` drag, then rewire the card's `onOutcome` switch. Separately,
replace the below-card swipe-prompt plate with a directional guide (an up arrow
above the card; left/right arrow labels below it), reusing the existing
`"Swipe left to skip"` / `"Swipe right to complete"` catalog keys and adding one
new `"Swipe up for more"` key in all six languages.

Decisions locked in the frontier grill: **(Q1a)** the up case lives in the pure
`SwipeGesture` rule — an `upReleaseDistance = 96` threshold plus strict vertical
dominance (`|dy| > 2·|dx|`) — rather than a new gesture stack; **(Q2a)** the new
mapping applies on iOS *and* macOS (one shared rule, no `#if` branches);
**(Q3a)** reuse the two existing side-arrow strings, add exactly one new key,
and keep the inline Dismiss button plus its accessibility identifiers.

No schema, storage, API, entitlement or dependency changes. The watch app does
not use the card swipe. `showSwipePrompt` remains iOS-only and its settings
toggle/caption copy is unchanged (renaming it would force another 5-language
catalog change for no ticket value).

---

## Phase 1: Gesture remap — right complete, left skip, up more

Thinnest end-to-end path: the pure rule classifies the new directions, the
modifier tracks the full drag translation and reveals the right panel, and
`ContentView` routes `.skip` to the model and `.more` to the action menu.

### Changes

#### 1. Pure swipe rule
**File**: `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift`
**Action**: modify

Add a `.skip` case, repoint `.more` at the upward direction, and add the up
threshold:

```swift
/// Which action a released row swipe should fire, if any.
public enum SwipeGestureOutcome: Equatable {
    case complete
    case skip
    case more
    case none
}
```

```swift
public nonisolated enum SwipeGesture {
    /// Horizontal travel (pt) past which a release fires the action — roughly
    /// half the stock `.swipeActions` full-swipe distance it replaces.
    public static let releaseDistance: CGFloat = 72

    /// Upward travel (pt) past which a steep release opens the action menu.
    /// Longer than `releaseDistance` because a vertical drag is attached
    /// simultaneously with `List` scrolling/rubber-banding, so an incidental
    /// scroll must not trip it.
    public static let upReleaseDistance: CGFloat = 96

    /// Classifies a released drag translation. Horizontal-dominant drags map
    /// right → complete, left → skip. A steep upward drag (`dy` past
    /// `upThreshold` and more than twice the horizontal travel) → more.
    /// Downward and shallow vertical drags are ignored so `List` scrolling and
    /// pull-to-refresh win.
    public static func outcome(
        for translation: CGSize,
        threshold: CGFloat = releaseDistance,
        upThreshold: CGFloat = upReleaseDistance) -> SwipeGestureOutcome {
        let dx = translation.width
        let dy = translation.height
        if dy <= -upThreshold, abs(dy) > 2 * abs(dx) {
            return .more
        }
        guard abs(dy) <= abs(dx) else { return .none }
        if dx >= threshold { return .complete }
        if dx <= -threshold { return .skip }
        return .none
    }

    /// Which reveal direction a live drag offset maps to: right → complete,
    /// left → skip, a steep upward drag → more, zero → nothing.
    public static func revealedOutcome(forOffset offset: CGSize) -> SwipeGestureOutcome {
        let dx = offset.width
        let dy = offset.height
        if dy < 0, abs(dy) > 2 * abs(dx) { return .more }
        if dx > 0 { return .complete }
        if dx < 0 { return .skip }
        return .none
    }
}
```

Note: `revealedOutcome(forOffset:)` changes from `CGFloat` to `CGSize` — its
only callers are the modifier and its tests.

#### 2. Drag modifier + reveal panel
**File**: `SingleThread/SwipeToActModifier.swift`
**Action**: modify

Track the full translation; lift the card only upward; add the `.skip` panel and
a `.bottom` anchor for the up reveal:

```swift
@State private var dragOffset: CGSize = .zero

func body(content: Content) -> some View {
    ZStack {
        if revealedOutcome != .none {
            SwipeRevealPanel(outcome: revealedOutcome, progress: progress)
        }
        content
            .contentShape(Rectangle())
            .offset(x: dragOffset.width, y: min(dragOffset.height, 0))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let outcome = SwipeGesture.outcome(
                            for: value.translation,
                            threshold: threshold)
                        withAnimation(.snappy) { dragOffset = .zero }
                        if outcome != .none {
                            onOutcome(outcome)
                        }
                    })
            .accessibilityAction(named: Text(SharedStrings.completeAction)) {
                onOutcome(.complete)
            }
            .accessibilityAction(named: Text(SharedStrings.skipAction)) {
                onOutcome(.skip)
            }
            .accessibilityAction(named: Text(SharedStrings.moreAction)) {
                onOutcome(.more)
            }
            .accessibilityIdentifier("reminderCard")
    }
}

/// `max(|dx|, |dy|) / threshold`, capped at 1 — the panel's reveal intensity.
/// The denominator is floored at 1 so a zero threshold cannot divide by zero.
private var progress: CGFloat {
    min(max(abs(dragOffset.width), abs(dragOffset.height)) / max(threshold, 1), 1)
}

private var revealedOutcome: SwipeGestureOutcome {
    SwipeGesture.revealedOutcome(forOffset: dragOffset)
}
```

`SwipeRevealPanel`'s extracted decisions become:

```swift
static func alignment(for outcome: SwipeGestureOutcome) -> Alignment {
    switch outcome {
    case .complete: .leading
    case .skip: .trailing
    case .more: .bottom
    case .none: .leading
    }
}

static func systemImage(for outcome: SwipeGestureOutcome) -> String {
    switch outcome {
    case .complete: "checkmark.circle.fill"
    case .skip: "arrow.left.circle.fill"
    case .more: "ellipsis.circle.fill"
    case .none: "circle"
    }
}
```

`presentation` gains a `.skip` arm and keeps `.more` on the existing strings and
tints:

```swift
case .complete:
    Presentation(
        title: SharedStrings.completeAction,
        systemImage: Self.systemImage(for: outcome),
        tint: CardPlate.completeHintColor(for: colorScheme))
case .skip:
    Presentation(
        title: SharedStrings.skipAction,
        systemImage: Self.systemImage(for: outcome),
        tint: CardPlate.skipHintColor(for: colorScheme))
case .more:
    Presentation(
        title: SharedStrings.moreAction,
        systemImage: Self.systemImage(for: outcome),
        tint: CardPlate.skipHintColor(for: colorScheme))
case .none:
    Presentation(
        title: SharedStrings.completeAction,
        systemImage: "circle",
        tint: .clear)
```

Update the file's top doc comments: `SwipeToActModifier` now tracks full travel;
the `swipeToAct` extension comment becomes "drag-to-complete (right) /
drag-to-skip (left) / drag-to-more (up)".

#### 3. Card outcome routing
**File**: `SingleThread/ContentView.swift`
**Action**: modify (the `.swipeToAct { … }` block, ~L463)

```swift
.swipeToAct { outcome in
    switch outcome {
    case .complete:
        Task { await viewModel.completeCurrentReminder() }
    case .skip:
        viewModel.skipCurrentReminder()
    case .more:
        presentActionMenu()
    case .none:
        break
    }
}
```

#### 4. Comment-only doc corrections
**Files**:
- `SingleThread/ContentView+ActionMenu.swift` (`presentActionMenu()` doc, ~L28-32): "left-swipe `.more`" → "up-swipe `.more`".
- `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` (`moreAction` doc, ~L36): "the left-swipe reveal label" → "the up-swipe reveal label".
- `SingleThread/CardPlate.swift` (`skipHintColor` doc, ~L27): keep the "Swipe left to skip" reference (still accurate in Spotter's guide) but note it also tints the revealed skip panel; `completeHintColor` doc unchanged.

#### 5. Pure-rule tests
**File**: `SingleThreadTests/SwipeGestureDecisionTests.swift`
**Action**: modify

Rename/repurpose and add cases (`leftPastThresholdShowsMore` → skip; the
vertical-dominance fixture keeps its `.none` expectation for down-drags):

```swift
@Test
func leftPastThresholdSkips() {
    #expect(SwipeGesture.outcome(for: CGSize(width: -80, height: 0)) == .skip)
}

@Test
func upPastThresholdOpensMore() {
    #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -100)) == .more)
}

@Test
func upBelowThresholdDoesNothing() {
    #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -80)) == .none)
}

@Test
func shallowUpIsIgnored() {
    // Past the up threshold but not steep enough (|dy| <= 2·|dx|) — a scroll,
    // not a command.
    #expect(SwipeGesture.outcome(for: CGSize(width: 60, height: -100)) == .none)
}

@Test
func upExactlyAtThresholdFires() {
    #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -96)) == .more)
}
```

Update the existing `exactlyAtThresholdFires` left case to `.skip`, and convert
the three `revealedOutcome(forOffset:)` fixtures to `CGSize`:

```swift
#expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 12, height: 0)) == .complete)
#expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: -12, height: 0)) == .skip)
#expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 0, height: -60)) == .more)
#expect(SwipeGesture.revealedOutcome(forOffset: CGSize.zero) == .none)
```

`verticalDominantDragDoesNothing`, `underThresholdDoesNothing`,
`horizontalEqualToVerticalIsNotVerticalDominant`, and the threshold-override
test keep their existing bodies.

#### 6. Reveal-panel tests
**File**: `SingleThreadTests/SwipeToActModifierTests.swift`
**Action**: modify

- `morePanelUsesEllipsisGlyph` unchanged.
- `morePanelAnchorsPlateToTrailingEdge` → `morePanelAnchorsPlateToBottomEdge`
  (`#expect(SwipeRevealPanel.alignment(for: .more) == .bottom)`).
- Add `skipPanelShowsSkipLabel` (`SwipeRevealPanel(outcome: .skip, progress: 1)`
  description contains `"Skip"` and `"CardPlateModifier"`).
- Add `skipPanelUsesLeftArrowGlyph`
  (`SwipeRevealPanel.systemImage(for: .skip) == "arrow.left.circle.fill"`).
- Add `skipPanelAnchorsPlateToTrailingEdge`
  (`#expect(SwipeRevealPanel.alignment(for: .skip) == .trailing)`).
- `completePanelShowsCompleteLabel`, `completePanelAnchorsPlateToLeadingEdge`,
  `idleModifierWrapsContentWithoutPanel` unchanged.

#### 7. UI tests
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify

Justification (AGENTS.md UI-test policy): the gesture → action routing through
`List` + `.simultaneousGesture` is not observable from unit tests, and this
suite already owns the swipe end-to-end coverage.

- `testOverThresholdSwipeCompletesReminder` — unchanged.
- Replace `testOverThresholdSwipeOpensActionMenu` with
  `testOverThresholdSwipeLeftSkips`: same `--seed` launch and ~110pt **left**
  drag, but assert the reminder is gone instead of the menu:

  ```swift
  XCTAssertFalse(app.buttons["rescheduleButton"].waitForExistence(timeout: 2),
                 "Left swipe must skip, not open the action menu")
  let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: app.staticTexts["Milk"])
  XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                 "A ~110pt left drag should skip the reminder")
  ```

- Add `testOverThresholdSwipeUpOpensActionMenu`: same seed, drag
  `CGVector(dx: 0, dy: -130)` with a slow velocity + release hold, then assert
  `app.buttons["rescheduleButton"]` and `app.buttons["deleteButton"]` exist.

### Verification

#### Automated
- [x] `make format` then `make lint` pass (`swiftlint lint --strict` clean)
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` passes
- [x] `make build` succeeds (warnings are errors) and `make mac-build` succeeds
- [ ] Full gate runs once after the phases via the `run-gate` skill; it must run
      `SingleThreadUITests/testOverThresholdSwipeCompletesReminder`,
      `testOverThresholdSwipeLeftSkips`, and
      `testOverThresholdSwipeUpOpensActionMenu` green

#### Manual
- [ ] iPhone: right-drag completes; left-drag replaces the card with the next
      reminder (or the empty state on a single-reminder seed); up-drag opens the
      Skip / Reschedule / Delete menu
- [ ] Downward drag and pull-to-refresh still scroll without opening the menu;
      a shallow diagonal drag fires nothing
- [ ] VoiceOver rotor on the card offers Complete, Skip and More
- [ ] macOS: same three directions behave the same way on the card

---

## Phase 2: Directional-arrow swipe guide

Replace the below-card swipe-prompt plate with arrows and action labels placed
around the card, reusing the two existing side labels and adding the new
up-swipe string in all six languages.

### Changes

#### 1. Card guide layout
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

`body` gains the up guide above the plate and the left/right guide row plus the
dismiss button below it (the card plate keeps its exact current composition):

```swift
var body: some View {
    VStack(spacing: 12) {
        if showSwipePrompt {
            upGuide
        }
        VStack(alignment: .leading, spacing: 4) {
            content
            if showNudge {
                nudgeBanner
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)

        if showSwipePrompt {
            horizontalGuide
            dismissButton
        }
    }
    .frame(maxWidth: maxWidth)
}
```

Replace the old `prompt` view (`~L200-243`) with the three pieces:

```swift
/// `↑ Swipe up for more`, centred above the card. Visual-only: the copy is
/// hidden from accessibility (VoiceOver users get the card's swipe actions).
private var upGuide: some View {
    VStack(spacing: 2) {
        Image(systemName: "arrow.up")
        Text("Swipe up for more")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityHidden(true)
}

/// `← Swipe left to skip` and `Swipe right to complete →`, one row below the
/// card, arrow on the outer edge of each side and tinted like its revealed
/// panel. Visual-only.
private var horizontalGuide: some View {
    HStack {
        HStack(spacing: 4) {
            Image(systemName: "arrow.left")
            Text("Swipe left to skip")
        }
        .foregroundStyle(CardPlate.skipHintColor(for: colorScheme))

        Spacer(minLength: 8)

        HStack(spacing: 4) {
            Text("Swipe right to complete")
            Image(systemName: "arrow.right")
        }
        .foregroundStyle(CardPlate.completeHintColor(for: colorScheme))
    }
    .font(.caption)
    .accessibilityHidden(true)
}
```

`dismissButton` is the existing Dismiss button lifted verbatim out of `prompt`:
same `showSwipePrompt = false` write, `Text("Dismiss")`, caption-bold,
bordered-prominent, `.tint`, vertical padding for the 44pt hit region,
`.accessibilityLabel("Dismiss swipe prompt")` and
`.accessibilityIdentifier("swipePromptDismissButton")`.

`CardPlate` reuse note: the guide is now plain text/arrows rather than its own
plate, so the `cardPlate` fill used by the guide is intentionally dropped; the
card plate is unchanged.

#### 2. Localization
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Add exactly one key, `"Swipe up for more"`, with all six languages filled in
(`LocalizationTests.catalogsHaveAllSixLanguages` and
`nonEnglishValuesDifferFromEnglish` are the gates). Source English plus
translations for review:

| lang | value |
| --- | --- |
| en | Swipe up for more |
| de | Nach oben wischen für mehr |
| es | Desliza hacia arriba para más |
| fr | Balayez vers le haut pour plus |
| ja | 上にスワイプしてその他 |
| zh-Hans | 上滑查看更多 |

`"Swipe left to skip"` and `"Swipe right to complete"` already carry all six
languages and are reused verbatim. No `SharedStrings` accessor is added — the
guide is iOS-only and rendered in the app target, so the raw `Text` key + app
catalog is the existing pattern.

#### 3. Guide tests
**File**: `SingleThreadTests/SwipePromptTests.swift`
**Action**: modify

- `promptShownWhenEnabled` → also assert `"Swipe up for more"` is present, and
  keep the document-order check, extended so the up label precedes the side row:

  ```swift
  #expect(description.contains("Swipe up for more"))
  #expect(description.contains("Swipe left to skip"))
  #expect(description.contains("Swipe right to complete"))
  #expect(description.contains("Dismiss"))
  #expect(description.contains("CardPlateModifier"))
  if let up = description.range(of: "Swipe up for more"),
     let complete = description.range(of: "Swipe right to complete"),
     let skip = description.range(of: "Swipe left to skip") {
      #expect(up.lowerBound < complete.lowerBound)
      #expect(complete.lowerBound < skip.lowerBound)
  } else {
      Issue.record("Expected all three swipe guide labels in the prompt body")
  }
  ```

- `promptHiddenWhenDisabled` → assert none of the three labels appear.
- `dismissButtonHasAccessibilityLabel` unchanged (still `Button<`,
  `BorderedProminentButtonStyle`, `AccessibilityAttachmentModifier`).

### Verification

#### Automated
- [x] `make format` then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadTests/SwipePromptTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (new key
      resolves in all six languages and its non-English values differ)
- [x] `make test` (unit-only gate) passes
- [ ] `make ui-test` in the post-phase gate still passes the accessibility audit

#### Manual
- [ ] iPhone, guide enabled: `↑` + "Swipe up for more" sits above the card;
      "← Swipe left to skip" and "Swipe right to complete →" render as one row
      below it in orange/green; Dismiss hides all of it
- [ ] Settings → Interface → "Show swipe prompt" off hides the whole guide
- [ ] Large Dynamic Type (AX5): the guide wraps without truncating and the card
      content is not clipped
- [ ] VoiceOver skips the guide copy but still reaches the Dismiss button

---

## Full gate (after both phases commit)

- [ ] Run `./scripts/test.sh` exactly once through the `run-gate` skill (never
      `nohup`d); it must pass on both the iPhone 17 and iPad (A16) matrix legs
- [ ] Confirm `git status` shows no `.pi/orksorksorks/` artifacts folded into a
      source commit
- [ ] PR body states why the swipe UI tests were extended (gesture-layer
      routing is not observable from unit tests)
