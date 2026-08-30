# Structure Outline

## Approach

Add a presentation-only delay on the watchOS completion path so the reminder
card stays visible behind the fading green glow, then transitions to the empty
state after the glow finishes. A new `isShowingCompletionTransition` flag on
`WatchReminderViewModel` gates the empty-state branch; the flag is set
synchronously before the glow trigger and cleared by a `Task.sleep` after
`glow.duration + 0.5 s`. No shared-code changes — the watch-only view model
and view are the sole touchpoints.

---

## Stage 1: ViewModel — Completion Transition State & Logic

**What this layer delivers**: The state machine for the post-completion
card-hold window. `WatchReminderViewModel` gains a flag, a captured reminder
reference, and timing logic. The flag is set on successful completion, prevents
re-entry (double-tap guard), and clears after the glow finishes. Unit tests
prove every state transition without touching the view or a UI-test harness.

**Files**:
- `SingleThreadWatch/WatchReminderViewModel.swift` — add properties + modify `completeCurrentReminder()`
- `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift` — add transition-state tests (this is the existing watch view-model test file)

**Key changes**:

```swift
// New properties on WatchReminderViewModel:
var isShowingCompletionTransition = false
var transitionReminder: EKReminder?
var completionTransitionBuffer: TimeInterval = 0.5  // test-configurable

// Modified completeCurrentReminder():
func completeCurrentReminder() async {
    guard !isShowingCompletionTransition else { return }           // double-tap guard
    transitionReminder = store.visibleReminders.first              // capture before mutation
    if await store.completeCurrentReminder(),
       showCompletionGlowState.isEnabled {
        isShowingCompletionTransition = true
        completionGlow.trigger()
        let delay = completionGlow.duration + completionTransitionBuffer
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            if store.visibleReminders.isEmpty {                     // store check before clearing
                isShowingCompletionTransition = false
                transitionReminder = nil
            }
        }
    } else {
        transitionReminder = nil                                    // completion failed
    }
}
```

**Tests** (added to `ShowCompletionGlowStateTests.swift`):

| Test | Covers |
|---|---|
| `transitionFlagStartsFalse` | flag is `false` at init |
| `transitionFlagSetOnSuccessfulComplete` | flag is `true` + `transitionReminder` is non-nil after `completeCurrentReminder()` with glow enabled |
| `transitionFlagNotSetWhenGlowDisabled` | flag stays `false` when `showCompletionGlowState.isEnabled == false` |
| `transitionFlagNotSetWhenNothingToComplete` | flag stays `false` when store has no visible reminders |
| `doubleTapIsNoOp` | calling `completeCurrentReminder()` while flag is set returns immediately, glow triggers exactly once |
| `transitionFlagClearsAfterDelay` | set `completionGlow.duration = 0.05`, `completionTransitionBuffer = 0.01`; after `Task.sleep(0.1)`, flag is `false` and `transitionReminder` is `nil` |
| `transitionFlagStaysSetIfStoreRepopulated` | after completion clears the store, inject a new reminder during the delay window; flag remains `true` after the sleep |

**Verify**: `make test` passes for `SingleThreadWatchTests` (the new tests are green). No view changes yet — the flag exists but nothing reads it.

---

## Stage 2: View — Ghost-Card Branch Gating

**What this layer delivers**: The `reminderContent` view in
`WatchReminderView` reads the new flag. When `isShowingCompletionTransition`
is `true`, it renders a "ghost card" using `transitionReminder` — the card
stays on screen with the glow overlay fading over it, while the store already
says the list is empty. After the delay (Stage 1 clears the flag), the view
re-evaluates and falls through to the normal empty-state branches.

**Files**:
- `SingleThreadWatch/WatchReminderView.swift` — add one branch in `reminderContent`

**Key change**:

```swift
// In reminderContent, the ZStack branch order becomes:
if viewModel.isShowingCompletionTransition,
   let reminder = viewModel.transitionReminder {
    reminderCard(reminder)        // ghost card — store is empty, but card stays
} else if viewModel.store.allSkipped {
    allDoneState
} else if let reminder = viewModel.store.visibleReminders.first {
    reminderCard(reminder)
} else {
    noRemindersState
}
```

The rest of the view is unchanged. Action buttons on the ghost card are
naturally no-op: Complete hits the guard in Stage 1, Skip finds no visible
reminder in the store. The glow overlay and its `.animation` continue to
render above whichever branch is active.

**Tests**: No new unit tests — the view change is a pure consumption of the
already-tested Stage 1 state machine. Run the existing watch UI test suite to
confirm no regressions:

**Verify**: `make ui-test` passes for `SingleThreadWatchUITests`. The existing
`testCompleteRemovesReminder`, `testCompletionGlowFlashesWhenEnabled`, and
`testCompletionGlowDoesNotAppearWhenDisabled` must all stay green. Manual
spot-check on the watch simulator: complete a reminder and confirm the card
doesn't vanish instantly, the glow fades over it, then the empty state appears.

---

## Stage 3: UI Tests — Post-Completion Timing Verification

**What this layer delivers**: A UI-test assertion that the card remains
visible during the glow window and the empty state appears only after the
delay elapses. This is the integration proof — the view model flag (Stage 1)
and the view branch (Stage 2) together produce the correct user-visible
timing.

**Files**:
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` — extend or add test

**Key change**: Add a new test `testCompleteHoldsCardDuringGlow` (or extend
`testCompletionGlowFlashesWhenEnabled`):

```swift
@MainActor
func testCompleteHoldsCardDuringGlow() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    let complete = app.buttons["Complete reminder"]
    XCTAssertTrue(complete.waitForExistence(timeout: 3))
    complete.tap()

    // Card must stay visible during the glow (2 s glow + 0.5 s buffer = 2.5 s window).
    // Assert card text is still present immediately after the tap — it must NOT
    // disappear in under 1 s.
    XCTAssertTrue(
        app.staticTexts["Buy groceries"].waitForExistence(timeout: 1),
        "Card should persist during the post-completion glow")

    // Glow overlay must be present (existing assertion, preserved).
    XCTAssertTrue(
        app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3))

    // After the full delay (2.0 + 0.5 = 2.5 s), the empty state must appear.
    // Use a generous timeout to account for CI executor variance.
    XCTAssertTrue(
        app.staticTexts["No Reminders"].waitForExistence(timeout: 8),
        "After the glow fades, the No Reminders state should appear")
}
```

The existing `testCompleteRemovesReminder` (no `--ui-testing-glow`) is
unchanged — that test asserts `No Reminders` appears after complete, which
still works (production glow is 0.50 + 0.50 = 1.0 s, well within the existing
5 s timeout).

**Verify**: `make ui-test` passes all `SingleThreadWatchUITests` tests.
`./scripts/test.sh` (full gate) passes.

---

## Testing Checkpoints

1. **After Stage 1**: `make test` → `SingleThreadWatchTests` green (7 new
   transition tests pass; existing tests unchanged)
2. **After Stage 2**: `make ui-test` → all existing watch UI tests green (no
   regressions) + manual glance at simulator
3. **After Stage 3**: `make ui-test` → new timing test green + all existing
   tests green; `./scripts/test.sh` → full gate green

## Open Design Questions

- **Buffer testability**: The design says the buffer constant should be
  test-configurable (`completionTransitionBuffer: TimeInterval = 0.5` as an
  `internal var` on the view model, matching `CompletionGlow.duration`). If
  kept as `private static let`, unit tests would sleep 0.55 s total (0.05 s
  glow + 0.5 s buffer) — acceptable but less clean. Recommend `internal var`
  for consistency with the existing glow-duration seam pattern.
- **`transitionReminder` type**: `EKReminder` holds a weak reference to its
  `EKEventStore`. The view model owns the store, so the reference is safe
  during the transition window. No need for a `ReminderDisplay` wrapper copy.