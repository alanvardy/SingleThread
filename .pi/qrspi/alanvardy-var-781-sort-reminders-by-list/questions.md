# Research Questions

## Context

This is an EventKit-backed Reminders app with a shared core package (SingleThreadCore) consumed by the iOS app, a watchOS companion, a macOS app, and a widget. User-visible reminders are produced as a single sorted array by the core, and a user-selectable sort option is persisted and synced across devices. Relevant areas: the reminder sort comparator and its tests, the reminder/list data model, consumers of the sorted array across targets, preference persistence and cross-device sync, the settings UI, and the UI-test seeding seam.

## Questions

1. **Sort comparator architecture** — How is the reminder sort comparator (`ReminderSort.areInIncreasingOrder`) implemented, and how does each `SortOption` case compose its ordering (primary key, tie-break chain, final fallback)? What invariants do the comparator unit tests pin down about determinism, strict total ordering, and option equivalence?

2. **List identity and metadata** — How are reminder lists (calendars) modeled in the codebase? What identifies a list (title? calendar identifier?), where does the app surface list metadata such as name, color, or ID on a reminder, and how does the app handle lists that share titles or get renamed — including the exclusion-by-title feature and `availableLists`?

3. **Consumers of the sorted array** — Which code paths consume the produced sorted reminder array (`visibleReminders`), across iOS, watchOS, macOS, and the widget? Where does any consumer assume a particular ordering, such as relying on the first element, and are there any places that re-sort or re-order independently?

4. **Preference persistence and sync** — How is a user-selectable preference like the sort option persisted (`SortOptionStore`/App Group defaults), restored on launch for each target (app, watch, widget), and synced between phone and watch over WatchConnectivity? Are there other preference values that follow the same pattern?

5. **Sort behavior testing** — What do the existing tests that guard reminder ordering look like — unit tests at the comparator and store level, and UI tests that assert reminder order? What can the `--seed` JSON UI-testing seam currently stage (per-reminder fields, calendars, due dates, exclusions) and what is it unable to stage?

6. **Settings UI structure** — How is the settings UI for choosing a sort option structured (`FilterSortSettingsView`, `SortOption+Presentation`), how is its value bound through `SettingsBindings`/`@AppStorage` to the store, and how are settings rows and pickers tested (unit and UI)?