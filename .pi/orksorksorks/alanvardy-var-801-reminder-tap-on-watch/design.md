# Design Discussion — VAR-801: Reminder tap on watch

## Current State

Tapping the reminder card on the watch opens a confirmation dialog offering
Refresh and Delete. All watch UI lives in one view file.

- Card tap target is the card's `ScrollView` with `.onTapGesture` whose only
  side effect sets `viewModel.isShowingRefreshConfirmation = true`
  (`SingleThreadWatch/WatchReminderView.swift:241-247`).
- That flag drives the dialog `.confirmationDialog("Reminder", isPresented:
  $viewModel.isShowingRefreshConfirmation)` (`WatchReminderView.swift:249`),
  which holds Refresh (`:250-253`, id `refreshButton`) and Delete
  (`:255-258`, id `deleteButton`, `role: .destructive`). No Cancel button.
- The flag has exactly one write (`View:246`) and one read (`View:249`); it is
  declared at `WatchReminderViewModel.swift:50`, reset only by SwiftUI's
  two-way `isPresented:` binding on dismissal.
- `@Bindable var viewModel = viewModel` inside `reminderCard`
  (`WatchReminderView.swift:239`) exists only to supply the `$` binding for
  `isPresented:` — an MVVM-refactor requirement (VAR-697).
- Tap accessibility is the single `.accessibilityAddTraits(.isButton)`
  (`WatchReminderView.swift:248`) — no label or identifier.
- Refresh runs through `WatchReminderViewModel.refresh(clearSkipped:)`
  (`WatchReminderViewModel.swift:121-133`): `guard !isRefreshing` re-entry
  guard → `isRefreshing = true` → `store.reload(clearSkipped:)` →
  1 s `MinimumDisplayDuration` pad → `isRefreshing = false`. The dialog's
  Refresh button calls it with `viewModel.store.allSkipped`
  (`WatchReminderView.swift:251`); on a card tap a reminder is visible, so
  `allSkipped == false` (`ReminderStore.swift:156-158`), i.e. prune skip state
  without un-skipping the window.
- Delete is reachable at three sites: card-tap dialog (`View:255-258`), the
  toggle-gated action menu (`View:211-221`, gate `View:81-85`, OFF by default
  via `ShowEnableActionButtonsState.swift:14-16`), and the 6-skip nudge banner
  (`View:261-274`, `WatchReminderViewModel.swift:92-93`).
- Two UI tests assert the card-tap dialog:
  `testTapRevealsConfirmationDialog` (`SingleThreadWatchUITests.swift:9-27`)
  and `testDeleteViaConfirmationDialogRemovesReminder`
  (`SingleThreadWatchUITestsFlows.swift:224-241`).

## Desired End State

A tap on the reminder card refreshes the list directly, with no dialog. The
Refresh (and Delete) dialog is gone; the card remains the touch target and
keeps its `.isButton` trait. Delete remains reachable via the action menu
(when enabled) and the skip-nudge banner, unchanged.

Verification:
- Watch unit test: `cardTapped()` runs the refresh cycle and passes
  `store.allSkipped` as `clearSkipped`.
- Existing watch UI suites pass with the two dialog tests removed; the
  action-menu delete (`Flows:134-159`), nudge-delete (`Flows:189-222`), and
  empty/all-done refresh (`Flows:255`) flows still pass unchanged.
- `./scripts/test.sh` full gate passes (format, lint, build, watch build,
  Periphery, unit + UI, watch unit + watch UI).

## Patterns to Follow

- **Immediate actions are `async` VM methods invoked from a `Task` in the
  view.** `completeCurrentReminder()` (`WatchReminderViewModel.swift`) is the
  model to mirror for `cardTapped()`; the view's existing `.onTapGesture`
  becomes `Task { await viewModel.cardTapped() }`. Do not recreate the pattern
  of mutating a `@State`/VM flag inline from the view — this change removes
  the last such write (`View:246`).
- **In-flight convention.** Reuse `refresh(clearSkipped:)` untouched: the
  `isRefreshing` guard (`WatchReminderViewModel.swift:122`), the shared
  `ProgressView` overlay (`View:113-117`), and the 1 s minimum display. The
  spinner and `.disabled` on the standalone refresh button (`View:205`) are
  unchanged; the new tap path inherits the guard's re-entrancy absorption
  (the dialog Refresh button had no `.disabled`, and the VM guard was its
  protection — the tap needs no disabled state either).
- **`clearSkipped` semantics.** Preserve `store.allSkipped`
  (`ReminderStore.swift:156-158`) as the argument, identical to the removed
  dialog call, so a tap never un-skips a window that still shows a reminder.
- **Presentation-flag lifecycle.** The removed flag was the canonical
  default-false / two-way-binding-reset shape. The remaining flags
  (`isShowingActionMenu`, `isShowingNudgeDialog`, `isShowingRescheduleSheet`,
  `isShowingCompletionTransition`) stay exactly as-is — we only delete
  `isShowingRefreshConfirmation` (`WatchReminderViewModel.swift:50`) and its
  dialog block.
