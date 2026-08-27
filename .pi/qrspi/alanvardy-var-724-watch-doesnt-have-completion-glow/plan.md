# Implementation Plan

## Overview

Make the watchOS completion glow visibly flash when tapping Complete, mirroring the
iPhone behavior, then add a `--ui-testing-glow` test seam and watch UI tests that
assert the glow appears and disappears.

---

## Phase 1: Root-Cause Fix — Make the Glow Visible on watchOS

### What this phase delivers

A visible green flash when the user taps Complete on a real watch (or simulator).
Existing unit tests stay green. If hypothesis (a) doesn't produce a visible flash
in manual testing, fall back to hypothesis (b).

### Changes

#### 1. Increase `CompletionGlow.duration` default (hypothesis a — most likely)

**File**: `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift`
**Action**: modify

```swift
// Before (line 20):
public var duration: TimeInterval = 0.25

// After:
public var duration: TimeInterval = 0.50
```

The current 0.25 s duration is too short on watchOS — the 0.4 s animation envelope
(`.easeInOut(duration: 0.4)`) means the glow fades out before it's perceptible.
Increasing to 0.5 s gives the glow one perceptible frame after the animation
envelope finishes.

No test changes needed: `CompletionGlowTests.glowAutoDismissesAfterDuration`
explicitly sets `glow.duration = 0.05` so it's unaffected by the default change.
`CompletionGlowViewModelTests` doesn't assert on duration at all.

#### 2. Fallback: change `reminderViewModel` from computed to stored (hypothesis b)

**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify — only if hypothesis (a) doesn't fix the visual flash

```swift
// Before (lines 53-64):
var reminderViewModel: WatchReminderViewModel {
    WatchReminderViewModel(
        store: store,
        showDateState: showDateState,
        showRecurrenceState: showRecurrenceState,
        showAlarmsState: showAlarmsState,
        showListState: showListState,
        showCompletionGlowState: showCompletionGlowState)
}

// After:
lazy var reminderViewModel = WatchReminderViewModel(
    store: store,
    showDateState: showDateState,
    showRecurrenceState: showRecurrenceState,
    showAlarmsState: showAlarmsState,
    showListState: showListState,
    showCompletionGlowState: showCompletionGlowState)
```

**And** add a unit test to confirm single-instance semantics:

**File**: `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift` (or new)
**Action**: modify / create

```swift
@Test
func reminderViewModelIsStableAcrossAccesses() {
    let appViewModel = WatchAppViewModel()
    let first = appViewModel.reminderViewModel
    let second = appViewModel.reminderViewModel
    #expect(first === second as AnyObject,
            "Computed → stored: view model must return the same instance")
}
```

**Note**: If this path is taken, skip the `duration` change — the root cause is
view-lifecycle, not duration. If hypothesis (a) works (visible flash at 0.5 s),
hypothesis (b) is not needed.

### Verification

#### Automated

- [x] `make test` passes (unit tests, including `CompletionGlowTests`)
- [x] `make watch-build` compiles
- [ ] If hypothesis (b) was applied: `make watch-test` passes (not applied — hypothesis (a) chosen)

#### Manual

- [ ] Launch watch app on simulator (`make watch-build` + run from Xcode with
  `SingleThreadWatch` scheme, Apple Watch Series 11 (46mm) destination)
- [ ] Tap **Complete reminder** button
- [ ] Confirm a visible green flash appears and auto-dismisses
- [ ] If no flash: apply hypothesis (b), rebuild, retest

---

## Phase 2: Watch UI Test Seam — `--ui-testing-glow` + `--ui-testing-glow-disabled`

### What this phase delivers

Two new launch-argument flags on watchOS, mirroring the iOS `--ui-testing-glow`
pattern, so watch UI tests can observe the glow deterministically.

### Changes

#### 1. `--ui-testing-glow`: extend duration + expose to accessibility

**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify — add seam logic in `init()` and a stored `isGlowUITesting` flag

After `showCompletionGlowState = ShowCompletionGlowState()` (line 32), add:

