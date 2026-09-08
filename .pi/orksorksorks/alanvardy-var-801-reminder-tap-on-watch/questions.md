# Research Questions

## Context

Focus on the Apple Watch app (`SingleThreadWatch/`) and the shared domain
layer it uses (`SingleThreadCore/`): the reminder card view and its
tap/gesture handling, the confirmation dialogs and the state flags that drive
them, the refresh and delete flows through `WatchReminderViewModel` and
`ReminderStore`, the accessibility exposure of interactive controls, and the
watch UI-test suites (`SingleThreadWatchUITests/`) with their launch seams.

## Questions

1. How does a tap on the reminder card flow through `WatchReminderView.swift`
   — from the `onTapGesture` on the card's `ScrollView`, through the
   `isShowingRefreshConfirmation` state flag, to the `confirmationDialog("Reminder")`
   and its Refresh/Delete buttons? What is the full lifecycle of that flag and
   the dialog's other bindings (labels, accessibility identifiers, destructive
   styling)?

2. How does the reminder refresh operation work end-to-end on the watch:
   `WatchReminderViewModel.refresh(clearSkipped:)` with its `isRefreshing`
   guard and `MinimumDisplayDuration` spinner convention, the underlying
   `ReminderStore.reload(clearSkipped:)` behavior on watchOS, and every UI
   site that currently invokes refresh (the empty/all-done `refreshButton` and
   the card-tap dialog)?

3. What are all the ways the delete-reminder action is currently reachable on
   the watch (card-tap dialog, toggle-gated action menu, skip-nudge banner),
   how is the action menu gated (`ActionMenuGate`, `--ui-testing-action-menu`),
   and how does the nudge banner's behavior depend on the skip/delete flow?

4. How are the card tap target, the dialog buttons, and the in-progress
   refresh indicator exposed to accessibility (`.accessibilityAddTraits(.isButton)`,
   `.accessibilityIdentifier`, `ProgressView` overlay, glow seams), and which
   of these does the UI accessibility audit (`.dynamicType`, `.hitRegion`,
   `.sufficientElementDescription`, `.trait`) exercise?

5. Which XCTest suites cover the card tap and its dialog (`testTapRevealsConfirmationDialog`,
   the flows file), how do those tests locate card content versus dialog
   buttons (text label vs `accessibilityIdentifier` vs dialog label), and what
   `--ui-testing*` launch seams and seeded-store fixtures drive them?

6. Which watch interactions currently execute immediately without any dialog
   (Complete button, direct Skip, refresh from the empty/all-done states), and
   which use a `confirmationDialog` or `.sheet` — i.e., what are the existing
   conventions for when a direct action versus a dialog is used while an
   action is in flight?