# Implementation Plan — VAR-801: Reminder tap on watch

## Overview

A tap on the watch reminder card refreshes the list directly (reusing the
existing `refresh(clearSkipped:)` path, `isRefreshing` guard, and spinner), with
the Refresh/Delete confirmation dialog removed. Delete remains reachable only via
the action menu and skip-nudge banner, unchanged.

Three horizontal stages, matching `structure.md`: add the VM action + test first
(additive), then swap the view and delete the dialog + its two UI tests, then run
the full CI-identical gate.

---

## Stage 1: ViewModel — `cardTapped()` (additive)

The app still compiles, the dialog still works, and the new method is
independently unit-tested. Nothing observable changes.

### Changes

#### 1. Add `cardTapped()` to the watch view model
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Insert one method immediately above `func refresh(clearSkipped: Bool) async`:

```swift
    /// A tap on the reminder card refreshes the list directly (no dialog),
    /// pruning skip state without un-skipping a still-visible window. Inherits
    /// `refresh`'s `guard !isRefreshing` re-entrancy absorption — no new state.
    func cardTapped() async {
        await refresh(clearSkipped: store.allSkipped)
    }
```

No other change in this file. `isShowingRefreshConfirmation` stays untouched
(`var isShowingRefreshConfirmation = false`, ~line 50) until Stage 2.

#### 2. New unit test for `cardTapped()`
**File**: `SingleThreadWatchTests/WatchReminderViewModelTests.swift`
**Action**: create

```swift
import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

// MARK: - Fixture

/// A single `EKEventStore` kept alive to back the test reminders. `EKReminder`
/// holds a weak reference to its backing store, so a deallocated store crashes
/// (SIGTRAP) when any property is read. Mirrors `ReminderStoreWatchTests` and
/// `ShowCompletionGlowStateTests` — `InMemoryEventStore.makeReminder` is iOS-only,
/// so watch unit tests build reminders against a live store.
@MainActor private let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

/// Covers `WatchReminderViewModel.cardTapped()`: a card tap runs a full refresh
/// cycle (`isRefreshing` false → true → false) and passes `store.allSkipped`
/// through as `clearSkipped`, pruning (never clearing) skip state while a
/// reminder is still visible.
@MainActor
@Suite(.serialized)
struct WatchReminderViewModelTests {
    @Test
    func cardTappedTriggersRefreshCycle() async {
        let skipKey = "watch-cardtap-skip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: skipKey) }

        let visible = watchReminder("Visible")
        let skipped = watchReminder("Skipped")
        // The reload path prunes from the *persisted* skip store, not the
        // in-memory `skippedIDs`, so the isolated store must be pre-seeded.
        let skipStore = SkippedReminderStore(defaults: .standard, key: skipKey)
        skipStore.save([skipped.calendarItemIdentifier])

        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [visible, skipped]),
            skipStore: skipStore,
            loadsReminders: true,
            reminders: [visible, skipped],
            skippedIDs: [skipped.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let viewModel = WatchReminderViewModel(
            store: store,
            showDateState: ShowDateState(),
            showRecurrenceState: ShowRecurrenceState(),
            showAlarmsState: ShowAlarmsState(),
            showListState: ShowListState(),
            showCompletionGlowState: ShowCompletionGlowState(),
            entitlementState: EntitlementState(),
            showEnableActionButtonsState: ShowEnableActionButtonsState())

        #expect(!viewModel.isRefreshing)
        #expect(!store.allSkipped) // "Visible" is not skipped, so a reminder shows

        // `refresh` sets `isRefreshing = true` synchronously ahead of its first
        // suspension, so a single yield lets the spawned task reach it.
        let cycle = Task { await viewModel.cardTapped() }
        await Task.yield()
        #expect(viewModel.isRefreshing)

        await cycle.value // includes the ~1 s `refreshMinimumDisplayDuration` pad

        #expect(!viewModel.isRefreshing)
        // Prune (`clearSkipped == false`) keeps the still-fetched skip; a wrong
        // `clearSkipped: true` would have cleared it to `[]`.
        #expect(store.skippedIDs.contains(skipped.calendarItemIdentifier))
    }
}
```