```swift
// --ui-testing-glow: extend the glow duration so UI tests can observe it
// --ui-testing-glow-disabled: pre-disable the state so the disabled-flow
//   test doesn't need a settings screen
if arguments.contains("--ui-testing-glow-disabled") {
    showCompletionGlowState.apply(false)
}
let isGlowUITesting = arguments.contains("--ui-testing-glow")
if isGlowUITesting, Phase 1 used the computed property {
    // The computed property rebuilds the view model on every access, so we
    // can't inject the extended duration here. Skip — the seam only affects
    // accessibility exposure for now.
}
```

If Phase 1 changed `reminderViewModel` to stored (hypothesis b), add after the
stored property initialization:

```swift
if isGlowUITesting {
    viewModel.completionGlow.duration = 2.0
}
```

If Phase 1 only changed `CompletionGlow.duration` (hypothesis a — no stored view
model), the duration extension must happen differently. We have two options:

**Option A** (simpler, matches iOS pattern): Set `completionGlow.duration = 2.0`
on the view model *inside the stored `reminderViewModel` accessor*. This requires
`reminderViewModel` to be stored (hypothesis b). If hypothesis (a) alone fixed the
visual bug, apply hypothesis (b) as well to support the seam.

**Option B**: Apply duration to the shared `CompletionGlow` type. Don't do this — it
would affect production code.

**Decision**: If Phase 1 used only hypothesis (a), apply the stored-property change
(hypothesis b) in this phase. The seam requires a stable view model reference.

Add a stored property to `WatchAppViewModel`:

```swift
// In WatchAppViewModel, alongside showCompletionGlowState:
let isGlowUITesting: Bool
```

In `init()`, after the state initialization block:

```swift
let isGlowUITesting = arguments.contains("--ui-testing-glow")
self.isGlowUITesting = isGlowUITesting
```

If the view model is stored: after creating it, apply the duration override:

```swift
if isGlowUITesting {
    viewModel.completionGlow.duration = 2.0
}
```

If the view model remains computed: set `isGlowUITesting` for the view to read.

#### 2. Expose the glow overlay to accessibility when `--ui-testing-glow` is set

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — add `isGlowUITesting` computed property and update the overlay

Add after the `@Environment` / `private let viewModel` block (around line 64):

```swift
/// True only for the completion-glow UI test; production always hides the
/// overlay from accessibility (unchanged behavior for real users).
private var isGlowUITesting: Bool {
    ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")
}
```

Update `completionGlowOverlay` (lines 141-148):

```swift
// Before:
private var completionGlowOverlay: some View {
    Color.green
        .opacity(0.3)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
}

// After:
private var completionGlowOverlay: some View {
    Color.green
        .opacity(0.3)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(!isGlowUITesting)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("completionGlowOverlay")
        .accessibilityLabel("Completion glow")
        .transition(.opacity)
}
```

This exactly mirrors the iOS `completionGlowOverlay` pattern (`ContentView.swift:480-493`).

### Verification

#### Automated

- [x] `make test` passes (unit tests)
- [x] `make watch-build` compiles
- [x] `make watch-ui-test` passes (existing tests — none assert on the glow yet, but
  they must not regress)
- [x] `./scripts/test.sh --ui-only` runs; the only failure is a **pre-existing**
  iOS `testSettingsOpensAndShowsControls` (app shows "Privacy Policy", test taps
  "Privacy") that already fails on `origin/main` — unrelated to this ticket. The
  glow iOS tests (`testCompletionGlowFlashesWhenEnabled`,
  `testCompletionGlowDoesNotAppearWhenDisabled`) pass.

#### Manual

- [ ] Launch with `--ui-testing --ui-testing-glow`: tap Complete, green flash should
  stay visible for ~2 s
- [ ] Launch with `--ui-testing --ui-testing-glow-disabled`: tap Complete, no green
  flash should appear

---

## Phase 3: Watch Glow UI Tests

### What this phase delivers

Two new watch UI tests that mirror the iOS coverage:
`testCompletionGlowFlashesWhenEnabled` and
`testCompletionGlowDoesNotAppearWhenDisabled`.

