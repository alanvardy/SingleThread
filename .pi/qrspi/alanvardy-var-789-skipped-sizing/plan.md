# Implementation Plan

## Overview

Fix iPad card stretch and oversized sheets by reusing the codebase's one existing iPad-adaptation pattern — the viewport-relative width cap `min(340, viewportWidth * 0.6)` (`EmptyStateCard.swift:42-44`) — instead of introducing size-class/idiom branching. Add the cap to the reminder card, remove its accidental full-width stretch sources, and content-size the nudge + reschedule sheets via `.presentationSizing(.fitted)`. No persistence, store, or sync logic changes.

This is a **view-layer** task: a pure pinnable helper → card view layer → sheet view layer → full gate. No schema migration, no new test target, no new `.sheet`.

---

## Phase 1: Pure width-cap helper (`CardWidth`)

Extract the iPad-proportionate sizing formula into a shared, pinnable free function so a Swift Testing unit test can pin `min(ceiling, fraction)` without rendering.

### Changes

#### 1. New helper type
**File**: `SingleThread/CardWidth.swift`
**Action**: create

```swift
import CoreGraphics

/// Pure, viewport-relative cap for content cards, shared by the empty states
/// and the reminder card. Returns `min(ceiling, fraction)` so cards hug short
/// content but never balloon on wide (iPad) screens. Kept free of SwiftUI so
/// unit tests can pin the math without rendering.
enum CardWidth {
    static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
    }
}
```

#### 2. Delegate `EmptyStateCard` to the new helper
**File**: `SingleThread/EmptyStateCard.swift`
**Action**: modify — replace the body of `maxContentWidth(viewportWidth:)` (the formula at `:42-44`) with a delegate call. Behavior-preserving; existing empty-state UI tests are the regression guard.

```swift
    static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        CardWidth.maxContentWidth(viewportWidth: viewportWidth)
    }
```

#### 3. Unit tests for the helper
**File**: `SingleThreadTests/CardWidthTests.swift`
**Action**: create

```swift
@testable import SingleThread
import CoreGraphics
import Testing

struct CardWidthTests {
    @Test
    func maxContentWidthScalesBelowCeiling() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 200) == 120)
    }

    @Test
    func maxContentWidthPinsAtCeiling() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 1000) == 340)
    }

    @Test
    func maxContentWidthHitsCeilingAtBoundary() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 340 / 0.6) == 340)
    }

    @Test
    func maxContentWidthIsNonNegativeAtZeroViewport() {
        #expect(CardWidth.maxContentWidth(viewportWidth: 0) == 0)
    }
}
```

Note: `CardWidth` is `internal`, so access is via `@testable import SingleThread` (same as `CardPlateTests`). Tests are not `@MainActor` — the helper is a pure `CGFloat` function. Test names do not start with `test`.

### Verification

