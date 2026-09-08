# Structure Outline

## Approach

Fix the watch completion glow so it visibly flashes, then add a UI-test seam
and watch UI tests that mirror the existing iOS coverage — all built
bottom-up, each layer tested green before the next begins.

---

## Stage 1: Root-Cause Fix — Make the Glow Visible on watchOS

**What this layer delivers**: A visible green flash when the user taps Complete on
a real watch (or simulator). Existing unit tests stay green; the glow is
observable to the naked eye.

The investigation will test three hypotheses, ranked by likelihood:

| # | Hypothesis                                             | Fix                                               |
|---|--------------------------------------------------------|---------------------------------------------------|
| a | 0.25 s duration is imperceptible on watchOS           | Increase `CompletionGlow.duration` to 0.5 s      |
| b | Computed `reminderViewModel` replaces `CompletionGlow` | Store view model; change computed → lazy stored    |
| c | Unknown cause                                          | Diagnose on device/simulator, apply targeted fix   |

**Files**:
- `SingleThreadWatch/WatchAppViewModel.swift` — if hypothesis (b): change
  `reminderViewModel` from computed to stored; or touch `completionGlow.duration`
  after creation
- `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift` — if hypothesis
  (a): change the default `duration` from `0.25` to `0.5`

**Key changes** (most likely — hypothesis a):
- `CompletionGlow.duration` default: `TimeInterval = 0.25` → `TimeInterval = 0.50`

If hypothesis (b):
- `WatchAppViewModel.reminderViewModel`: change from `var reminderViewModel:
  WatchReminderViewModel { … }` → `lazy var reminderViewModel =
  WatchReminderViewModel(…)` stored once in `init()`

**Tests**:
- Existing unit tests (`CompletionGlowTests`, `ShowCompletionGlowStateTests`,
  `WatchSyncPipelineTests`, `WatchReminderTests`) must stay green
- If changing from computed to stored: add a `WatchAppViewModelTests` unit test
  that `reminderViewModel` returns the same instance across multiple accesses
- If changing `CompletionGlow.duration` default: update
  `CompletionGlowTests.glowAutoDismissesAfterDuration` — it currently sets
  `duration = 0.05` explicitly, so the default change doesn't break it; verify
  the test still passes at the new shorter effective time

**Verify**:
```bash
make test                          # unit tests pass
make watch-build                    # compiles for watchOS
```
Then manual: launch on watch simulaor (`make watch-build` + run from Xcode),
tap Complete, confirm a visible green flash.

---

## Stage 2: Watch UI Test Seam — `--ui-testing-glow` + `--ui-testing-glow-disabled`

**What this layer delivers**: Two new launch-argument seams that make the glow
testable from watch UI tests, mirroring the iOS `--ui-testing-glow` pattern:
1. `--ui-testing-glow`: extends duration to 2.0 s and exposes the overlay to
   accessibility with `accessibilityIdentifier("completionGlowOverlay")`
2. `--ui-testing-glow-disabled`: pre-sets `ShowCompletionGlowState` to disabled,
   so the disabled-flow UI test doesn't need a settings screen

Existing tests (unit + watch UI) must stay green.

**Files**:
- `SingleThreadWatch/WatchAppViewModel.swift` — detect both flags in `init()`,
  wire them into the view model
- `SingleThreadWatch/WatchReminderView.swift` — conditionally expose the overlay
  to accessibility when the seam is active

**Key changes**:

`WatchAppViewModel` additions:
```swift
// New stored property (replaces/reorients the computed property from Stage 1):
// If Stage 1 already changed to stored, just add the seam logic here.
var isGlowUITesting: Bool          // true when --ui-testing-glow is present

// In init(), after creating showCompletionGlowState:
if arguments.contains("--ui-testing-glow-disabled") {
    showCompletionGlowState.apply(false)
}
let isGlowUITesting = arguments.contains("--ui-testing-glow")
self.isGlowUITesting = isGlowUITesting

// In the stored view model, after creating it:
if isGlowUITesting {
    viewModel.completionGlow.duration = 2.0
}
```

