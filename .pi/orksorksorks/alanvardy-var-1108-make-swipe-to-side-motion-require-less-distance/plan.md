# Implementation Plan

## Overview

The iOS reminder card fires Complete (drag right) / Skip (drag left) once the
finger is released past a fixed **72pt** horizontal threshold — roughly half the
current full-swipe distance — while the card follows the finger, a tinted
Complete/Skip panel reveals behind it, vertical-dominant drags are ignored so
`List` scroll / pull-to-refresh keep working, and VoiceOver keeps named
Complete/Skip actions. Plain SwiftUI, no `#if os(iOS)` in the gesture path, with
the direction/threshold/dominance rule extracted into a pure, host-testable
helper. `.swipeActions` is removed entirely.

All unit test files live in the existing `SingleThreadTests` target and the UI
test in `SingleThreadUITests`; no new target, scheme, `test.sh` or CI wiring is
needed (both are run whole-target: `-only-testing:SingleThreadTests` /
`-only-testing:SingleThreadUITests`). `SingleThread/CardPlate.swift` (not Core)
owns the hint colours; `SharedStrings.completeAction` / `.skipAction` already
exist — **no new localisation keys**.

Resolved open risk from design/`research.md`: `testLaunchAndRenderSmoke`
(`SingleThreadUITests/SingleThreadUITests.swift:43-67`) asserts
`completeButton` / `skipButton`, which are the `actionCluster` in `bottomBar`
(`ContentView.swift:532-553,701-757`), **not** the `.swipeActions` buttons —
removing `.swipeActions` does not break it.

---

## Phase 1: Walking skeleton — half-distance drag fires Complete/Skip end to end

The user can drag the reminder card ~72pt left/right and release to fire Skip /
Complete exactly once; under-threshold and vertical-dominant drags do nothing.
The `.swipeActions` blocks are gone. This front-loads the riskiest unknown (Q3:
custom row `DragGesture` coexisting with `List` scroll / `.refreshable`).

### Changes

#### 1. Pure decision helper
**File**: `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift`
**Action**: create

Mirror `SkipCountLogic` (`SkipCountStore.swift:3-8`): a small `nonisolated`
namespace with a `static let` threshold and a pure function. No EventKit/UI
dependencies, so it is host-testable.

```swift
import CoreGraphics

/// Which action a released row swipe should fire, if any.
public enum SwipeGestureOutcome: Equatable {
    case complete
    case skip
    case none
}

/// Pure direction/threshold rule for the reminder-card swipe. Extracted from the
/// row so the trigger distance is unit-testable without a gesture runtime.
public nonisolated enum SwipeGesture {
    /// Horizontal travel (pt) past which a release fires the action — roughly
    /// half the stock `.swipeActions` full-swipe distance it replaces.
    public static let releaseDistance: CGFloat = 72

    /// Classifies a released drag translation. A vertical-dominant drag
    /// (`|dy| > |dx|`) is ignored so `List` scrolling/pull-to-refresh win.
    public static func outcome(
        for translation: CGSize,
        threshold: CGFloat = releaseDistance) -> SwipeGestureOutcome {
        guard abs(translation.height) <= abs(translation.width) else { return .none }
        if translation.width >= threshold { return .complete }
        if translation.width <= -threshold { return .skip }
        return .none
    }
}
```

#### 2. Row: remove `.swipeActions`, attach the drag gesture
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**2a.** Add drag state alongside the other `private` `@State` properties (anchor:
`@State private var isShowingSettings = false`, `:351`):

```swift
    @State private var dragOffset: CGFloat = 0
```

**2b.** In the `.reminder` arm, on the `ReminderCardView(...)` call
(`:446-457`) insert the offset/gesture **immediately after the initializer's
closing paren and before `.listRowBackground(...)`** (`:459`). Attaching it here
(inside the 40pt row padding / full-height frame) means only the card moves, not
the whole row:

```swift
                            ReminderCardView(
                                /* …unchanged args… */
                                maxWidth: CardWidth.maxContentWidth(viewportWidth: geometry.size.width))
                                .contentShape(Rectangle())
                                .offset(x: dragOffset)
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            dragOffset = value.translation.width
                                        }
                                        .onEnded { value in
                                            let outcome = SwipeGesture.outcome(for: value.translation)
                                            dragOffset = 0
                                            switch outcome {
                                            case .complete:
                                                Task { await viewModel.completeCurrentReminder() }
                                            case .skip:
                                                viewModel.skipCurrentReminder()
                                            case .none:
                                                break
                                            }
                                        })
                                .listRowBackground(viewModel.rowChromeBackground)
```

`simultaneousGesture` (not `.gesture`) lets the `List` pan recognizer keep
running, which is how scroll/pull-to-refresh survive. `minimumDistance: 10`
keeps taps (Dismiss, nudge) working.

**2c.** Delete both `.swipeActions` blocks (`:488-494` leading/complete and
`:496-503` trailing/skip) entirely — including the now-unused
`SharedStrings.completeAction`/`skipAction` `Label`s at those lines. Do **not**
touch the `#if os(iOS) .contextMenu { … }` block directly above them.

#### 3. Decision tests
**File**: `SingleThreadTests/SwipeGestureDecisionTests.swift`
**Action**: create

Swift Testing, `@testable import SingleThread` + `import SingleThreadCore`;
names must not start with `test`/`testing` (SwiftFormat strips the prefix). This
runs in `SingleThreadTests`, exercised on iOS-sim by `test-one.sh` and on macOS
by `make test`.

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

/// Threshold/direction/dominance rule for the reminder-card swipe. Pure logic,
/// so it is pinned independently of any live gesture runtime.
struct SwipeGestureDecisionTests {
    @Test
    func rightPastThresholdCompletes() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 80, height: 0)) == .complete)
    }

    @Test
    func leftPastThresholdSkips() {
        #expect(SwipeGesture.outcome(for: CGSize(width: -80, height: 0)) == .skip)
    }

    @Test
    func underThresholdDoesNothing() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 40, height: 0)) == .none)
        #expect(SwipeGesture.outcome(for: CGSize(width: -40, height: 0)) == .none)
    }

    @Test
    func verticalDominantDragDoesNothing() {
        // Little horizontal travel, lots of vertical: a scroll, not a swipe.
        #expect(SwipeGesture.outcome(for: CGSize(width: 100, height: 130)) == .none)
        #expect(SwipeGesture.outcome(for: CGSize(width: -100, height: -130)) == .none)
    }

    @Test
    func horizontalEqualToVerticalIsNotVerticalDominant() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 100, height: 100)) == .complete)
    }

    @Test
    func exactlyAtThresholdFires() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 72, height: 0)) == .complete)
        #expect(SwipeGesture.outcome(for: CGSize(width: -72, height: 0)) == .skip)
    }

    @Test
    func customThresholdOverrideIsHonoured() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 30, height: 0), threshold: 20) == .complete)
        #expect(SwipeGesture.outcome(for: CGSize(width: 30, height: 0), threshold: 50) == .none)
    }
}
```

### Verification

#### Automated
- [x] `make format` then `make lint` clean (SwiftFormat + SwiftLint `--strict`)
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests`
      green (uses `.simulator_id` = `6F5F8C04-4CC2-4B11-8171-EC9D4F4DCAD7`)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke`
      green — proves the removed `.swipeActions` did not back
      `completeButton`/`skipButton`
- [x] `make build` succeeds

#### Manual
- [ ] On the iOS sim (`SIM=platform=iOS Simulator,id=6F5F8C04-4CC2-4B11-8171-EC9D4F4DCAD7`):
      drag the card ~72pt right → Complete fires once; drag left → Skip fires
      once; drag ~30pt → nothing, card returns to centre
- [ ] Vertical scroll of the card area still scrolls; pull-to-refresh still
      triggers `reload()`; Dismiss on the prompt and the nudge banner still tap

---

## Phase 2: Reveal affordance — card follows finger behind a tinted hint panel

While dragging, the card translates with the finger, a tinted Complete/Skip
panel reveals behind it and intensifies toward the threshold; release always
animates the card back to zero (no stuck-open state). The gesture is extracted
into one reusable modifier.

### Changes

#### 1. Reveal panel + modifier
**File**: `SingleThread/SwipeToActModifier.swift`
**Action**: create

Reuses `CardPlate.plateFill(for:)` + `CardPlate.completeHintColor` /
`skipHintColor(for:)` so the reveal reads as the same vocabulary as the prompt
(`ReminderCardView.swift:177-224`). No `#if os(iOS)` — this file is compiled for
the macOS-host unit target, so it must stay cross-platform.