### Changes

#### 1. Add two test methods

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify — append before the `// MARK: Private` section

```swift
// MARK: - Completion glow

@MainActor
func testCompletionGlowDoesNotAppearWhenDisabled() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-glow-disabled"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    let complete = app.buttons["Complete reminder"]
    XCTAssertTrue(complete.waitForExistence(timeout: 3))
    complete.tap()

    XCTAssertTrue(
        app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
        "Completing should empty the list")
    XCTAssertFalse(
        app.otherElements["completionGlowOverlay"].exists,
        "Glow should be suppressed when disabled")
}

@MainActor
func testCompletionGlowFlashesWhenEnabled() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    let complete = app.buttons["Complete reminder"]
    XCTAssertTrue(complete.waitForExistence(timeout: 3))
    complete.tap()

    // Glow duration is extended to 2 s under the seam, so `waitForExistence`
    // is deterministic.
    XCTAssertTrue(
        app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3),
        "Glow overlay should flash briefly after completion")
}
```

No new types, no new files. These are XCTest methods in the existing
`SingleThreadWatchUITestsFlows` class.

### Verification

#### Automated

- [x] `make watch-ui-test` passes — the two new tests must be green
  ```bash
  xcodebuild -scheme SingleThreadWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
    -configuration Debug \
    -derivedDataPath DerivedData \
    test \
    -only-testing:SingleThreadWatchUITests
  ```
- [x] `make test` passes (unit tests — no regression)
- [x] `./scripts/test.sh --ui-only` passes (iOS UI tests — no regression; pre-existing `testSettingsOpensAndShowsControls` failure on `origin/main` is unrelated — verify glow iOS tests pass)

#### Manual

*(None — the automated tests ARE the verification)*

---

## Phase 4: Integration Validation

### What this phase delivers

Confidence that nothing regressed across the full CI matrix.

### Changes

**None.** This is a validation-only phase.

### Verification

#### Automated

- [ ] `./scripts/test.sh` passes end-to-end:
  ```bash
  ./scripts/test.sh
  ```
  This runs: format → lint → iOS build → watch build → Periphery → iOS unit
  tests → iOS UI tests → watch UI tests → macOS build → macOS unit tests

- [ ] Check that the new `--ui-testing-glow-disabled` and `--ui-testing-glow` flags
  are not flagged as dead code by Periphery. If they are (because Periphery sees
  them used only in `ProcessInfo.processInfo.arguments` string literals in test
  code, not in the main target), make sure the `.periphery.yml` excludes cover
  them — or accept the warning and verify it's a false positive since launch
  arguments are inherently runtime values.

#### Manual

- [ ] Review CI results on the PR — confirm the `ci.yml` matrix jobs all pass,
  including the `watch-ui-tests` job which runs the new glow tests on a
  standalone watchOS simulator.

---

## Summary of File Changes

| File | Phase | Action |
|------|-------|--------|
| `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift` | 1 | Modify: `duration` 0.25 → 0.50 |
| `SingleThreadWatch/WatchAppViewModel.swift` | 1, 2 | Modify: computed → stored `reminderViewModel` + seam flags |
| `SingleThreadWatch/WatchReminderView.swift` | 2 | Modify: `isGlowUITesting` + accessibility exposure |
| `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` | 3 | Modify: add 2 test methods |

## Deviation Notes

- Phase 1 and Phase 2 are coupled: if Phase 1 fixes the glow with only the
  `duration` change (hypothesis a), Phase 2 still requires the stored-view-model
  change (hypothesis b) so the `--ui-testing-glow` seam can inject
  `completionGlow.duration = 2.0`. The structure treats these as independent
  phases, but in practice they share the `WatchAppViewModel.reminderViewModel`
  property change.

- The `SingleThreadWatchUITests` target already exists — no new target, pbxproj
  object IDs, or CI matrix additions are needed (mitigating Design Decision 5's
  risk). The structure's mention of "creating a `SingleThreadWatchUITests`
  target" was precautionary; it already exists.