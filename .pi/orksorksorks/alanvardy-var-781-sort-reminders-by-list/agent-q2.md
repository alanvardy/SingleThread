# Agent Q2 — List identity and metadata

## 1. How reminder lists (calendars) are modeled

**There is no app-level list model type.** Lists are raw EventKit `EKCalendar` objects, reached only through the `EventKitStoring` protocol seam:

- `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:13-16` — protocol exposes `func calendars(for entityType: EKEntityType) -> [EKCalendar]` (plus predicate/fetch/save APIs). `EKEventStore` conforms at `EventKitStoring.swift:25-`; the test/in-memory implementation returns an injected `[EKCalendar]` at `InMemoryEventStore.swift:52-54`.

**Only the `.title` attribute of a calendar is ever consumed anywhere in the repo.** All three read sites:

1. `ReminderStore.swift:480-483` (`reload()`): `availableLists = Set(eventStore.calendars(for: .reminder).map(\.title).filter { !$0.isEmpty }).sorted()`
2. `ReminderStore.swift:150` (`visibleReminders`): exclusion filter on `$0.calendar?.title ?? ""`
3. `ReminderDisplay.swift:16`: `listName = reminder.calendar?.title`

No calendar **color**, **default-calendar flag**, or content-modification flags are read anywhere (zero hits for `cgColor`/`isDefaultForReminders`/`allowsContentModifications` on calendars across production targets).

## 2. What identifies a list → the title string

