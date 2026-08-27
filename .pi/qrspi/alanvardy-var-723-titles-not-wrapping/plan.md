# Implementation Plan

## Overview

Long reminder titles wrap naturally on iPhone **and** iPad — fully readable, never clipped or
truncated — while the existing priority marker, code-span background highlight, and card plate
stay intact. Verified by a UI test that seeds a long title and asserts the rendered title is not
clipped.

## Assumptions & Deviations from structure.md

- **Stale test names**: `structure.md` cites `testSeededReminderTitle` / `testSeededReminderNotes`
  in `UITestingSeedTests.swift`; those methods no longer exist (the file now has
  `parsesRemindersFromCompactJSON` and `inMemoryStoreRendersSeededRemindersThroughStore`). The plan
  adds a new `parsesLongTitlesWithoutTruncation` test instead.
- **Label-only assertion gap**: accessibility labels carry the full string even when text is
  visually clipped, so the structure's label-aggregation assertion alone cannot distinguish a
  wrapped title from a single-line clipped one. Stage 2 adds a supplementary element-height
  assertion to actually reproduce clipping.
- **TCC monitor is defensive**: the `--seed` path backs the app with `InMemoryEventStore`, which
  reports `.fullAccess` and never calls `requestFullAccessToReminders()`, so no TCC dialog is
  expected. The interruption monitor in Stage 1 is harmless defensive code.
