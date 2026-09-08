# Agent Q4 — Preference persistence and sync

## 1. Storage substrate: App Group defaults

- `AppGroup.suiteName = "group.app.alanvardy.SingleThread"` — `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:11`
- `AppGroup.defaults` is `UserDefaults(suiteName: suiteName) ?? .standard` — `AppGroup.swift:16-18`. Doc comment (:13-15): the `.standard` fallback exists for "watchOS, unregistered simulators, and previews"; the widget and iOS app hold the real App Group entitlement.
- Store types all default to this container:
  - `SortOptionStore.init(defaults: UserDefaults = AppGroup.defaults, key: String = SortOption.defaultsKey)` — `SortOption.swift:25`
  - `BoolPreferenceStore.init(defaults: UserDefaults = AppGroup.defaults, key: String, fallback: Bool)` — `BoolPreferenceStore.swift:14-26`
  - `ExcludedListStore.init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedListTitles")` — `ExcludedListStore.swift:7`

## 2. The sort preference: value type + store

- `SortOption` is a `String` raw-value enum: cases `.priority`, `.dueDate`, `.title` — `SortOption.swift:6-12`; `defaultsKey = "sortOption"` — `SortOption.swift:18`.
- `SortOptionStore.load()`: `defaults.string(forKey: key)`, falls back to `.priority` on missing **or** unrecognized raw value — `SortOption.swift:34-39`; `save(_:)` writes `option.rawValue` — `SortOption.swift:41-43`.
- `ReminderStore.sortOption` is a plain stored property (`ReminderStore.swift:76-77`); applied in `visibleReminders` via `ReminderSort.areInIncreasingOrder($0, $1, using: sortOption)` — `ReminderStore.swift:151`. Direct assignment (launch restore) does **not** fire hooks; `setSortOption` is the hook-firing path (`ReminderStore.swift:407-412`): guards `option != sortOption`, calls `onSortOptionChanged?(option)` and `onRemindersChanged?()`.

## 3. iOS app

**Launch restore** — `SingleThreadApp.init` builds `AppViewModel()` (`SingleThreadApp.swift:13-15`). In `AppViewModel.init`:
- `store.sortOption = SortOptionStore().load()` — `AppViewModel.swift:25` (direct assignment; reads App Group key `sortOption`).
- `Self.registerDefaults()` — `AppViewModel.swift:26` (defined `AppViewModel.swift:164-174`; registers `showMicrophoneButton` default, runs one-time `enableActionButtons` `.standard` → App Group migration, :168-173).
- iOS: `setupSyncService(with: store)` — `AppViewModel.swift:29-30` (impl `:340-409`); widget-timeline hook `store.onRemindersChanged = { WidgetCenter.shared.reloadAllTimelines() }` — `:31-34`.

**Settings write path** — `makeSettingsBag()` (`ContentView.swift:196-202`) → `sortOption` bound to `FilterSortSettingsView` picker (`SettingsView.swift:92-95` → `FilterSortSettingsView.swift:18-29`). `.onChange(of: bag.sortOption)` write-back (`ContentView+Settings.swift:38`) writes to ContentView `@AppStorage`:

```swift
@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)
var sortOption = SortOption.priority   // ContentView.swift:118-120
```

That `@AppStorage` mutation (App Group write) is observed by `ContentView.onChange(of: sortOption)` (`ContentView.swift:274-276`) → `ContentViewModel.handleSortOption` (`ContentViewModel.swift:126-128`) → `store.setSortOption(option)` (`ReminderStore.swift:407-412`), which fires the sync hook wired in `AppViewModel.setupSyncService`:

```swift
store.onSortOptionChanged = { option in
    SortOptionStore().save(option)
    service.pushAll()
}
```
— `AppViewModel.swift:402-407`

So the persisted key `sortOption` is written by the `@AppStorage` write-back **and** redundantly by `SortOptionStore().save()` in the hook.