```swift
import SingleThreadCore
import SwiftUI

/// Tinted hint panel revealed behind the card while a swipe is in progress.
/// Fill matches the prompt plate; icon+label take the adaptive Complete/Skip
/// hint colours, and opacity scales with `progress` so it intensifies toward
/// the threshold.
struct SwipeRevealPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let outcome: SwipeGestureOutcome
    let progress: CGFloat

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardPlate(fill: CardPlate.plateFill(for: colorScheme))
            .opacity(Double(progress))
    }

    private var title: LocalizedStringResource {
        switch outcome {
        case .complete: SharedStrings.completeAction
        case .skip: SharedStrings.skipAction
        // Never rendered: the modifier omits the panel for `.none`.
        case .none: SharedStrings.completeAction
        }
    }

    private var systemImage: String {
        switch outcome {
        case .complete: "checkmark.circle.fill"
        case .skip: "circle.slash"
        case .none: "circle"
        }
    }

    private var tint: Color {
        switch outcome {
        case .complete: CardPlate.completeHintColor(for: colorScheme)
        case .skip: CardPlate.skipHintColor(for: colorScheme)
        case .none: .clear
        }
    }
}

/// Drag-to-act behaviour for the reminder card: tracks horizontal travel,
/// reveals `SwipeRevealPanel` behind the card, fires `onOutcome` on release past
/// `threshold`, and always animates the card back to zero.
struct SwipeToActModifier: ViewModifier {
    @State private var dragOffset: CGFloat = 0

    let threshold: CGFloat
    let onOutcome: (SwipeGestureOutcome) -> Void

    init(
        threshold: CGFloat = SwipeGesture.releaseDistance,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) {
        self.threshold = threshold
        self.onOutcome = onOutcome
    }

    /// `|dx| / threshold`, capped at 1 — the panel's reveal intensity.
    private var progress: CGFloat {
        min(abs(dragOffset) / threshold, 1)
    }

    private var revealedOutcome: SwipeGestureOutcome {
        if dragOffset > 0 { .complete }
        else if dragOffset < 0 { .skip }
        else { .none }
    }

    func body(content: Content) -> some View {
        ZStack {
            if revealedOutcome != .none {
                SwipeRevealPanel(outcome: revealedOutcome, progress: progress)
            }
            content
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let outcome = SwipeGesture.outcome(
                                for: value.translation,
                                threshold: threshold)
                            withAnimation(.snappy) { dragOffset = 0 }
                            if outcome != .none { onOutcome(outcome) }
                        })
        }
    }
}

extension View {
    /// Adds drag-to-complete (right) / drag-to-skip (left) with a reveal panel
    /// behind the view and a fixed release threshold.
    func swipeToAct(
        threshold: CGFloat = SwipeGesture.releaseDistance,
        onOutcome: @escaping (SwipeGestureOutcome) -> Void) -> some View {
        modifier(SwipeToActModifier(threshold: threshold, onOutcome: onOutcome))
    }
}
```

#### 2. ContentView: swap the inline gesture for the modifier
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Remove the Phase-1 `@State private var dragOffset: CGFloat = 0`. Replace the
Phase-1 `.contentShape(Rectangle())` / `.offset(x: dragOffset)` /
`.simultaneousGesture(...)` chain on the card with:

```swift
                                .swipeToAct { outcome in
                                    switch outcome {
                                    case .complete:
                                        Task { await viewModel.completeCurrentReminder() }
                                    case .skip:
                                        viewModel.skipCurrentReminder()
                                    case .none:
                                        break
                                    }
                                }
                                .listRowBackground(viewModel.rowChromeBackground)
```

#### 3. Modifier / panel reflection tests
**File**: `SingleThreadTests/SwipeToActModifierTests.swift`
**Action**: create

