# Structure Outline

## Approach

Replace the card-tap confirmation dialog (Refresh/Delete) with a direct
refresh, preserving the existing `refresh(clearSkipped:)` path, in-flight
`isRefreshing` guard, and spinner. Three horizontal stages: add the VM method
and test it first, then swap the view and delete the dialog, then finalize
the full gate.

---

## Stage 1: ViewModel — `cardTapped()` (additive)

Add the `cardTapped()` async action to the VM without touching the existing
flag, dialog, or view. This stage is purely additive — the app still
compiles, the dialog still works, and the new method is independently
testable.

**Files**:
- `SingleThreadWatch/WatchReminderViewModel.swift` — add method
- `SingleThreadWatchTests/WatchReminderViewModelTests.swift` — **new file**

**Key changes**:
- `WatchReminderViewModel.cardTapped() async` — new method:
  calls `await refresh(clearSkipped: store.allSkipped)`. No new state, no
  flag, no re-entrancy guard of its own (inherits `refresh`'s `guard
  !isRefreshing`).
- `WatchReminderViewModel.isShowingRefreshConfirmation` — **untouched** in
  this stage (still `var … = false` at line 50).

**Tests** (`SingleThreadWatchTests/WatchReminderViewModelTests.swift`):
- `cardTappedTriggersRefreshCycle` — constructs VM with a store that
  actually reloads (not `loadsReminders: false`); calls `cardTapped()`;
  asserts `isRefreshing` transitions `false → true → false` and
  `clearSkipped` is passed as `store.allSkipped`.
- (Fixture concern for the plan phase: init needs 8 state objects; reuse
  patterns from `WatchAppViewModelTests` / `ReminderStoreWatchTests`; the
  1 s `refreshMinimumDisplayDuration` makes the test slow — plan will
  address via injected duration or task-yield observation.)

**Verify**: `make watch-test` passes for the new suite + existing
`SingleThreadWatchTests` suites stay green. Watch app still builds.

---

## Stage 2: View — tap gesture, dialog removal, test deletion

Remove the `isShowingRefreshConfirmation` flag and its confirmation dialog.
Replace the `.onTapGesture` body with a direct `Task` call to
`cardTapped()`. Delete the two UI tests that assert on the now-removed
dialog. Clean up the now-orphaned `@Bindable` inside `reminderCard`.

**Files**:
- `SingleThreadWatch/WatchReminderViewModel.swift` — delete flag
- `SingleThreadWatch/WatchReminderView.swift` — replace tap gesture + delete
  dialog + remove orphaned `@Bindable`
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — delete test
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` — delete test

**Key changes**:
- **Deleted**: `var isShowingRefreshConfirmation = false` (VM:50)
- **Deleted**: `viewModel.isShowingRefreshConfirmation = true` (View:246)
- **Deleted**: `.confirmationDialog("Reminder", isPresented:
  $viewModel.isShowingRefreshConfirmation) { … }` block (View:249-259)
  including its Refresh and Delete buttons
- **Deleted**: `@Bindable var viewModel = viewModel` inside `reminderCard`
  (View:239) — its only `$` binding was `isPresented:` on the dialog
- **Replaced**: `.onTapGesture { … }` body (View:245-247) →
  `Task { await viewModel.cardTapped() }`
- **Preserved**: `.accessibilityAddTraits(.isButton)` (View:248) — stays on
  the tap target
- **Deleted**: `testTapRevealsConfirmationDialog` (SingleThreadWatchUITests.swift:9-27)
- **Deleted**: `testDeleteViaConfirmationDialogRemovesReminder`
  (SingleThreadWatchUITestsFlows.swift:224-241)

**Tests** (existing, now minus two):
- Watch UI suites pass: action-menu delete (`Flows:134-159`), nudge-delete
  (`Flows:189-222`), empty/all-done refresh (`Flows:255`), a11y audit
  (`SingleThreadWatchUITests.swift:30-42`), and the remaining 12 Flows
  tests.
- Watch unit tests from Stage 1 still green.
- Build passes with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — the
  `@Bindable` removal is confirmed (a leftover unused `@Bindable` would be a
  warning → error).
- `make lint` clean (SwiftLint `--strict`, SwiftFormat `--lint`).

**Verify**: `make watch-ui-test` passes (all remaining watch UI tests
green); `make watch-test` passes (including Stage 1 test); `make lint`
clean.

---

## Stage 3: Full gate

Run the complete CI-identical gate to confirm no regressions across iOS,
watchOS, and macOS test suites, and that Periphery finds no dead code from
the removed dialog identifiers.

**Files**: none (verification only)

**Key changes**: none

**Tests**: full `./scripts/test.sh` — format, lint, iOS build, watch
build, Periphery, iOS unit (iPhone + iPad), iOS UI, watch unit, watch UI,
macOS unit.

**Verify**: `./scripts/test.sh` exits 0 with all suites green.

---

## Testing Checkpoints

| After Stage | Command | What must pass |
|---|---|---|
| 1 | `make watch-test` | `WatchReminderViewModelTests.cardTappedTriggersRefreshCycle` green; all existing `SingleThreadWatchTests` green |
| 2 | `make watch-ui-test && make lint` | All 12 remaining Flows + a11y audit green; format/lint clean |
| 3 | `./scripts/test.sh` | Full CI gate green — all platforms, all suites, no dead code |