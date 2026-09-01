# Implementation Plan

## Overview

Add a `.regularMaterial` plate behind the two iOS `ContentUnavailableView` empty
branches ("All Done" and "Nothing due" / "No Reminders") so text is readable
over any background photo in light or dark mode. Close the test gap: add a UI
test for the untested `hasHidden == true` "Nothing due" path via the `--seed`
seam.

**Deviation from structure.md**: The structure's proposed Stage 3 seed
(`skippedIdentifiers` → "Nothing due") is incorrect — one reminder + skip hits
the `allSkipped` "All Done" branch instead. The correct trigger is `reminders`
empty + `hasHidden: true`, which requires extending the `--seed` JSON schema
with a `hasHidden` field. The `skippedIdentifiers` seed field from the
structure outline is replaced by `hasHidden`.

---

## Phase 1: Design Token — Empty-State Corner Radius

Define a shared corner-radius constant in `ReminderCardView` and assert it in
unit tests. The constant is the bottom-most testable seam for the new plate.

### Changes

#### 1. Add `emptyStateCornerRadius` constant
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

After the `promptBoxFill` declaration (line 35), add:

```swift
/// Shared corner radius for content plates: the card text plate and the
/// empty-state material plate. Extracted because the rendered shape can't be
/// asserted headlessly — tests assert this decision instead.
static let emptyStateCornerRadius: CGFloat = 10
```

Also replace the inline `10` on line 49 so the card plate uses the shared
constant:

```swift
// Before (line 49):
RoundedRectangle(cornerRadius: 10)

// After:
RoundedRectangle(cornerRadius: Self.emptyStateCornerRadius)
```

(Only the corner-radius argument changes; the fill, padding pair, and `.padding(-12)` are untouched.)

#### 2. Add unit test asserting the constant
**File**: `SingleThreadTests/BackgroundCardTests.swift`
**Action**: modify

Add a new test method inside `struct BackgroundCardTests` after
`plateFillBlackInDarkMode()` (~line 78):

```swift
/// The empty-state plate's corner radius must match the card plate (10pt)
/// so they share visual rhythm. The rendered shape can't be asserted
/// headlessly — tests assert this decision instead.
@Test
func emptyStateCornerRadiusMatchesCardPlate() {
    #expect(ReminderCardView.emptyStateCornerRadius == 10)
}
```

### Verification

#### Automated
- [x] `make test` passes (all `BackgroundCardTests` green)
- [x] `make build` succeeds (compiler verifies `Self.emptyStateCornerRadius` usage)

#### Manual
- [ ] None — the constant changes no rendered output; the card plate uses the same numeric value.

---

## Phase 2: View — Material Plate on Empty States

Apply `.background(.regularMaterial, in: RoundedRectangle(cornerRadius:))` to
both `ContentUnavailableView` empty branches in `ContentView`.

### Changes

#### 1. "All Done" branch plate
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `reminderList` computed property, inside the `if viewModel.store.allSkipped`
branch (around lines 354–358), add one modifier between the
`ContentUnavailableView` and `.frame`:

```swift
// Before:
ContentUnavailableView(
    allDoneCopy.title,
    systemImage: allDoneCopy.systemImage,
    description: Text(allDoneCopy.description))
    .frame(minHeight: viewHeight, alignment: .center)

// After:
ContentUnavailableView(
    allDoneCopy.title,
    systemImage: allDoneCopy.systemImage,
    description: Text(allDoneCopy.description))
    .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: ReminderCardView.emptyStateCornerRadius))
    .frame(minHeight: viewHeight, alignment: .center)
```

#### 2. Empty branch plate ("Nothing due" / "No Reminders")
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `else if viewModel.store.reminders.isEmpty` branch (around lines
368–372), same modifier addition:

```swift
// Before:
ContentUnavailableView(
    emptyCopy.title,
    systemImage: emptyCopy.systemImage,
    description: Text(emptyCopy.description))
    .frame(minHeight: viewHeight, alignment: .center)

// After:
ContentUnavailableView(
    emptyCopy.title,
    systemImage: emptyCopy.systemImage,
    description: Text(emptyCopy.description))
    .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: ReminderCardView.emptyStateCornerRadius))
    .frame(minHeight: viewHeight, alignment: .center)
```

### Verification

#### Automated
- [x] `make build` succeeds (no new compiler errors)
- [x] `make lint` passes (SwiftFormat + SwiftLint)

#### Manual
- [ ] Launch app with a photo background in light mode — "No Reminders" text is readable over the photo
- [ ] Switch to dark mode — "No Reminders" text is readable
- [ ] Skip all visible reminders — "All Done" text is readable over photo in both schemes
- [ ] The material plate looks lighter than the card plate (visual distinction)

---

## Phase 3: Seed Extension — `hasHidden` Field

The `--seed` JSON currently cannot produce `hasHidden == true` with an empty
`reminders` array — the state needed for the "Nothing due" UI test. Extend the
seed schema with a `hasHidden` field and wire it so the store preserves the
value when seeded in the empty+hidden combination.

### Changes

#### 1. Add `hasHidden` to seed payload and materialized struct
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

**a)** In `SeedPayload` (the private `Codable` struct), add the property:

```swift
var hasHidden: Bool = false
```

**b)** In `SeedPayload.init(from:)`, add decoding (after `isEntitled` line):

