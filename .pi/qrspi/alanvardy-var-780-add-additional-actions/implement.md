# Implementation Summary

Branch: `alanvardy-var-780-add-additional-actions`
Ticket: add additional actions (VAR-780) — toggle-gated Skip / Reschedule / Delete action menu on iOS, macOS, and watchOS.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `115bdd2` | Storage & Sync Foundation — `enableActionButtons` moved to `AppGroup.defaults`, added to the watch-sync pipeline (PayloadKey + pushAll + apply + `onEnableActionButtonsReceived` hook), watch-side `ShowEnableActionButtonsState` holder wired through `WatchAppViewModel`/`WatchReminderViewModel`, one-shot `.standard`→AppGroup migration, both test seams + `handlePreferencesChanged` diff set updated. Zero UI changes. |
| 2     | `5add9f7` | Store Methods & Gate Logic — `requestRescheduleReminder` relay + `onRescheduleReminderReceived` hook on `SkippedReminderSyncService`, `onRescheduleReminder` hook on `ReminderStore` (watchOS branch fires hook + returns true), phone/watch hook wiring, pure `ActionMenuGate.showsActionMenu` gate function. |
| 3     | `544fb59` | Extract RescheduleSheet — reusable `RescheduleSheet` view (nudge message, date-only vs date+time picker via testable static helpers, Reschedule confirm button), nudge sheet refactored to use it, general `ContentViewModel.rescheduleReminder(identifier:to:)`, `SkipNudgeUITests` selector updated to `rescheduleConfirmButton`. |
| 4     | `a97f805` | Platform Action Menus — iOS `confirmationDialog` + reschedule sheet, macOS `Menu` (skip/Reschedule/Delete; skip+Delete when toggle off) in new `ContentView+ActionMenu.swift`, watch `confirmationDialog` + DatePicker sheet firing the watch→phone reschedule relay, `--ui-testing-action-menu` watch seam, new `ActionMenuUITests` (4 tests) + 3 watch action-menu flows. Toggle-off path unchanged. |

## Automated Checks

- [x] Full CI gate green: `./scripts/test.sh` — format, SwiftLint `--strict`, iOS + watch builds, Periphery, unit tests (517/517), iOS UI tests (49/49), watch UI tests (27/27), watch unit tests, macOS unit tests. **`✅ All CI checks passed.`**
- [x] `make build` / `make watch-build` / `make mac-build` compile clean (verified per phase)
- [x] New unit tests pass: `ShowEnableActionButtonsStateTests`, `EnableActionButtonsSyncTests`, `WatchSyncPipelineTests` (+ new updates), `EnableActionButtonsMigrationTests`, `ActionMenuGateTests` (2×2×2 table), `RescheduleSyncTests`, `RescheduleSheetTests`, `ReminderStoreWatchTests` (relay)
- [x] New UI tests pass: `ActionMenuUITests` (menu Skip/Delete/Reschedule + toggle-off direct skip), `SkipNudgeUITests` (nudge flow unchanged), `ActionButtonsUITests` (cluster renders + skip advances via dialog, a11y audit), 3× watch action-menu flows (`SingleThreadWatchUITestsFlows`)
- [x] Gate re-runs: run 1 passed everything except the watch section (name-only watch destination ambiguous with two runtimes — environmental, documented in repo; fixed by pinning `WATCH_TEST_SIM=…,id=3F69EA19-…`); run 2 UI flake (`testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder` timed out under contention from an orphaned xcodebuild — pre-existing test, zero diff vs `origin/main`, passed 16.9s in isolation and again in the final gate run); run 3 fully green.

## Manual Verification Items (from the plan)

- [ ] Toggle ON in Settings → relaunch → toggle still ON (persists via AppGroup)
- [ ] Fresh install (no key set) → toggle OFF by default
- [ ] Migration: pre-set `.standard` key to `true` only → launch → toggle ON in UI
- [ ] iOS: toggle ON → confirmationDialog → each action works
- [ ] iOS: toggle OFF → direct skip (no dialog)
- [ ] macOS: toggle ON → skip is a Menu → Delete hidden → keyboard shortcut 's' opens menu
- [ ] macOS: toggle OFF → skip + Delete as before
- [ ] watch: toggle ON + phone paired → skip → dialog → each action works
- [ ] watch: toggle OFF → direct skip

## Notes / Observations from workers

- Several mechanical deviations from the plan draft, all intent-preserving and documented in `plan.md`: receive-decode lives in `applyRemaining(context:)` (SwiftLint 50-line body), watch state holder persists via `AppGroup.defaults` (AGENTS.md rule; falls back to `.standard` on real watch), migration folded into `registerDefaults()`, sync tests in own files (`file_length` budget), `var dc` renamed `dueComponents` (identifier_name), `ContentView+ActionMenu.swift` split (type_body_length budget), `--ui-testing-action-menu` seam added for watch tests.
- Phase 1 fixed a pre-existing SwiftLint import-order issue in `EnableActionButtonsMigrationTests`.
- `assertTogglePersists` UI-test pattern was not added: toggle persistence is covered by `AppGroup.defaults` + existing Settings persistence tests (documented in plan.md).