Same view-reflection pattern as `SwipePromptTests.swift:7-64`. `SwipeRevealPanel`
is internal (`@testable import SingleThread`) and `CardPlateModifier` is asserted
present because `.cardPlate(...)` draws the panel fill — SwiftUI does not inline
a `ViewModifier`'s body into the host's static type, the modifier's name appears
in the reflected chain.

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

/// Reflection coverage for the swipe reveal panel: the direction selects the
/// Complete/Skip label, and the `.none` modifier body renders no panel.
@MainActor
struct SwipeToActModifierTests {
    @Test
    func completePanelShowsCompleteLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .complete, progress: 1).body)
        #expect(description.contains("Complete"))
        #expect(description.contains("CardPlateModifier"))
    }

    @Test
    func skipPanelShowsSkipLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .skip, progress: 1).body)
        #expect(description.contains("Skip"))
    }

    @Test
    func idleModifierRendersNoPanel() {
        let modifier = SwipeToActModifier(threshold: 72, onOutcome: { _ in })
        let description = String(describing: modifier.body(content: Text("card")))
        #expect(!description.contains("Complete"))
        #expect(!description.contains("Skip"))
    }

    @Test
    func modifierWrapsItsContent() {
        let modifier = SwipeToActModifier(threshold: 72, onOutcome: { _ in })
        let description = String(describing: modifier.body(content: Text("card")))
        #expect(description.contains("card"))
    }
}
```

`Text(SharedStrings…)` / `LocalizedStringResource` reflection prints the
resource key, so `contains("Complete")` / `contains("Skip")` is stable (same
mechanism as `SwipePromptTests`). If, when compiling, `SwipeToActModifier`'s
internal `init` is unreachable from the test target, keep the `init` internal
(not `private`) — `@testable` exposes it.

### Verification

#### Automated
- [x] `make format` then `make lint` clean
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green
- [x] `scripts/test-one.sh SingleThreadTests/SwipePromptTests` green (prompt
      markup untouched)
- [x] `make build` succeeds

#### Manual
- [ ] Partial right drag on the sim: tinted Complete panel is revealed behind
      the card and brightens as it approaches 72pt; release under threshold
      snaps back with no action and no leftover panel
- [ ] Partial left drag shows the Skip panel; release past 72pt fires Skip and
      the card animates back to centre
- [ ] No stuck-offset card after either release

---

## Phase 3: Hardening & proof — accessibility parity, audits, the one UI gesture test

VoiceOver exposes Complete and Skip as named actions on the card; the
accessibility audit (hit region / dynamic type) passes; one coordinate-drag UI
test proves a **half-distance** drag triggers the action end to end.

### Changes

#### 1. Accessibility parity + drag target identifier
**File**: `SingleThread/SwipeToActModifier.swift`
**Action**: modify

Chain these onto `content` inside `SwipeToActModifier.body`, after
`.simultaneousGesture(...)`:

```swift
                .accessibilityAction(named: Text(SharedStrings.completeAction)) {
                    onOutcome(.complete)
                }
                .accessibilityAction(named: Text(SharedStrings.skipAction)) {
                    onOutcome(.skip)
                }
                .accessibilityIdentifier("reminderCard")
```

Labels come from `SharedStrings.completeAction` / `skipAction` — the same keys
`bottomBar`'s `actionCluster` uses (`ContentView.swift:536,545-553`), so
VoiceOver parity is preserved after `.swipeActions` is gone.
`Text(_: LocalizedStringResource)` is the compile-verified init; if the
`accessibilityAction(named:)` overload resolution object, compile the file and
pick the `Text` overload that matches (the SDK skill: verify by compiling, don't
mine `.swiftinterface`).

#### 2. Half-distance swipe UI test
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify

One UI test, added beside `testLaunchAndRenderSmoke`. It is justified because
the regression is a *distance-to-trigger* feel bug that only manifests at the
gesture layer; direction/threshold math is already unit-tested in Phase 1. It
reuses the proven `--ui-testing` seam exactly as `testLaunchAndRenderSmoke`
does (plain `--ui-testing` seeds one reminder, "Buy groceries" /
"Don't forget the milk" — `SingleThreadUITests.swift:29-39`), so no `--seed`
JSON is needed. The element query goes through `descendants(matching: .any)` so
it is agnostic to whether SwiftUI surfaces the identifier on the `List` cell or
an `other` element.

```swift
    /// Proves a ~half-threshold horizontal drag on the card fires Complete end
    /// to end: the seeded reminder disappears after a ~90pt rightward drag
    /// (threshold 72pt). Direction/threshold logic is unit-tested; this test
    /// exists only because the trigger distance is a gesture-layer behaviour.
    func testHalfDistanceSwipeCompletesReminder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
                      "Seeded reminder should render")

        let card = app.descendants(matching: .any)["reminderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "Reminder card drag target should render")

        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 90, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Buy groceries"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed,
                       "A ~90pt right drag should complete the reminder")
    }