```swift
hasHidden = try container.decodeIfPresent(Bool.self, forKey: .hasHidden) ?? false
```

**c)** In `CodingKeys` (private enum, ~line 142), add the key:

```swift
case hasHidden
```

**d)** In `SeedPayload.materialize()`, pass `hasHidden` through:

```swift
return UITestingSeed(
    reminders: createdReminders,
    calendars: createdCalendars,
    excludedListTitles: Set(excludedLists),
    completionCount: completionCount,
    isEntitled: isEntitled,
    hasHidden: hasHidden)
```

**e)** In `UITestingSeed` (the public struct), add the property after `isEntitled`:

```swift
public let hasHidden: Bool
```

#### 2. Wire `hasHidden` in the seeded-store factory
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In `seededStore(_:)` (~line 272), replace the `ReminderStore` init call with
logic that uses `loadsReminders: false` when the seed is empty+hidden (so
`reload()` doesn't overwrite `hasHidden`):

```swift
// Before:
let store = ReminderStore(
    eventStore: inMemoryStore,
    loadsReminders: true,
    completionCounter: CompletionCounterStore(
        defaults: AppGroup.defaults,
        key: "completionCount"),
    entitlementStore: entitlementStore)

// After:
let emptyWithHidden = seed.reminders.isEmpty && seed.hasHidden
let store = ReminderStore(
    eventStore: inMemoryStore,
    loadsReminders: !emptyWithHidden,
    hasHidden: seed.hasHidden,
    completionCounter: CompletionCounterStore(
        defaults: AppGroup.defaults,
        key: "completionCount"),
    entitlementStore: entitlementStore)
```

**Why `loadsReminders: false`**: when the seed has no reminders and `hasHidden`
is true, we want the store to stay exactly as initialized. If `loadsReminders`
were `true`, `start()` → `reload()` would recompute `hasHidden` (via broad
fetch), and the `InMemoryEventStore` returns the same list for both narrow and
broad fetches, so `hasHidden` would be reset to `false`.

### Verification

#### Automated
- [ ] `make build` succeeds (no new compiler errors in `SingleThreadCore` or `SingleThread`)
- [ ] `make test` passes — existing seed tests (`testEmptyListShowsNoRemindersState`, `testSkipAllShowsAllDoneState`) must still pass
- [ ] `make lint` passes

#### Manual
- [ ] None — just a test seam; no production behavior changes.

---

## Phase 4: UI Test — "Nothing Due" Coverage

Add a UI test for the `hasHidden == true` "Nothing due" empty path, which
currently has zero UI test coverage. Seed an empty store with `hasHidden: true`
and assert the "Nothing due" `ContentUnavailableView` renders.

### Changes

#### 1. Add `testNothingDueShowsWhenAllVisibleRemindersSkipped`
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add a new test method in the "List rendering" `// MARK:` section, after
`testEmptyListShowsNoRemindersState()` (~line 51):

```swift
@MainActor
func testNothingDueShowsWhenRemindersHidden() {
    let app = launchApp(seedJSON: #"""
    {"reminders":[],"hasHidden":true}
    """#)

    XCTAssertTrue(
        app.staticTexts["Nothing due"].waitForExistence(timeout: 5),
        "With hasHidden seeded true and no reminders, 'Nothing due' should appear")
}
```

**State flow**: `reminders: []` + `hasHidden: true` + `loadsReminders: false` →
`store.reminders.isEmpty == true` (empty branch, not All Done) →
`store.hasHidden == true` → `ContentViewModel.emptyStateCopy(hasHidden: true)`
returns title `"Nothing due"` → `ContentUnavailableView` renders it.

### Verification

#### Automated
- [ ] `make ui-test` passes — the new test and all existing UI tests green
- [ ] `make lint` passes
- [ ] [ ] Full gate: `./scripts/test.sh` passes (unit + UI + lint + format + periphery)

#### Manual
- [ ] None — the UI test is the verification.

---

## Phase 5: Final Gate

Run the full CI-identical pipeline once.

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes (formats, lints, builds, periphery, unit tests, UI tests)
- [ ] `make periphery` passes
- [ ] `pr_status` shows CI green

#### Manual
- [ ] Screenshot "Nothing due" and "All Done" over a photo background in light + dark mode — match `docs/SimulatorManualVerification.md` slots
- [ ] Visual review: material plate is present and readable; card plate is unchanged

---

## Files Summary

| File | Phase | Action |
|------|-------|--------|
| `SingleThread/ReminderCardView.swift` | 1 | Add `emptyStateCornerRadius`; use it in card plate |
| `SingleThreadTests/BackgroundCardTests.swift` | 1 | Add `emptyStateCornerRadiusMatchesCardPlate` test |
| `SingleThread/ContentView.swift` | 2 | Add `.background(.regularMaterial, …)` to two empty branches |
| `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift` | 3 | Add `hasHidden` field to seed schema |
| `SingleThread/AppViewModel.swift` | 3 | Wire `hasHidden` + `loadsReminders` logic in `seededStore()` |
| `SingleThreadUITests/SingleThreadUITestsFlows.swift` | 4 | Add `testNothingDueShowsWhenRemindersHidden` |

## Not Changed

- Watch, widget, `ControlPlateModifier`, `ReminderCardView.plateFill`, copy
  strings, populated card path, `RowChromeBackground` — none touched.
- No new types, migrations, or codegen steps.