**Sync push for sibling preferences** — same `setupSyncService` wires `store.onSkipSetChanged`, `store.onShowUndatedRemindersChanged`, `store.onExcludedListsChanged` all to `service.pushAll()` — `AppViewModel.swift:391-393`. A NotificationCenter observer on `UserDefaults.didChangeNotification` for `AppGroup.defaults` (`AppViewModel.swift:449-459`) → `handlePreferencesChanged()` (`:464-484`) diffs last-seen vs current for showDate/showRecurrence/showAlarms/showList/showCompletionGlow/`enableActionButtons` (`:466-483`) and calls `pushAll()` on change (last-seen at `:486-505`). `sortOption` is **not** in that diff — it has the explicit `onSortOptionChanged` path.

## 4. iPhone ↔ watch sync: SkippedReminderSyncService

Compiled only for `#if os(iOS) || os(watchOS)` (`SkippedReminderSyncService.swift:4`). Uses `updateApplicationContext` (latest-wins, auto-delivered on reconnect) — `:21`, `:237`.

- **Push** (`pushAll()` at `:200-243`): one combined context always containing `skippedReminderIdentifiers`, `skipCounts`, `excludedListTitles`, `showUndatedReminders`, `sortOption: sortStore.load().rawValue`, `completionCount`, `enableActionButtons` (read raw from `AppGroup.defaults.bool(forKey:)`) — `:204-209`; gated showDate/showRecurrence/showAlarms/showList/showCompletionGlow/entitled follow (:211-234). Payload key constants: `:344-362`.
- **Receive** — `WCSessionDelegate.session(_:didReceiveApplicationContext:)` → `apply(context:)` (`:294-298`, `:386-445`). For each present key: persists via the local store first, then fires the hook. Sort: `sortStore.save(option)` then `onSortOptionReceived?(option)` — `:410-414`. show-* bools: `:417-441`. `applyRemaining` (`:447-463`): `enableActionButtons` → `AppGroup.defaults.set(...)` then `onEnableActionButtonsReceived` (`:448-451`), plus skipCounts/entitled/completionCount. Absent keys are explicit no-ops.
- Service `init` defaults (`:26-60`): all store params default to App Group-backed stores; on the watch these resolve to `.standard` via the fallback.

## 5. watchOS app

**Launch restore** — `WatchAppViewModel.init`:
- `store.sortOption = SortOptionStore().load()` — `WatchAppViewModel.swift:31`; comment (:28-30) "Restore the last-received sort (persisted to .standard on receive)". No App Group entitlement on watch → `.standard`.
- `store.showsUndatedReminders = BoolPreferenceStore(defaults: .standard, key: showUndatedReminders, fallback: false).isEnabled` — `:33-36` (the didSet hook `onShowUndatedRemindersChanged` is unwired on the watch, comment :32-33).
- Each `Show*State` seeds itself from a `.standard`-backed `BoolPreferenceStore` in `init()` — e.g. `ShowListState.swift:16-30` (`preference.isEnabled`), `ShowEnableActionButtonsState.swift:16-23`.

**Receive wiring** — `setupSyncService` (`WatchAppViewModel.swift:74-233`): watch builds the service with `.standard`-backed stores for show-* bools and `CompletionCounterStore(defaults: .standard)` and disables pushes of show-*/entitled (`sendsShowDate/…/sendsEntitled = false`, watch never pushes those — `:130-146`). Then:
- `service.onShowUndatedRemindersReceived` → `store.showsUndatedReminders = value; await store?.reload()` — `:194-198`
- `service.onSortOptionReceived` → `store?.setSortOption(option)` — `:212-215`
- `service.onExcludedListTitlesReceived` → `store?.refreshExcludedListTitles(Set(titles))` — `:224-226` (comment :229-230 "Exclusions sync phone→watch only")
- `wireStateReceiveHooks` maps each `onShowXReceived`/`onEntitlementReceived`/`onEnableActionButtonsReceived` to the corresponding `Show*State.apply(...)` on MainActor — `:249-273`
- `service.activate()` — `:227`; the only watch push hook is `store.onSkipSetChanged = { _ in service.pushAll() }` — `:228`.

