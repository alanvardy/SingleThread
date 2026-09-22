# Task

Update reminder sorting in the SingleThread iOS app (VAR-1062). Rework the
`ReminderSort` comparator chains in `SingleThreadCore` to the specified rules —
**Sort by Priority** orders by priority then due date then title; **Sort by
Title** orders by title only; **Sort by Due Date** orders by due date then
priority then title — and add a new **Default** `SortOption` that keeps items in
the order the API provides them (i.e. no reordering).

This spans the Core `SortOption`/`ReminderSort`/`ReminderStore` (the `.sorted`
path must skip sorting for `.default`), the app-target `SortOption` presentation
(label + SF symbol), the persistence plumbing (`SortOptionStore` load/save,
present in `app-group` AppGroup.shared), and the settings picker which renders
`SortOption.menuOptions`. Read the codebase to wire it end to end and cover it
with tests.

## Why MEDIUM
MATCHED: MULTI_MODULE + BROAD_TEST_SURFACE. The change crosses `SingleThreadCore`
and the `SingleThread` app target plus the shared `SortOption` persistence value
(low-level comparator + shared store, easy to regress), but the approach is known
and M1–M2 hold: no schema/migration, no new subsystem, no design sign-off.

## Key files (recon
- `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift` — add `.default`
  case (a selectable `menuOptions` entry); keep load/save backward compatible.
- `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift` — reorder the
  `.priority`/`.dueDate`/`.title` chains per the ticket; note the current code
  injects a `compareLists` step into each chain that the ticket's spec does not
  mention — decide whether to keep/drop it; add `.default` (= "raw API order").
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` (~line 175) —
  the `.sorted` call must not reorder when `sortOption == .default`.
- `SingleThread/SortOption+Presentation.swift` — add `.default` `title`
  (localized) + `systemImage`.
- `SingleThread/FilterSortSettingsView.swift`, `SingleThread/SettingsView.swift`,
  `SingleThread/ContentView.swift`, `SingleThread/AppViewModel.swift` — the
  picker is driven by `menuOptions` and watchers (`== .ai`) may need review for
  the new case; the phone computes/pushes the ordered list to the watch, so no
  watch-side sorting change is expected.
- Tests: `SingleThreadTests/SortOptionTests.swift` (raw value, `allCases`,
  `menuOptions`, presentation, store round-trip) and `SingleThreadTests/
  ReminderSkipTests.swift` (`ReminderSortTests`) — assert the exact new chains
  incl. a `.default` no-reorder path.
- `SortOption.defaultsKey` is the shared persistence key (AppGroup.defaults,
  `--ui-testing`/`--seed` seams) — keep raw values backward compatible.