Fixture notes (verified against the tree):
- The 8 `WatchReminderViewModel` state params are all no-arg `init()` holders
  (`ShowDateState()`, `ShowRecurrenceState()`, `ShowAlarmsState()`,
  `ShowListState()`, `ShowCompletionGlowState()`, `ShowEnableActionButtonsState()`,
  `EntitlementState()`).
- `ReminderStore.init` labels are `eventStore:skipStore:loadsReminders:reminders:
  skippedIDs:authorizationStatus:` (all other params defaulted).
- `SkippedReminderStore(defaults:key:)` is `public`.
- The test runs ~1 s because `refresh` pads to `refreshMinimumDisplayDuration ==
  1`. Acceptable for a single test; we do **not** inject a shorter duration
  (that would require widening `private static let refreshMinimumDisplayDuration`
  or editing `refresh(clearSkipped:)`, both out of scope). If the suite ever
  becomes slow, revisit with an injected duration as a follow-up.
- `@Suite(.serialized)` + a unique `skipKey` (with `defer` cleanup) matches the
  `ReminderStoreWatchTests` isolation convention; the default `SkipCountStore` /
  `ExcludedListStore` / `PendingCompletionStore` touch shared `.standard` keys
  but never affect the `skippedIDs` assertion.

### Verification
#### Automated
- [x] `make watch-test` passes — `WatchReminderViewModelTests.cardTappedTriggersRefreshCycle` green, and all existing `SingleThreadWatchTests` suites stay green.
- [x] `make watch-build` passes (watch app target compiles with the new method, warnings-as-errors applies only where the file belongs).

#### Manual
- [ ] Open the watch app in the simulator: tapping the card still opens the Refresh/Delete dialog (unchanged — Stage 1 is additive); refresh still works behind the dialog.

---

## Stage 2: View — tap gesture, dialog removal, test deletion

Replace the `.onTapGesture` body with a direct `Task` call to `cardTapped()`,
delete the `isShowingRefreshConfirmation` flag and its dialog, and remove the two
obsolete UI tests.

### Changes

#### 1. Delete the `isShowingRefreshConfirmation` flag
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Delete the line (adjacent to `var isRefreshing = false`):

```swift
    var isShowingRefreshConfirmation = false
```

It has exactly one write and one read (both in `WatchReminderView.swift`, being
deleted below) — no other references exist (repo-wide `rg` confirmed in research).

#### 2. Replace the tap gesture and delete the dialog
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In `private func reminderCard(_ reminder: EKReminder) -> some View`, change the
`ScrollView` modifiers — replace the `.onTapGesture` body and delete the
`.confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation) { … }`
block.

Before:
```swift
    private func reminderCard(_ reminder: EKReminder) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                let display = ReminderDisplay(reminder: reminder)
                reminderDetails(display)
            }
            .onTapGesture {
                viewModel.isShowingRefreshConfirmation = true
            }
            .accessibilityAddTraits(.isButton)
            .confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation) {
                Button("Refresh") {
                    Task { await viewModel.refresh(clearSkipped: viewModel.store.allSkipped) }
                }
                .accessibilityIdentifier("refreshButton")

                Button(SharedStrings.deleteAction, role: .destructive) {
                    Task { await viewModel.store.deleteCurrentReminder() }
                }
                .accessibilityIdentifier("deleteButton")
            }
```

After:
```swift
    private func reminderCard(_ reminder: EKReminder) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                let display = ReminderDisplay(reminder: reminder)
                reminderDetails(display)
            }
            .onTapGesture {
                Task { await viewModel.cardTapped() }
            }
            .accessibilityAddTraits(.isButton)
```

**KEEP `@Bindable var viewModel = viewModel`** (line ~239). It is **not**
orphaned after this change: it still supplies the `$` bindings for the nudge
dialog (`$viewModel.isShowingNudgeDialog`, ~line 269), the action-menu dialog
(`$viewModel.isShowingActionMenu`, ~line 284), and the reschedule sheet
(`$viewModel.isShowingRescheduleSheet`, ~line 287), all of which remain in
`reminderCard`. This corrects `structure.md` Stage 2, which claimed its only `$`
use was the removed dialog. (The separate `@Bindable` inside
`actionMenuRescheduleSheet()`, ~line 298, is unrelated and stays.)

