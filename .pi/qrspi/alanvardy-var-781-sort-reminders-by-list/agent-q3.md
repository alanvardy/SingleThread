# Agent Q3 — Consumers of the sorted array (`visibleReminders`)

## 1. Single point of production

- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:147-152` — `public var visibleReminders: [EKReminder]` filters `reminders` by `skippedIDs` then `excludedListTitles` and sorts with `.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }`.
- Comparator: `ReminderSort.swift:14-31` (`areInIncreasingOrder(_:_:using:)`; legacy 2-arg entry at :9-11 delegates to `.priority`). The only production call sites of the comparator are inside `visibleReminders`.
- `reminders` is assigned in `reload()` in **unsorted fetch order** (`ReminderStore.swift:455-490` area); ordering is deferred entirely to the computed property. The only other `.sorted()` in the store is `ReminderStore.swift:484` — `availableLists` (calendar titles, alphabetical) — unrelated to reminder ordering.

## 2. Core (shared) consumers — internal to ReminderStore

- `ReminderStore.swift:154-157` — `allSkipped` = `!reminders.isEmpty && visibleReminders.isEmpty` (presence only).
- `ReminderStore.swift:160-169` — `listContent` resolves display state and **assumes the first element**: `if let first = visibleReminders.first { return .reminder(ReminderDisplay(reminder: first)) }` (line 167-168). `ListContent` (`ListContent.swift:4-24`) is the canonical snapshot consumed by all four surfaces.
- `ReminderStore.swift:260-262` — `completeCurrentReminder()`: `guard let reminder = visibleReminders.first`.
- `ReminderStore.swift:315-317` — `deleteCurrentReminder()`: `visibleReminders.first`.
- `ReminderStore.swift:380-382` — `skipCurrentReminder()`: `visibleReminders.first` (interactive path, iOS/watch/macOS).
- `ReminderStore.swift:421-423` — `skipCurrentReminderImmediately()`: `visibleReminders.first` (widget path, documented at :417-420 as existing for `SkipReminderIntent`).

Tests asserting the ordering contract directly: `SingleThreadTests/ReminderStoreTests.swift:51-87` (priority/date sorts, exclusion), `:177-195` (`setSortOptionReordersVisibleReminders`). Comparator tests: `SingleThreadTests/ReminderSkipTests.swift:237-321` (per agent-q1, sort tests at :134-225).

## 3. iOS app (`SingleThread/`)

- `ContentView.swift:413` — in the `.reminder` branch of `switch viewModel.store.listContent` (line 377), renders `if let reminder = viewModel.store.visibleReminders.first` (**order assumption**: displays the first sorted reminder), with `ReminderDisplay(reminder:)` at :416 and the "View in Reminders" deep link / delete / swipe actions bound to that same first element (:414-450).
- `ContentView.swift:633` — `#if os(macOS)` `bottomBar`: `if viewModel.store.visibleReminders.first != nil { actionButtons }` (presence gate only).
- `ContentViewModel.swift:66` — iOS `showsActionButtons`: `AppGroup.defaults.bool(forKey:"enableActionButtons") && store.visibleReminders.first != nil` (presence gate).
- `AppViewModel.swift:84` — iOS notification scheduling: `let count = store.visibleReminders.count` (count only; no ordering assumption).
- `ContentView+ActionMenu.swift:22` — iOS `showActionMenu` gate `visibleReminders.first != nil` (presence).
- `ContentView+ActionMenu.swift:33` — iOS Skip button captures `actionMenuReminder = viewModel.store.visibleReminders.first` (**order assumption**: menu targets the first reminder).
- `ContentView+ActionMenu.swift:66` — iOS `actionMenuRescheduleReminder`: `actionMenuReminder ?? viewModel.store.visibleReminders.first` (fallback to first).
- `ContentView+ActionMenu.swift:93` — macOS `macShowActionMenu` gate (presence).
- `ContentView+ActionMenu.swift:168` — macOS `actionMenuRescheduleReminder`: `viewModel.store.visibleReminders.first` directly (no capture on macOS).
- `ContentView+ActionMenu.swift:181` — reschedule `onReschedule` closure re-derives the target: `let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier` (**order assumption**).
- `ContentView+iOS.swift:87` — `nudgedReminder`: `viewModel.store.visibleReminders.first { $0.calendarItemIdentifier == identifier }` — `first(where:)`, **order-independent** lookup by identifier.