- **Stage 3 is a decision tree** (per design decision #3, "fix technique is TBD pending the
  reproduction"): the exact lever is selected by the Stage 2 reproduction, applied in least→most
  invasive order, and gated on the full suite staying green.
- **Non-reproducibility escape hatch**: if the Stage 2 test passes on iPad too, the ticket closes
  as already-fixed / not-reproducible (design "Open Risks"), and Stages 3–4 are skipped.

---

## Phase 1: Long-Title Seed Fixture + iPad Test Harness

Prove the `--seed` seam accepts arbitrarily long titles and that the UI-test harness launches a
seeded app on iPad without a blocking TCC dialog.

### Changes

#### 1. Unit test for long-title seed parsing
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify (add one `@Test` method)

```swift
@Test
func parsesLongTitlesWithoutTruncation() {
    // 500-character plain title and a >500-character title containing code
    // spans: the Codable seed path must accept arbitrarily long titles
    // (no length truncation at the parser surface).
    let longPlain = String(repeating: "a", count: 500)
    let longCodeSpan = String(repeating: "word `code` ", count: 45)
    let seed = UITestingSeed.fromLaunchArguments([
        "--seed",
        #"{"reminders":[{"title":"\#(longPlain)"},{"title":"\#(longCodeSpan)"}]}"#
    ])

    #expect(seed?.reminders.count == 2)
    #expect(seed?.reminders[0].title == longPlain)
    #expect(seed?.reminders[1].title == longCodeSpan)
}
```

Note: the seed parser stores the title literally — backticks are not interpreted here (that is
`CodeSpanFormatter`'s job at render time).

#### 2. iPad seed-launch UI test with TCC interruption monitor
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (add one `@MainActor` test method)

```swift
@MainActor
func testSeedLaunchesOnIPad() {
    let app = XCUIApplication()
    app.launchArguments = ["--seed", #"{"reminders":[{"title":"Buy groceries"}]}"#]

    // Defensive TCC/interruption handler. The seed path backs the app with
    // InMemoryEventStore (.fullAccess, no EventKit access request), so no
    // dialog is expected — but if a system alert appears on iPad, dismiss its
    // primary action before asserting.
    addUIInterruptionMonitor(withDescription: "TCC dialog") { alert -> Bool in
        if alert.buttons.count > 1 {
            alert.buttons.element(boundBy: 1).tap()
        } else {
            alert.buttons.firstMatch.tap()
        }
        return true
    }

    app.launch()
    app.tap() // triggers any pending interruption monitor

    XCTAssertTrue(
        app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
        "Seeded reminder title should display on iPad without a blocking dialog")
}
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:SingleThreadTests/UITestingSeedTests` exits 0
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testSeedLaunchesOnIPad` exits 0

#### Manual
- [ ] On the iPad (A16) simulator, confirm the seeded "Buy groceries" card renders with no TCC/system dialog left on screen (screenshot or `simctl io` check).

**Checkpoint**: both commands exit 0 — seed data + iPad harness proven stable.

---

## Phase 2: Reproduction Test — Failing on iPad, Passing on iPhone

A single UI test seeding a ~250-char title that asserts the full text is visible and not clipped.
Expected **FAIL on iPad** (proving the bug) and **PASS on iPhone**.

### Changes

#### 1. Shared seed constants
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (add two `static let` constants at the top of the class body, before
`setUpWithError`; internal so `SingleThreadUITests` can reference them in Phase 4)

```swift
final class SingleThreadUITestsFlows: XCTestCase {
    // Shared long-title seeds (also referenced by the accessibility-audit test).
    static let longTitleSeed = #"{"reminders":[{"title":"Remember to buy groceries milk eggs bread butter cheese yogurt cereal coffee tea sugar flour pasta rice apples oranges bananas tomatoes onions potatoes carrots celery lettuce spinach broccoli cauliflower peppers cucumbers squash zucchini garlic ginger olive oil vinegar salt pepper"}]}"#

    static let longCodeSpanSeed = #"{"reminders":[{"title":"Use `map` and `filter` to process the collection of items before rendering them in the list view with `compactMap` and `reduce` to produce the final result set for the grocery run this week"}]}"#
    ...
}
```

#### 2. Reproduction test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (add one `@MainActor` test method)

```swift
// MARK: - Long title wrapping

@MainActor
func testLongTitleWrapsWithoutClipping() {
    let app = launchApp(seedJSON: Self.longTitleSeed)

    XCTAssertTrue(
        app.staticTexts.firstMatch.waitForExistence(timeout: 5),
        "Seeded card should render before wrapping assertions")

    let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
    let visible = labels.joined(separator: " ")

    // The full title must be present in the aggregated visible text.
    XCTAssertTrue(
        visible.contains("Remember to buy groceries milk eggs bread butter cheese"),
        "Full title should be visible, got: \(labels)")

    // No truncation ellipsis anywhere in the rendered text.
    XCTAssertFalse(
        labels.contains(where: { $0.hasSuffix("…") || $0.hasSuffix("...") }),
        "Title should not be truncated, got: \(labels)")

    // Supplementary clipping check: accessibility labels carry the full string
    // even when text is visually clipped, so label presence alone can't tell a
    // wrapped title from a single-line clipped one. A title this long must span
    // several wrapped lines — assert the title element grew taller than a
    // single `.title` line (~40pt).
    guard let titleElement = app.staticTexts
        .allElementsBoundByIndex
        .first(where: { $0.label.contains("Remember to buy groceries") })
    else {
        return XCTFail("Title element should be present")
    }
    XCTAssertGreaterThan(
        titleElement.frame.height, 60,
        "Title should wrap to multiple lines; got height \(titleElement.frame.height)")
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testLongTitleWrapsWithoutClipping` **PASSES**
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testLongTitleWrapsWithoutClipping` **FAILS** (proving the bug)

#### Manual
- [ ] On iPad, confirm the failure is clipping/truncation of the title (not an unrelated assertion). Screenshot the failure for the PR.

**Checkpoint**: test passes on iPhone, fails on iPad. **If it passes on iPad too**, the bug is
not reproducible — stop here and close the ticket as already-fixed / not-reproducible; do not
ship a speculative fix. Otherwise this test becomes the acceptance gate for Phase 3.

---

## Phase 3: Layout Fix

The minimal SwiftUI change so the long title wraps on iPad instead of clipping/truncating. Apply
the levers **in order**, stopping at the first that makes the Phase 2 test pass on iPad while
keeping the full suite green (iPhone + iPad). Revert a lever and move to the next if it regresses
anything.

### Changes

#### 1. Lever A — `*` `.fixedSize(horizontal: false, vertical: true)` on the title
**File**: `SingleThread/ReminderCardView.swift:37-38`
**Action**: modify

```swift
Text(display.titleAttributed)
    .font(.title)
    .fixedSize(horizontal: false, vertical: true)
```

Rationale: allows horizontal compression (→ wrapping) while letting the title expand vertically
to show all lines. Least invasive; try first.

#### 2. Lever B — `.layoutPriority(1)` on the title
**File**: `SingleThread/ReminderCardView.swift:37-38`
**Action**: modify (if Lever A is insufficient)

```swift
Text(display.titleAttributed)
    .font(.title)
    .layoutPriority(1)
```

Rationale: lets the title claim width before the marker HStack squeezes it.

#### 3. Lever C — iPad-gated reduction of the 40pt horizontal row inset
**File**: `SingleThread/ContentView.swift:309` (and add a computed property)
**Action**: modify (if Levers A–B are insufficient)

```swift
// In the row modifier chain (ContentView.swift:309), replace:
.padding(.horizontal, 40)
// with:
.padding(.horizontal, horizontalCardPadding)

// New private computed property (near the other private vars):
private var horizontalCardPadding: CGFloat {
    #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 40
    #else
        40
    #endif
}
```

Note: `UIDevice` requires `import UIKit` (iOS-gated; the `#if os(iOS)` keeps the macOS build
compiling). On iPad the 80pt total inset may over-squeeze the title.

#### 4. Lever D — explicit `.frame(maxWidth: .infinity, alignment: .leading)` on the title
**File**: `SingleThread/ReminderCardView.swift:37-38`
**Action**: modify (only if A–C all fail)

```swift
Text(display.titleAttributed)
    .font(.title)
    .frame(maxWidth: .infinity, alignment: .leading)
```

Rationale: force the title to use the full proposed row width so it wraps inside it.

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testLongTitleWrapsWithoutClipping` **PASSES**
- [ ] `env SIM='platform=iOS Simulator,name=iPad (A16)' ./scripts/test.sh` exits 0
- [ ] `env SIM='platform=iOS Simulator,name=iPhone 17' ./scripts/test.sh` exits 0

#### Manual
- [ ] On iPad, visually confirm the long title wraps across multiple lines, no ellipsis, marker + plate intact.

**Checkpoint**: iPad test exits 0 and both full-suite matrix entries stay green — no regressions.

---

## Phase 4: Regression Guard — Full Suite

Harden the fix with code-span and large-dynamic-type variants plus an accessibility audit running
over a *rendered card* (not the empty `--ui-testing` branch). Phase 2 is non-negotiable; this
phase may be trimmed only if the Phase 3 fix was trivial.

### Changes

#### 1. Code-span long-title wrap test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (add one `@MainActor` test method; reuses `longCodeSpanSeed`)

```swift
@MainActor
func testLongTitleWithCodeSpansWraps() {
    let app = launchApp(seedJSON: Self.longCodeSpanSeed)

    XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))

    let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
    let visible = labels.joined(separator: " ")

    // Code-span content renders without backtick fences and without truncation.
    XCTAssertTrue(visible.contains("map"), "Code-span content should be visible, got: \(labels)")
    XCTAssertTrue(visible.contains("filter"), "Code-span content should be visible, got: \(labels)")
    XCTAssertFalse(visible.contains("`"), "Backtick fences should be stripped, got: \(labels)")
    XCTAssertFalse(
        labels.contains(where: { $0.hasSuffix("…") || $0.hasSuffix("...") }),
        "Long code-span title should not be truncated, got: \(labels)")
}
```

#### 2. Large dynamic-type wrap test (iPad-gated)
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify (add one `@MainActor throws` test method). Add `import UIKit` to the file top
for the `UIDevice` check.

```swift
@MainActor
func testLongTitleWrapsAtLargeDynamicType() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else {
        throw XCTSkip("Large dynamic-type wrapping is iPad-focused")
    }

    let app = XCUIApplication()
    app.launchArguments = [
        "--seed", Self.longTitleSeed,
        // Best-effort UIKit dynamic-type override; may be ignored on some OS
        // versions — the label + height assertions still guard wrapping.
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"
    ]
    app.launch()

    XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))

    let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
    let visible = labels.joined(separator: " ")
    XCTAssertTrue(
        visible.contains("Remember to buy groceries milk eggs"),
        "Full title should be visible at large dynamic type, got: \(labels)")
    XCTAssertFalse(
        labels.contains(where: { $0.hasSuffix("…") || $0.hasSuffix("...") }),
        "Title should not be truncated at large dynamic type, got: \(labels)")
}
```

#### 3. Accessibility audit over the rendered card
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify (rename `testAccessibilityAudit` → `testAccessibilityAuditOverRenderedCard`,
change the launch to seed a card, add `.textClipped` to the audit categories)

```swift
@MainActor
func testAccessibilityAuditOverRenderedCard() throws {
    let app = XCUIApplication()
    // Seed a real card (long code-span title) so the audit runs over rendered
    // reminder content instead of the empty `--ui-testing` branch.
    app.launchArguments = ["--seed", SingleThreadUITestsFlows.longCodeSpanSeed]
    app.launch()

    XCTAssertTrue(
        app.staticTexts.firstMatch.waitForExistence(timeout: 5),
        "Seeded card should display text content before auditing")

    #if os(iOS)
        // On CI the full traversal (especially .dynamicType/.hitRegion) can hang
        // on virtualized runners, so keep those local-only. `.textClipped` is
        // cheap (it measures text frames) and is the category that catches a
        // non-wrapping title, so it runs in both paths.
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            try app.performAccessibilityAudit(
                for: [.sufficientElementDescription, .trait, .textClipped]
            )
        } else {
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait, .textClipped]
            )
        }
    #else
        try app.performAccessibilityAudit()
    #endif
}
```

### Verification

#### Automated
- [ ] `env SIM='platform=iOS Simulator,name=iPhone 17' ./scripts/test.sh` exits 0
- [ ] `env SIM='platform=iOS Simulator,name=iPad (A16)' ./scripts/test.sh` exits 0

#### Manual
- [ ] On iPad, run the three new/changed tests and confirm the card wraps with code spans and at accessibility text sizes.

**Checkpoint**: both matrix entries exit 0 — the wrap fix is proven on both device families with
code-span and large-dynamic-type regressions guarded.

---

## Final Gate

- [ ] `make format` then `make lint` (or `./scripts/test.sh`) pass — SwiftFormat + SwiftLint `--strict` clean
- [ ] `periphery scan --strict` clean (no dead code from the added constants/tests)
- [ ] No pbxproj or Makefile changes needed — new tests live in existing targets only
- [ ] Confirm the bug fix ships with a reproducing unit/UI test before the fix was applied (Phase 2 run order in the PR)
