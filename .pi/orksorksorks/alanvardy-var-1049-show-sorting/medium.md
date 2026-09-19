# Task

Add a new button to the existing "Filtering & Sorting" settings subscreen
(`SingleThread/FilterSortSettingsView.swift`) labeled "View sorted and filtered
list" (or a better suggestion), which shows all reminders ordered and filtered
by the current Filtering & Sorting settings (sort option, show-undated toggle,
AI sort rules, excluded lists).

The data plumbing already exists and is live: `ReminderStore.visibleReminders`
(`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:167-180`) is
already filtered (skipped IDs, excluded lists) and sorted (`ReminderSort` /
`AI` ranks) per the current settings, and the main `ContentView` already reacts
to settings changes via `SettingsBindings`/`PreferenceHolder`. So no new
sorting/filtering logic is required — the work is a view-layer addition:

- Add the button in `FilterSortSettingsView.swift` (wired into the existing
  `.settingsSubscreenLayout()`).
- Provide a "see all reminders" surface that renders `visibleReminders` in
  order. Note SingleThread is a single-card-at-a-time app — decide the list
  representation (scrollable all-at-once `List` reusing `ReminderCardView` vs.
  tap-through progression) and get it sign-off'd in the plan step.
- Wire navigation from the button through `ContentView.swift` (settings sheet
  → list sheet) and add the new label to the localization
  `SingleThread/Resources/Localizable.xcstrings`.
- Ship unit tests covering the new view + any wiring logic (Swift Testing in
  `SingleThreadTests/`, following existing `FilterSortSettingsViewTests.swift`
  / `ReminderStoreTests.swift` patterns).

## Why MEDIUM

MULTI_MODULE breadth trigger: the change spans ~4–5 files across the settings
module (`FilterSortSettingsView.swift`, `.xcstrings`) and the content module
(`ContentView.swift`, a new list-view file, possibly `ContentViewModel`)
— more than one module and more than ~5 files. M1–M2 hold: the approach is
known (sort/filter is already applied to `visibleReminders`; just surface it),
and there is no schema/migration, no new subsystem or integration, and no
shared/convention-format risk — it is an additive view-layer change following
existing patterns. One design question (list representation in a
single-card-at-a-time app) is resolvable in the plan step with a ⭐-option;
it does not warrant the full LARGE research/design pipeline.

## Key files

- `SingleThread/FilterSortSettingsView.swift` — add the button (the
  "Filtering & Sorting" subscreen; `NavigationLink`/`Button` in
  `.settingsSubscreenLayout()`).
- `SingleThread/ContentView.swift` — settings-sheet wiring
  (`makeSettingsBag()`/`settingsSheetContent`, ContentView.swift:133-369) and
  the new destination sheet/navigation.
- `SingleThread/ContentViewModel.swift` — any view orchestration for the new
  surface.
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` — the
  source of truth for the sorted/filtered set: `visibleReminders`
  (167-180), `filteredReminders` (161-165); reuses `ReminderSort.swift`,
  `SortOption.swift`.
- `SingleThread/Resources/Localizable.xcstrings` — new button label.
- Tests: `SingleThreadTests/FilterSortSettingsViewTests.swift`,
  `SingleThreadTests/ReminderStoreTests.swift`,
  `SingleThreadTests/ContentViewModelTests.swift`; UI XCTest surface in
  `SingleThreadUITests/SingleThreadUITests.swift` /settingsButton.