#### Automated
- [x] `make format` passes (no renames — the new unit-test names don't start with `test`/`testing`)
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`)
- [x] `make test` green — `CardWidthTests` passes on iOS (`-only-testing:SingleThreadTests`)
- [x] `make periphery` clean (helper is consumed by `EmptyStateCard` immediately — no dead extraction)

#### Manual
- [ ] `EmptyStateCard` still renders identical empty/all-done cards (behavior-preserving refactor)

---

## Phase 2: Card de-stretch + width cap (reminder card view layer)

Make `ReminderCardView` hug its content in every state (plain, nudge, swipe prompt, long title) by removing the swipe prompt's full-width frame, content-hugging the nudge banner, and layering the `CardWidth` cap inside the card. Centering stays on the caller row.

### Changes

#### 1. `ReminderCardView.swift` — add `maxWidth` property + apply the cap
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Add a stored property and init parameter (defaulted so the existing `String(describing:)` test helpers and any previews keep compiling):

```swift
    init(
        display: ReminderDisplay,
        showDate: Bool,
        showList: Bool = false,
        showRecurrence: Bool = true,
        showAlarms: Bool = true,
        showSwipePrompt: Binding<Bool> = .constant(false),
        showNudge: Bool = false,
        onNudgeTap: @escaping () -> Void = {},
        maxWidth: CGFloat = 340) {
        // ...existing assignments...
        self.maxWidth = maxWidth
    }
```

Add the stored property next to the other `let`s:

```swift
    /// Caps the card's width so long titles wrap and the nudge banner/styled
    /// buttons stop expanding under the row's `.center` proposal on iPad.
    private let maxWidth: CGFloat
```

Apply the cap in `body`, **inside** the card and before `.cardPlate` (mirrors `EmptyStateCard.swift:31`, but leading-aligned since the card's copy is leading-aligned, unlike the centered empty-state copy):

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if showNudge {
                nudgeBanner
            }
            if showSwipePrompt {
                prompt
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)
    }
```

#### 2. `ReminderCardView.swift` — content-hug the nudge banner
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — add `.fixedSize(horizontal: true, vertical: false)` to `nudgeBanner` right after `.tint(.white)` (before `.padding(.vertical, 8)`). This stops the `borderedProminent` button from expanding under the row's `.center` full-width proposal.

```swift
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 8)
```

#### 3. `ReminderCardView.swift` — remove the swipe prompt's full-width frame
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify — delete `.frame(maxWidth: .infinity)` from the `prompt` VStack (`:206-207`), so the prompt hugs too. The trailing `.cardPlate(fill: .promptBoxFill)` stays.

```swift
        }
        .cardPlate(fill: CardPlate.promptBoxFill)
    }
```

#### 4. `ContentView.swift` — pass the viewport cap
**File**: `SingleThread/ContentView.swift`
**Action**: modify — in the `ReminderCardView(...)` call inside `reminderList` (`:415-427`), add the cap computed from the `GeometryReader`:

```swift
                            ReminderCardView(
                                display: ReminderDisplay(reminder: reminder),
                                showDate: showDate,
                                showList: showList,
                                showRecurrence: showRecurrence,
                                showAlarms: showAlarms,
                                showSwipePrompt: swipePromptBinding,
                                showNudge: viewModel.isNudged(reminder.calendarItemIdentifier),
                                onNudgeTap: openNudgeSheet,
                                maxWidth: CardWidth.maxContentWidth(viewportWidth: geometry.size.width))
```

#### 5. New iPad UI test
**File**: `SingleThreadUITests/SkipNudgeUITests.swift`
**Action**: modify — add one method (reuses the existing class and `--seed` seam; runs in the iPad matrix job automatically since CI runs `SingleThreadUITests` on both `iPhone 17` and `iPad (A16)`):

```swift
    // MARK: - iPad layout

    /// On iPad the nudged card must hug its content instead of stretching the
    /// borderedProminent banner edge-to-edge across the padded row. Red on
    /// `origin/main` (banner fills ~rowWidth − 80); green once the card is
    /// width-capped.
    @MainActor
    func testNudgedCardDoesNotSpanRowOnIPad() {
        let app = launchSeeded(Self.seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3))

        let rowWidth = app.windows.firstMatch.frame.width
        // Strictly less-than is deliberate: before the fix the banner equals
        // the padded row width on iPad, so `<=` would falsely pass.
        XCTAssertLessThan(
            banner.frame.width,
            rowWidth - 80,
            "Nudged card should hug its content, not span the full row width")
    }
```

> **Deviation from structure**: the structure sketch said `width ≤ row width − 80`. A `<=`/`≥` assertion would be green on `origin/main` (the pre-fix banner *equals* `rowWidth − 80` on iPad), so the test could never reproduce the report red-first. The plan uses strict `<` instead — the correct operator to make the test fail before the fix and pass after. If `app.windows.firstMatch` proves empty in a later SwiftUI, fall back to `app.frame.width` (same value for a single full-screen window).

> **Red-first requirement** (design's open risk on the exact iPad trigger): before writing the fix in steps 1–4, run only this one test against a clean `origin/main` checkout on iPad and confirm it **fails**. Then apply steps 1–4 and confirm it passes.

### Verification

#### Automated
- [ ] Red-first: on `origin/main`, `SIM='platform=iOS Simulator,name=iPad (A16)'` — `testNudgedCardDoesNotSpanRowOnIPad` **fails**
- [ ] After fix: `SIM='platform=iOS Simulator,name=iPad (A16),OS=<ver>'` — `testNudgedCardDoesNotSpanRowOnIPad` **passes** (pin `,OS=`/`,id=` — bare `name=` hangs, per conventions)
- [ ] `make build` passes
- [ ] `SIM='platform=iOS Simulator,name=iPhone 17'` — existing `SkipNudgeUITests`, `ActionMenuUITests`, and `SingleThreadUITestsFlows` swipe-prompt flows stay green (the new test also passes on iPhone — the banner already hugged there)
- [ ] `make test` green — the existing `String(describing:)` card snapshots (`ShowDateTests`, `ShowAlarmsTests`, `ShowRecurrenceTests`, `SwipePromptTests`) stay green: they assert substrings (`"Groceries"`, `"FormatStyleStorage"`, `"CardPlateModifier"`, `"style: orange"`, `"BorderedProminentButtonStyle"`), none of which a `.frame`/`.fixedSize` wrapper or the removed prompt frame removes
- [ ] `make periphery` clean (no orphaned code after the `prompt` frame deletion)

#### Manual
- [ ] On iPad sim: card hugs content in all four states (plain / nudge banner / swipe prompt / long title) — never edge-to-edge; on iPhone the card looks unchanged except long titles wrap at the cap (~340 wouldn't matter on narrow iPhone — effectively no visual change)

---

## Phase 3: Content-sized sheets (sheet view layer)

Size the nudge sheet and the standalone reschedule sheet to their content so they no longer render with large blank bands above/below on iPad.

### Changes

#### 1. `.presentationSizing(.fitted)` on both short sheets
**File**: `SingleThread/ContentView.swift`
**Action**: modify — the `.sheet` attachments at `:302-303` (reschedule) and `:306-307` (nudge) each gain `.presentationSizing(.fitted)`. No type/signature change anywhere else.

```swift
        .sheet(isPresented: $isShowingRescheduleSheet) {
            actionMenuRescheduleSheet
                .presentationSizing(.fitted)
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() }) {
            nudgeSheetContent
                .presentationSizing(.fitted)
        }
        #endif
```

`.presentationSizing(.fitted)` is iOS 17+; deployment target is iOS 18.7 — no availability gating needed.

#### 2. Documented fallback (do not start here)
**Fallback only** if `fitted` misbehaves with the `ToolbarItem` cancel or the embedded `DatePicker` (design Decision 3, Stage 3 open risk): swap to `.presentationDetents([.height(...)])` with a per-sheet value (e.g. `.height(320)` for the reschedule sheet, `.height(420)` for the nudge sheet), sized for the content including large Dynamic Type. Never a hardcoded device-conditional `frame`; size from content.

### Verification

#### Automated
- [ ] `make build` passes
- [ ] `make ui-test` on the pinned iPad destination — existing `SkipNudgeUITests` reschedule path and `ActionMenuUITests` reschedule path stay green through the newly fitted presentation
- [ ] `make ui-test` on `iPhone 17` — full `SingleThreadUITests` still green (fitted should not change iPhone page-sheet behavior)

#### Manual
- [ ] On iPad sim: tap the nudge banner — sheet is content-sized (no blank bands); open the action-menu Reschedule sheet — also content-sized; Cancel and the `DatePicker` both render and dismiss correctly
- [ ] Optional (skip if it trips the local-only hit-region flakiness noted in `AGENTS.md`): assert the sheet content `VStack` frame is narrower than the screen on iPad

---

## Phase 4: Full gate + cross-target regression (final checkpoint)

Prove the iOS-scoped changes don't shift shared card/centering behavior for the watch and widget targets, and that format/lint/periphery stay clean. **Run once**, after Phases 1–3 commit — workers must not re-run the full gate.

### Changes

None (verification only). No watch/widget source touched — `ReminderCardView` is iOS-app-only; the watch/widget views (`WatchReminderView.swift:368`, `NextThingWidget.swift:161`) merely mirror the same centering *pattern* and are unaffected.

### Verification

#### Automated
- [ ] `./scripts/test.sh` fully green (CI-identical: swiftformat → swiftlint `--fix` → swiftformat `--lint` → swiftlint `--strict` → iOS build → watch build → periphery → iOS unit `SingleThreadTests` → iOS UI `SingleThreadUITests` → watch unit+UI → macOS unit)
- [ ] `SingleThreadWatchTests` / `SingleThreadWatchUITests` green unchanged
- [ ] `make periphery` clean

#### Manual
- [ ] Confirm watch and Today-widget still render their cards centered and hugged (sanity spot-check, no regression expected)

---

## Out of Scope (do not touch in any phase)

- Skip-count persistence, `SkipCountStore`, threshold logic, the 6th-skip interrupt, and the watch-sync gap on that intercept.
- The two-hardcoded-6s bug (`SkipCountStore.defaultThreshold = 6` vs static `"Skipped 6 times"` in `LocalizedString+Shared.swift:25-28`). Flagged for a separate ticket.
- Settings and purchase sheets (`ContentView.swift:294-299`) — intentionally full-height.
- Any size-class/idiom branching (`horizontalSizeClass` / `.pad`) — zero matches today; viewport-relative math replaces it.
- No new test target, no new `.sheet` — modifiers on existing views only.

## Open Risks (verify at the named phase)

- **Fitted + NavigationStack/DatePicker** (Phase 3): least-proven; detent fallback is the documented escape hatch.
- **Cap value tuning** (Phase 1 → proven Phase 2): `min(340, 0.6)` is sized for empty states; the reminder card may warrant a different ceiling/fraction. Confirm with the iPad assertion, adjust the single constant in `CardWidth` if needed.
- **Long-title wrap regression** (Phase 2): the cap makes titles wrap earlier on iPad. Cap wins per design; revisit only if visually objectionable.