# Task

Fix VAR-1004: the "Show action buttons" toggle in the macOS app's Settings does nothing. It **should show and hide** the bottom-bar action buttons (Complete / Skip / Delete / action menu), matching the iOS behavior.

Root cause: `ContentView.bottomBar`'s macOS branch gates the `actionButtons` cluster on `viewModel.store.visibleReminders.first != nil` only — it never consults `enableActionButtons`. The toggle currently only morphs the Skip button into a three-action menu vs. three separate buttons, so the buttons never disappear and the setting appears dead. The iOS side already gates its equivalent (`actionCluster`) on `viewModel.showsActionButtons` (`enableActionButtons && store.visibleReminders.first != nil`), which is the pattern to mirror.

Fix scope:

- `SingleThread/ContentView.swift` — in `bottomBar`, change the `#if os(macOS)` gate to use `viewModel.showsActionButtons` (which implies a visible reminder) so the toggle hides/shows the buttons on macOS.
- `SingleThread/ContentView+ActionMenu.swift` — check `macShowActionMenu` / `actionButtons` for consistency with the gated behavior if the split changes.
- Follow the existing iOS gating pattern; do not change the App Group key, persistence, or iOS paths. Toggle-off should behave like iOS: no action cluster, just the primary dictation control.

Testing (bug fix — add a test that reproduces the symptom):

- `SingleThreadTests/` (Swift Testing) — unit-test the `ContentViewModel.showsActionButtons` predicate (already written to be testable without a live view): false when `enableActionButtons` is off even with a visible reminder, true when both hold. Extend `EnableActionButtonsSyncTests`-style coverage if a gap exists for the macOS-visible path.
- A UI test is likely not justified; state why if skipped (the logic lives in the testable `showsActionButtons` predicate / view-model).
- Run `make format` and `make lint` in-line, then the project gate before committing.

## Why SMALL

Single module, ≤2 files, existing pattern (iOS `showsActionButtons` gate on `ContentView.bottomBar`), 0–2 unknowns, no schema/migration, no new subsystem or shared/convention code, no design sign-off (ticket wording + iOS precedent dictate the behavior), and few local tests.

## Key files

- `SingleThread/ContentView.swift` — `bottomBar` macOS branch (currently gates on `store.visibleReminders.first != nil`, ignores `enableActionButtons`); iOS gate at line ~715 is the precedent.
- `SingleThread/ContentView+ActionMenu.swift` — macOS `actionButtons` / `macShowActionMenu` (shape switching).
- `SingleThread/ContentViewModel.swift` — `showsActionButtons` predicate (already testable).
- `SingleThread/ContentView+Settings.swift`, `SingleThread/InterfaceSettingsView.swift` — macOS settings toggle wiring (verified working: writes through `@AppStorage("enableActionButtons")` in the App Group).
- `SingleThreadTests/EnableActionButtonsSyncTests.swift` — existing sync coverage to extend.