The app treats the **title string as the list identity**; `EKCalendar.calendarIdentifier` appears **zero times** in Swift sources. By contrast, `calendarItemIdentifier` (the *reminder's* EventKit ID) is the reminder identity used throughout for skip/complete/delete/undo (e.g. `ReminderStore.swift:149, 456, 677`; `ContentViewModel.swift:201` deep link).

Title-as-identity is embodied in three store properties:

- `ReminderStore.swift:57` — `public private(set) var excludedListTitles: Set<String> = []`
- `ReminderStore.swift:71` — `public private(set) var availableLists: [String] = []` (doc comment at `:70`: "All reminder-list titles (sorted, deduplicated) the settings UI presents.")
- `ReminderStore.swift:150` — the filter: `.filter { !excludedListTitles.contains($0.calendar?.title ?? "") }` inside `visibleReminders` (`:147-152`)

`ExcludedListStore` persists the titles in `UserDefaults` under key `"excludedListTitles"` (`ExcludedListStore.swift:7` init default, `:15` `load()` via `stringArray`, `:19` `save()`).

## 3. Where list metadata is surfaced on a reminder

The single projection is `ReminderDisplay.listName: String?` (`ReminderDisplay.swift:48`), set from `reminder.calendar?.title` in `init(reminder:)` (`ReminderDisplay.swift:16`). **Only the name is surfaced — never color and never any calendar ID** (the 8-field struct at `ReminderDisplay.swift:45-51` has no identifier field at all).

Three render sites, all gated behind the `showList` preference (App Group key `"showList"`, default `false`, `ContentView.swift:124-125`; toggle "Show list" in `ReminderSettingsView.swift:39-49`):

1. **iOS card** — `ReminderCardView.swift:108-112`: `if showList, let listName = display.listName, !listName.isEmpty { Text(listName) … .accessibilityIdentifier("listNameText") }`
2. **Watch** — `WatchReminderView.swift:347-348`: `if viewModel.showListState.isEnabled, let listName = display.listName { Text(listName) }`
3. **Widget** — `NextThingWidget.swift:207-208`: `if entry.showsList, let listName = display.listName, !listName.isEmpty { Text(listName) }`; `showsList` comes from `BoolPreferenceStore(key: BoolPreferenceKey.showList.rawValue, fallback: false)` at `NextThingWidget.swift:58`.

The watch and widget also receive/read the `showList` flag over WatchConnectivity (`SkippedReminderSyncService.swift:221, 431-434`).

## 4. The exclusion-by-title feature (`excludedListTitles`)

- **Filter** — `visibleReminders` (`ReminderStore.swift:147-152`): reminders whose `calendar?.title` is in `excludedListTitles` are dropped, sorted after filtering. A `nil` calendar maps to `""` and is never excluded (empty titles are also filtered out of `availableLists` at `:483`).
- **Set path (user/Settings)** — `setExcludedListTitles(_:)` at `ReminderStore.swift:409-417`: assigns in-memory, `excludeStore.save(Array(titles))`, fires `onExcludedListsChanged` **and** `onRemindersChanged`. Wired to Settings via `excludedListsBinding` (`ContentView.swift:141-146`, get/in-set both hit the store) → `SettingsView` → `FilterSortSettingsView.swift:41-45` → `ExcludedListsView` toggles.
- **Receive path (WatchConnectivity)** — `refreshExcludedListTitles(_:)` at `ReminderStore.swift:419-429`: updates memory + `onRemindersChanged` only — deliberately **no** `onExcludedListsChanged` echo (documented anti-echo at `:420-425`). Hooked on iPhone in `AppViewModel.swift:377-380` and on watch in `WatchAppViewModel.swift:224-226`; the sync payload key is `PayKey.excludedListTitles` (`SkippedReminderSyncService.swift:205` push, `:400-404` receive).
- **Rehydration** — every `reload()` re-applies the persisted set via `reconcileSkipState` → `excludedListTitles = Set(excludeStore.load())` at `ReminderStore.swift:679`.

## 5. `availableLists`

- Populated **only** inside `reload()` (`ReminderStore.swift:480-484`), which itself only runs after `.fullAccess` (`start()` at `:194-203` → `reload()`; `requestAccess` at `:434-444`). Before first full-access reload it is `[]` (tested: `ReminderStoreTests.swift:111-119`).
- **Deduplication by title**: a `Set` collapses duplicate titles; `.sorted()` gives case-sensitive order, so `"Work"` and `"work"` remain distinct entries (pinned by `EventKitStoringTests.swift:505-519` asserting `["Personal", "Work", "work"]` from calendars `Work, Personal, work, Work, ""`).
- **Consumption chain** (Settings only): `ContentView+Settings.swift:12` → `SettingsView.init` (`SettingsView.swift:21, 28`) → `FilterSortSettingsView` (`SettingsView.swift:94-96`; stored at `FilterSortSettingsView.swift:14`) → `ExcludedListsView` (`FilterSortSettingsView.swift:41-45`; `ForEach(availableLists, id: \.self)` at `ExcludedListsView.swift:21`). Watch and widget never read it.

## 6. Shared titles and renamed lists — consequences of title-as-identity

- **Shared titles**: filtering and display are purely title-based. Excluding `"Work"` hides reminders from *every* calendar titled `"Work"`. UI identity in `ForEach(..., id: \.self)` is the title string itself (`ExcludedListsView.swift:21`) — made safe only because `availableLists` is deduped by construction. The in-memory store seeds `reminder.calendar = defaultCalendar` (`InMemoryEventStore.swift:139-142`), i.e. one title per fixture.
- **Renamed lists**: there is **no identifier-based tracking and no rename reconciliation**:
  - The exclusion set stores the title at exclusion time (`ReminderStore.swift:409-417`). Renaming a calendar leaves the stale title in the set; its reminders reappear because `:150` no longer matches. Renaming an unexcluded calendar *into* an excluded title hides it. Nothing rewrites the stored set against identifiers.
  - There is **no EventKit change observation** — no `EKEventStoreChanged`/`NotificationCenter` observers anywhere in production code (also documented as a deliberate non-feature in `.pi/qrspi/.../var-750/design.md:83`). All refetches are explicit `reload()` calls; `availableLists`/exclusions are only refreshed on those reloads.
  - On reload, exclusions are re-read from persistence (`ReminderStore.swift:679`) rather than regenerated, so a renamed-away list keeps its exclusion entry silently until the user toggles it in Settings (where `availableLists` now shows the current titles).

## 7. Test coverage pinning this behavior

- `SingleThreadTests/ReminderStoreTests.swift:100-106` (excluded list empties `visibleReminders`), `:111-119` (`availableListsDefaultsToEmpty`), `:127-142` (`setExcludedListTitlesPersistsAndFiresHooks`), `:148-164` (`refreshExcludedListTitles` anti-echo).
- `SingleThreadTests/EventKitStoringTests.swift:505-529` (`availableListsSortedAndDeduplicatedAfterReload`, `availableListsEmptyWhenNoCalendars`).
- `SingleThreadTests/ExcludedListStoreTests.swift:9-24` (load/save round-trip, **save replaces not unions**, key isolation).
- `SingleThreadTests/ReminderDisplayTests.swift:60-71` (`listNameFollowsCalendar` — maps `calendar.title` and `nil` calendar → `nil`).
- UI test seed: launch-argument calendars + `excludedLists` become `excludedListTitles` (`UITestingSeed.swift:130-166`, field at `:37`, persisted-keys wipe list at `:76`); seeded application path `AppViewModel.swift:344-345` calls `store.setExcludedListTitles`.

## 8. Current branch sort context

Per agent-q1: current `SortOption` enum has exactly `priority`/`dueDate`/`title` (`SortOption.swift:6-19`) and `ReminderSort` has no list/calendar comparison key — the sort has no list identity concept today.