## 6. Widget (and intents)

- `NextThingProvider.makeEntry` re-reads preferences on every timeline: showDate/showList/showRecurrence/showAlarms via `BoolPreferenceStore` (App Group suite) — `NextThingWidget.swift:57-63`; then for `.fullAccess` builds `ReminderStore(loadsReminders: true)`, restores `store.showsUndatedReminders` (`:68-69`) and `store.setSortOption(SortOptionStore().load())` (`:71`) before `reload()` (`:72`). Widget holds the real App Group entitlement, so these reads see the phone's writes.
- `CompleteReminderIntent.perform` (`ReminderIntents.swift:18-21`) and `SkipReminderIntent.perform` (`ReminderIntents.swift:41-44`) each do `store.setSortOption(SortOptionStore().load())` + `reload()` before mutating.

## 7. Preference inventory (user-selectable, same pattern)

All declared in `ContentView` as `@AppStorage(_, store: AppGroup.defaults)`, synced phone→watch in the combined `applicationContext`, received/persisted in `apply`, surfaced on watch through `Show*State` seeded from `.standard`:

| Preference | iOS `@AppStorage` | Sync payload / receive | Watch storage + receive hook |
|---|---|---|---|
| `sortOption` | `ContentView.swift:118-120` | `SkippedReminderSyncService.swift:207` (push), `:410-414` (receive) | `WatchAppViewModel.swift:31`, `:212-215` |
| `showDate` | `ContentView.swift:121-123` | `:211-212` (gated), `:417-419` | `ShowDateState` via `WatchAppViewModel.swift:249-251` |
| `showList` | `ContentView.swift:124-126` | default `sendsShowList: true`, `:221-222`, `:429-433` | `ShowListState.swift:16-30`, hook `:258-260` |
| `showRecurrence` / `showAlarms` | `:127-128` / `:129-131` | `:214-217`/`:218-220`, `:421-423`/`:425-427` | `ShowRecurrenceState`/`ShowAlarmsState` via `:253-256` |
| `showCompletionGlow` | `:132-134` | `:225-226`, `:437-440` | `ShowCompletionGlowState` via `:264-266` |
| `showUndatedReminders` | `:115-117` | `:206` unconditional, `:406-408`; store relay `showsUndatedReminders.didSet` → `onShowUndatedRemindersChanged` (`ReminderStore.swift:121-126`) | `.standard` restore `WatchAppViewModel.swift:33-36`, hook `:194-198` |
| `enableActionButtons` | `:96-98` (iOS-only) | `:209` (raw App Group read), `:448-451` (`AppGroup.defaults.set`) | `ShowEnableActionButtonsState.swift:16-29`, hook `:269-271`; `.standard`→App Group migration `AppViewModel.swift:168-173` |
| `excludedListTitles` | store-backed, not `@AppStorage` (`ExcludedListStore.swift:7`); settings UI via `excludedListsBinding` (`ContentView.swift:219-228`) | `:207`, receive `:401-404`; re-read from `excludeStore.load()` on every `reload` (`ReminderStore.swift:679`) | hook `WatchAppViewModel.swift:224-226`; iOS store hook `onExcludedListsChanged` → pushAll (`AppViewModel.swift:393`) |

Non-preference payloads in the same combined context: `skippedReminderIdentifiers`, `skipCounts`, `completionCount`, `entitled` (`SkippedReminderSyncService.swift:204-234`, `:394-399`, `:452-460`). Watch→phone traffic: skips (watch's `onSkipSetChanged` → `pushAll`, `WatchAppViewModel.swift:228`) and interactive `sendMessage` relays for complete/delete/reschedule (`SkippedReminderSyncService.swift:270-292`, `:300-320`). macOS shares the same Core stores and `AppViewModel` launch restore (`AppViewModel.swift:25` unconditional; WCSession/`setupSyncService` iOS-gated at `:29`).