`.accessibilityAddTraits(.isButton)` (~line 248) stays on the tap target.
`SharedStrings.deleteAction` remains imported/used by the other two dialogs — no
import cleanup.

#### 3. Delete `testTapRevealsConfirmationDialog`
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITests.swift`
**Action**: modify

Delete the entire `@MainActor func testTapRevealsConfirmationDialog()` method
(source lines 9–27, including the `// The --ui-testing seam seeds...` comment
block). Leave `setUpWithError` and `testAccessibilityAudit` intact. The file's
`// The --ui-testing seam…` element-location comment was specific to this method;
delete it with the method.

#### 4. Delete `testDeleteViaConfirmationDialogRemovesReminder`
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify

Delete the `// MARK: - Delete (via confirmation dialog)` marker and the entire
`@MainActor func testDeleteViaConfirmationDialogRemovesReminder()` method (lines
~222–241). The adjacent `// MARK: - Refresh` / `testRefreshPresentOnNoRemindersState`
section stays.

### Verification
#### Automated
- [x] `make format` applies cleanly (SwiftFormat reorders per `organizeDeclarations`; run it, then commit its result).
- [x] `make lint` passes — `swiftformat --lint` + `swiftlint lint --strict` both clean (the removed flag/dialog leave no dead identifiers; the retained `@Bindable` avoids the unused-binding warnings-as-errors failure).
- [x] `make watch-test` passes (Stage 1 test still green).
- [x] `make watch-ui-test` passes — the 12 remaining `SingleThreadWatchUITestsFlows` tests + `testAccessibilityAudit` + `testLaunch` are green; `testTapRevealsConfirmationDialog` and `testDeleteViaConfirmationDialogRemovesReminder` are gone.

#### Manual
- [ ] `.pi/qrspi/…/structure.md` checkpoint obedience: action-menu delete (`Flows:134-159`), nudge-delete (`Flows:189-222`), empty/all-done refresh (`Flows:255`), a11y audit, and the remaining 12 flow tests all pass (covered by `make watch-ui-test`).
- [ ] On the simulator: tapping the reminder card directly triggers the refresh (spinner appears briefly, list re-fetches) — no dialog. Delete is still reachable via the action menu (`--ui-testing-action-menu`) and the 6-skip nudge banner.

---

## Stage 3: Full gate

Verification only — no file changes.

### Changes

None.

### Verification
#### Automated
- [x] `./scripts/test.sh` passes: format, lint, iOS build, watch build, Periphery (no dead code from the removed `isShowingRefreshConfirmation` flag or dialog identifiers), iOS unit, iOS UI, watch unit, watch UI all green — passes modulo 2 known local-only macOS `EntitlementStoreTests` SKTestSession failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`; pre-existing, CI mac-tests green, `SingleThreadTests/EntitlementStoreTests.swift` untouched by this diff).

#### Manual
- [ ] Confirm no `refreshButton`/`deleteButton`/dialog references remain in the watch UI-test target beyond the standalone `refreshButton` identifier at `WatchReminderView.swift` (~line 206) — `rg "isShowingRefreshConfirmation|deleteButton" SingleThreadWatch SingleThreadWatchUITests` returns nothing (the standalone `refreshButton` is expected to remain).

---

## Testing Checkpoints

| After Stage | Command | What must pass |
|---|---|---|
| 1 | `make watch-test` | `WatchReminderViewModelTests.cardTappedTriggersRefreshCycle` green; all existing `SingleThreadWatchTests` green |
| 2 | `make format && make lint && make watch-ui-test && make watch-test` | 12 remaining Flows + a11y audit + launch green; format/lint clean; Stage 1 test green |
| 3 | `./scripts/test.sh` | Full CI gate green — all platforms, all suites, no dead code |