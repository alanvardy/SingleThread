# Structure Outline

## Approach

Add a `.regularMaterial` plate behind the two iOS empty-state
`ContentUnavailableView` views so their text is readable over any background
photo in light or dark mode. The fix is iOS-only (watch has no photo layer;
widget already has `.fill.tertiary`), adds no new types, and extracts only one
decision constant for testability. Plate extraction is deferred to a follow-up
ticket.

---

## Stage 1: Design Token — Empty-State Corner Radius

Define the shared corner-radius constant that both the card plate and the new
empty-state plate consume. This is the bottom-most testable seam — everything
above it uses this value.

**Files**:
- `SingleThread/ReminderCardView.swift` (add constant)
- `SingleThreadTests/BackgroundCardTests.swift` (add test)

**Key changes**:
```swift
// ReminderCardView.swift — alongside plateFill / promptBoxFill (after line 35)

/// Shared corner radius for content plates: the card text plate and the
/// empty-state material plate. Extracted because the rendered shape can't be
/// asserted headlessly — tests assert this decision instead.
static let emptyStateCornerRadius: CGFloat = 10
```

**Existing constant to reference** (already present, not changed):
```swift
// ReminderCardView.swift:49 — card plate uses 10 inline:
RoundedRectangle(cornerRadius: 10)
```

**Tests**:
- `BackgroundCardTests.emptyStateCornerRadiusMatchesCardPlate()` — asserts
  `ReminderCardView.emptyStateCornerRadius == 10`
- Optionally: replace the inline `10` in the card plate (`ReminderCardView.swift:49`)
  with `Self.emptyStateCornerRadius` so the card and empty state share the
  single source of truth. If done, the existing `plateFill*` tests remain green
  as regression guards.

**Verify**: `make test` passes for `SingleThreadTests` (specifically
`BackgroundCardTests`).

---

## Stage 2: View — Material Plate on Empty States

Apply `.background(.regularMaterial, in: RoundedRectangle(cornerRadius:))` to
both `ContentUnavailableView` empty branches. The material adapts to light/dark
automatically, is lighter than the card's off-white/black plate (visually
distinct), and requires no color-constant extraction.

**Files**:
- `SingleThread/ContentView.swift` (two modifier additions)

**Key changes**:

1. **"All Done" branch** (`ContentView.swift` ~line 354–358):
   ```swift
   // Before:
   ContentUnavailableView(
       allDoneCopy.title,
       systemImage: allDoneCopy.systemImage,
       description: Text(allDoneCopy.description))
       .frame(minHeight: viewHeight, alignment: .center)

   // After — add one modifier:
   ContentUnavailableView(…)
       .background(
           .regularMaterial,
           in: RoundedRectangle(cornerRadius: ReminderCardView.emptyStateCornerRadius))
       .frame(minHeight: viewHeight, alignment: .center)
   ```

2. **Empty branch** (`ContentView.swift` ~line 368–372):
   ```swift
   // Before:
   ContentUnavailableView(
       emptyCopy.title,
       systemImage: emptyCopy.systemImage,
       description: Text(emptyCopy.description))
       .frame(minHeight: viewHeight, alignment: .center)

   // After — same modifier:
   ContentUnavailableView(…)
       .background(
           .regularMaterial,
           in: RoundedRectangle(cornerRadius: ReminderCardView.emptyStateCornerRadius))
       .frame(minHeight: viewHeight, alignment: .center)
   ```

**NOT changed**:
- No padding pair (the card's `.padding(12)` / `.padding(-12)` trick) — these
  branches are in `ScrollView`, not `List`, so row metrics don't apply.
- No changes to populated card, watch, widget, `ControlPlateModifier`, or copy
  strings.

**Tests**: No new unit tests at this stage — `.regularMaterial` is not
`Equatable`, and the `emptyStateCornerRadius` constant was already asserted in
Stage 1. The visual change is verified manually.

**Verify**:
- `make build` succeeds (compiler verifies the modifier syntax and type).
- Manual: screenshot "Nothing due" and "All Done" over a photo background in
  light + dark mode, matching the slots in
  `docs/SimulatorManualVerification.md`.

---

## Stage 3: UI Test — "Nothing Due" Coverage

Close the test gap flagged in research: no UI test covers the `hasHidden == true`
"Nothing due" path. Use the `--seed` seam to seed a store with all visible
reminders skipped, then assert the "Nothing due" `ContentUnavailableView`
renders.

**Files**:
- `SingleThreadUITests/SingleThreadUITestsFlows.swift` (add test method)

**Key changes**:
```swift
// New test in SingleThreadUITestsFlows, following existing pattern
// (testEmptyListShowsNoRemindersState at ~line 45):

@MainActor
func testNothingDueShowsWhenAllVisibleRemindersSkipped() {
    let app = launchApp(seedJSON: #"""
    {"reminders":[{"title":"Buy groceries","notes":"milk"}],
     "skippedIdentifiers":["Buy groceries"]}
    """#)

    XCTAssertTrue(
        app.staticTexts["Nothing due"].waitForExistence(timeout: 5),
        "When all visible reminders are skipped, 'Nothing due' should appear")
}
```

**Seed shape**: the `--seed` JSON accepts `skippedIdentifiers` (an array of
reminder titles matched by `InMemoryEventStore`). One reminder seeded +
skipped → `visibleReminders.isEmpty && !reminders.isEmpty` → `allSkipped` is
`false` (there are reminders, just none visible) → `hasHidden` is `true` →
"Nothing due" branch.

**Tests**:
- `testNothingDueShowsWhenAllVisibleRemindersSkipped` — happy path.
- Existing `testEmptyListShowsNoRemindersState` and
  `testListShowsSeededReminder` remain green as regression guards.
- `testAccessibilityAudit()` (`SingleThreadUITests.swift:27-66`) — the
  existing audit runs against the No Reminders empty branch; it must still
  pass (the plate is invisible to the audit).

**Verify**: `make ui-test` passes for `SingleThreadUITests`.

---

## Testing Checkpoints

| Stage | What must be green before advancing |
|-------|-------------------------------------|
| 1 — Design Token | `make test` (unit tests): `BackgroundCardTests` all pass |
| 2 — View | `make build` succeeds; manual screenshots match expectations |
| 3 — UI Test | `make ui-test` passes; `./scripts/test.sh` (full gate) passes |