## 4. watchOS app (`SingleThreadWatch/`)

- `WatchReminderView.swift:84` — `canShowActionMenu` gate `... && viewModel.store.visibleReminders.first != nil` (presence).
- `WatchReminderView.swift:95-111` — `.reminder` branch of `switch viewModel.store.listContent` (line 95); renders `if let reminder = viewModel.store.visibleReminders.first` at :107 (**order assumption**: the single-card UI shows the first sorted reminder, `reminderCard` at :242).
- `WatchReminderView.swift:309` — reschedule confirm: `if let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier` (**order assumption**).
- `WatchReminderViewModel.swift:98` — completion ghost-card snapshot: `transitionReminder = store.visibleReminders.first` before `completeCurrentReminder()` (**order assumption**; displayed only, never written back).
- Sort option arrival on watch: `WatchAppViewModel.swift:31` (`store.sortOption = SortOptionStore().load()` on launch) and :212-213 (`onSortOptionReceived` → `store.setSortOption(option)`), pushed over WatchConnectivity by `SkippedReminderSyncService.swift:207-208, 410-413` and the iPhone's `onSortOptionChanged` hook (`AppViewModel.swift:402-404`).

## 5. Widget (`SingleThreadWidget/` + Core intents)

- `NextThingWidget.swift:71-75` — timeline `makeEntry()`: `store.setSortOption(SortOptionStore().load())`, `await store.reload()`, `state: store.listContent`. The widget never reads `visibleReminders` directly; it consumes `ListContent`, whose `.reminder` payload is built from `visibleReminders.first` in Core (`ReminderStore.swift:167-168`) — **order assumption is inherited**.
- `NextThingWidget.swift:149,158` — Complete/Skip buttons fire `CompleteReminderIntent` / `SkipReminderIntent`.
- `ReminderIntents.swift:15-24` — `CompleteReminderIntent.perform()`: `store.setSortOption(...)`, `store.reload()`, `await store.completeCurrentReminder()` → first-element assumption via `ReminderStore.swift:260-262`.
- `ReminderIntents.swift:37-52` — `SkipReminderIntent.perform()`: `store.setSortOption(...)`, `store.reload()`, `store.skipCurrentReminderImmediately()` → first-element assumption via `ReminderStore.swift:421-423`.

## 6. Where ordering beyond the first element is assumed

- **No consumer reads index ≥ 1**, slices, `min`/`max`, or `last` of `visibleReminders` in production source. Grep found only `.first`, `.isEmpty`/`!= nil`, and `.count` (`AppViewModel.swift:84`). The UI on every surface is single-card/top-of-order.
- **All first-element uses** assume sort order determines "the current reminder": rendering (iOS :413, watch :107, widget via `listContent` :167), complete (:261), delete (:316), skip (:382, :423), watch transition snapshot (:98), reschedule targets (:181, :309), and action-menu capture/fallback (:33, :66, :168).
- `first(where:)` lookups (`ContentView+iOS.swift:87` nudge; `ReminderStore.swift:288/314/323` component lookups by identifier) are order-independent.

## 7. Independent re-sort or re-order

- **None in production.** The only production comparator call site is `ReminderStore.swift:151`; the only other `.sorted()` is the calendar-title sort at :484. `reload()` stores fetched (unsorted) order; `allSkipped`/`listContent`/all mutation methods defer to the computed property. Watch restores the same shared `SortOption` (:31), widget and intents load it from `SortOptionStore` (`NextThingWidget.swift:71`, `ReminderIntents.swift:20,43`) — all surfaces sort through the single `visibleReminders` path with the same comparator and option.

## 8. Sort-option plumbing (producer side)

- `SortOption.defaultsKey = "sortOption"` (`SortOption.swift:18`); persisted via `SortOptionStore` (`SortOption.swift:22-44`, App Group defaults). Set at launch by iOS `AppViewModel.swift:25`, watch `WatchAppViewModel.swift:31`, widget `NextThingWidget.swift:71`, intents `ReminderIntents.swift:20,43`. Settings picker (`FilterSortSettingsView.swift:10-21`) and `@AppStorage` binding (`ContentView.swift:118-119, 274-275` → `ContentViewModel.handleSortOption` :126-127 → `store.setSortOption` :407-411).