`WatchReminderView` changes (in `completionGlowOverlay`):
```swift
// Before:
.accessibilityHidden(true)
// After:
.accessibilityHidden(!viewModel.isGlowUITesting)
// And add:
.accessibilityIdentifier("completionGlowOverlay")
.accessibilityLabel("Completion glow")
.accessibilityElement(children: .ignore)
```

The `isGlowUITesting` flag must reach `WatchReminderView`. Route it either:
- Through `WatchReminderViewModel` (add `let isGlowUITesting: Bool` init param)
- Or have the view read `ProcessInfo.processInfo.arguments` directly (matches
  iOS's `ContentView.isGlowUITesting` pattern — simpler, fewer plumbing changes)

**Decision**: Use the `ProcessInfo`- reads-directly pattern from iOS — it's a
one-line computed property in the view, no view model plumbing needed. This
keeps `WatchReminderViewModel`' init surface unchanged.

```swift
// In WatchReminderView:
private var isGlowUITesting: Bool {
    ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")
}
```

**Tests**:
- Existing watch UI tests (`make watch-ui-test`) must stay green
- Existing iOS glow UI tests must stay green (regression check)
- Existing `ShowCompletionGlowStateTests` must stay green (the `--ui-testing-glow-disabled`
  seam doesn't affect unit tests — they create their own holders)

**Verify**:
```bash
make test                          # unit tests green
make watch-build                   # compiles
make watch-ui-test                 # existing watch UI tests green
./scripts/test.sh --ui-only       # iOS UI tests green (regression)
```

---

## Stage 3: Watch Glow UI Tests

**What this layer delivers**: Two new watch UI tests that assert the glow
appears when enabled and does NOT appear when disabled, mirroring
`testCompletionGlowFlashesWhenEnabled` / `testCompletionGlowDoesNotAppearWhenDisabled`
from `SingleThreadUITestsFlows.swift`.

**Files**:
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` — add two test methods

**New tests**:

```swift
// Enabled: glow fires after completion, visible for 2 s
@MainActor
func testCompletionGlowFlashesWhenEnabled() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    let complete = app.buttons["Complete reminder"]
    XCTAssertTrue(complete.waitForExistence(timeout: 3))
    complete.tap()

    XCTAssertTrue(
        app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3),
        "Glow overlay should flash briefly after completion")
}

// Disabled: glow suppressed, no overlay ever appears
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
```

**No new types or signatures** — these are XCTest test methods following the
existing `SingleThreadWatchUITestsFlows` pattern (launch with `--ui-testing` +
additional seam flags, assert on accessibility identifiers).

**Tests**: these ARE the tests — they exercise the complete-then-glow flow.

**Verify**:
```bash
make watch-ui-test    # includes both new glow tests
```

If the watch simulaor isn't available on this machine, skip this checkpoint
and rely on CI (`watch-ui-tests` job).

---

## Stage 4: Integration Validation

**What this layer delivers**: Confidence that nothing regressed across the full
matrix — iOS unit, iOS UI, watch unit, watch UI, macOS, lint, periphery.

**Files**: none (validation-only stage)

**Tests**: the full gate

**Verify**:
```bash
./scripts/test.sh    # format, lint, build, periphery, unit + UI (iOS + watch)
```

**CI check**: the PR's `watch-ui-tests` job runs the new glow tests in the GitHub
Actions matrix on a standalone watchOS simulaor.

---

## Testing Checkpoints

| Stage | What must be green before advancing          | Command                  |
|-------|----------------------------------------------|--------------------------|
| 1     | Unit tests + manual visual confirmation      | `make test && make watch-build` |
| 2     | Unit + existing watch UI + iOS UI regression  | `make test && make watch-ui-test && ./scripts/test.sh --ui-only` |
| 3     | New watch glow UI tests                      | `make watch-ui-test`     |
| 4     | Full gate (format, lint, build, periphery, all tests) | `./scripts/test.sh` |