- **Accessibility.** Keep `.accessibilityAddTraits(.isButton)` (`View:248`).
  Avoid adding supplementary labels/ids to the card or spinner: the a11y audit
  exercises the card in its rest state only (`SingleThreadWatchUITests.swift:30-42`),
  and the card is already located by visible text label
  (`app.staticTexts["Buy groceries"]`, `Flows` convention).
- **UI-test element rules.** Dialog buttons were queried by dialog label
  (`app.buttons["Refresh"]`/`"Delete"`), non-dialog buttons by identifier.
  Removing the dialog removes the label-based dialog queries; the remaining
  `refreshButton` identifier (`View:206`) is unaffected.

### Patterns NOT to follow

- The inline flag write at `View:246` (`viewModel.isShowingRefreshConfirmation
  = true`) — exactly what this change deletes.
- The `nudgeIdentifier` doc/code gap (`WatchReminderViewModel.swift:53` says
  "cleared on delete/dismiss/refresh" but nothing clears it on watch): do not
  add new state whose lifecycle is only implicit. The new tap path adds no
  state.

## Design Decisions

1. **Tap = direct refresh, dialog removed** — the `.onTapGesture` calls a new
   VM action; `isShowingRefreshConfirmation` (decl, write, read) and the
   `Refresh/Delete` `confirmationDialog` block (`View:249-259`) are deleted.
   Scope is confined to the card-tap interaction, per the task.
2. **New `WatchReminderViewModel.cardTapped() async`** — calls
   `await refresh(clearSkipped: store.allSkipped)`. Owns the tap semantics in
   the VM (MVVM), mirrors `completeCurrentReminder()`, and is unit-testable in
   `SingleThreadWatchTests` (Q2-A).
3. **`clearSkipped` preserved as `store.allSkipped`** — identical to the
   removed dialog call; keeps behavior byte-for-byte with today (Q3-B).
4. **Delete reachability unchanged** — Remove only the card-tap dialog. Do
   NOT flip the action-menu toggle default or add a long-press/other delete
   affordance. A default user retains delete only via the (off-by-default)
   action menu and the 6-skip nudge banner (Q1-A).
5. **Test strategy** — delete the two obsolete UI tests
   (`testTapRevealsConfirmationDialog`, `testDeleteViaConfirmationDialogRemovesReminder`);
   add a `SingleThreadWatchTests` unit test asserting `cardTapped()` completes
   a refresh cycle (`isRefreshing` returns to `false`) and does not un-skip.
   Delete coverage already exists via the action-menu and nudge flows (Q4-A).
6. **Follow-on cleanups** — remove the now-unused `@Bindable var viewModel`
   inside `reminderCard` (`View:239`) if `isPresented:` was its only `$` use;
   a warning would fail the build under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

## What We're NOT Doing

- Not touching the action menu, its gate, `ActionMenuGate`, or the
  `--ui-testing-action-menu` seam.
- Not changing the skip-nudge banner or `nudgeIdentifier`/`isNudged`.
- Not altering Complete, direct Skip, or the reschedule sheet.
- Not flipping the action-menu toggle ON by default (delete reachability for
  default users stays as-is).
- Not adding pull-to-refresh, `.refreshable`, or any new refresh site.
- Not fixing the pre-existing lack of `defer`/`try/catch` in
  `refresh(clearSkipped:)` (`WatchReminderViewModel.swift:121-133`) — it
  survives as-is; the tap path inherits it.
- Not adding accessibility identifiers/labels to the card tap target or the
  spinner.
- Not adding a watch UI test for tap→refresh (under `--ui-testing` the
  fixture store is `loadsReminders: false`, so `reload` no-ops
  (`ReminderStore.swift:440`) and there is no stable observable).

## Open Risks

- **Delete for default users**: after this change, a user who never enables
  the action menu and has <6 skips cannot delete or reschedule from the watch
  — accepted per decision 4, but flag for product confirmation.
- **`@Bindable` removal**: if `reminderCard` has no remaining `$` binding after
  the dialog is deleted, the now-unused `@Bindable` must go or the
  warnings-as-errors build fails. Confirmed at implementation time.
- **Unit-test fixture cost**: `WatchReminderViewModel.init` needs 8 state
  objects; no `WatchReminderViewModelTests.swift` exists yet. The plan should
  reuse existing fixtures from `WatchAppViewModelTests` / the UI-test store,
  and note the ~1 s `refreshMinimumDisplayDuration` makes the test slow
  without injecting a shorter duration.
- **nudge/refresh interplay**: `cardTapped()` triggers `store.reload` but, on
  the watch, nothing clears `nudgeIdentifier` (pre-existing gap). A refresh
  from a nudge-bannered card will not dismiss the banner until the reminder
  leaves the visible list — unchanged by this ticket, but note it.
- **Obsolete UI-test names**: deleting the two XCTest methods also removes the
  only card-tap coverage; confirm nothing else references the now-removed
  dialog identifiers `refreshButton`/`deleteButton` inside the dialog context
  (the standalone `refreshButton` at `View:206` keeps them in use).