```

#### 3. Localisation check
**Action**: verify only — no file change expected

The panel and the accessibility actions reuse existing `Localizable.xcstrings`
keys "Complete" (`:3451`-area) and "Skip"; confirm
`SingleThreadCore/LocalizedString+Shared.swift:15-32` is the only source and that
no new key is introduced. If any new key were introduced it would have to be
added to the localisation test fixtures (`LocalizationTestHelpers.swift`) — the
intent is that none is.

### Verification

#### Automated
- [x] `make format` then `make lint` clean
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testHalfDistanceSwipeCompletesReminder`
      green (destination pinned by `.simulator_id`)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke`
      green (includes `performAccessibilityAudit`)
- [x] `make ui-test` green (full iOS UI suite + accessibility audit; the audit
      is where the `.hitRegion`/`.dynamicType` parity is enforced)
- [x] `make test` green (macOS-native `SingleThreadTests`, includes Phases 1-2
      suites; ignore the three pre-existing local `EntitlementStoreTests`
      failures per `conventions.md`)
- [ ] Full gate via the `run-gate` skill (`./scripts/test.sh`) once after all
      three phases commit — never `nohup`’d ad hoc
- [x] `make periphery` clean (clean `DerivedData/` first after branch switches)

#### Manual
- [ ] On the sim: VoiceOver (or Accessibility Inspector) exposes "Complete" and
      "Skip" as actions on the card
- [ ] Scroll the list and pull-to-refresh still work; the prompt + Dismiss and
      nudge banner are unchanged
- [ ] On-device (or sim) feel check: a ~72pt drag is noticeably easier than the
      old full-swipe; if the feel is wrong, `SwipeGesture.releaseDistance` is the
      single constant to tune (unit + UI test thresholds derive from it)

---

## Testing Checkpoints

- **After Phase 1**: `SwipeGestureDecisionTests` + `testLaunchAndRenderSmoke`
  green → proceed.
- **After Phase 2**: `SwipeToActModifierTests` + `SwipePromptTests` green,
  `make build` → proceed.
- **After Phase 3**: new UI test + a11y audit green, scroll/refresh manual check
  done → full gate via `run-gate`.
- Do not advance past a red slice. No slice depends on another's internals: all
  cross-slice integration goes through `SwipeGesture.outcome` and
  `.swipeToAct`.

## Deviations from `structure.md`

- **Phase 1 gesture placement**: attached to the `ReminderCardView` initializer
  (before `.listRowBackground`) rather than the row after the full-height frame.
  Same public effect, but keeps the offset/panel card-sized instead of
  full-row-height and keeps the Phase 2 extraction to a single modifier.
- **Phase 3 UI test seam**: uses plain `--ui-testing` (which already seeds one
  reminder) rather than `--ui-testing` + `--seed`; the seed JSON would be
  redundant and the plain seam is what `testLaunchAndRenderSmoke` already
  proves.
- **`SwipeToActModifierTests` constructor**: tests call
  `SwipeToActModifier(threshold:onOutcome:).body(content:)` via
  `@testable import` (internal `init`) rather than reflecting a host view;
  equivalent reflection, less fixture plumbing.
- **Known-risk resolved**: `bottomBar` (verified `ContentView.swift:701-757`)
  owns `completeButton`/`skipButton`, so removing `.swipeActions` cannot break
  the smoke test.