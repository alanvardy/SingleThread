# Research Findings

## Q1: Which `EKReminder` properties exist, which are read anywhere, and where?

### SDK surface (`EKReminder` inherits `EKCalendarItem`)
- `EKCalendarItem`: `calendarItemIdentifier`, `calendarItemExternalIdentifier`, `calendar`, `title`, `notes`, `url`, `location`, `alarms`, `hasAlarms`, `attachments`, `startDateComponents`, `endDateComponents`, `allDay`, `hasNotes`, `hasAttendees`, `hasRecurrenceRules`, `recurrenceRules`, `timeZone`, `organizer`
- `EKReminder` itself: `dueDateComponents`, `priority`, `isCompleted`, `completionDate`, `creationDate`, `lastModifiedDate`, `displayOrder`

### Properties READ in production code today
| Property | Read sites |
|---|---|
| `title` | `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:12`; `ReminderSort.swift:76`; `SingleThreadWatch/WatchReminderView.swift:172` |
| `notes` | `ReminderDisplay.swift:13`; `WatchReminderView.swift:180` |
| `priority` | `ReminderDisplay.swift:15`; `ReminderSort.swift:46-47`; `WatchReminderView.swift:166-167` |
| `dueDateComponents` | `ReminderDisplay.swift:14`; `ReminderSort.swift:61-62`; `ReminderStore.swift:281` (window filter); `WatchReminderView.swift:175` |
| `calendar?.title` (list membership) | `ReminderDisplay.swift:16`; `ReminderStore.swift:110` |
| `calendarItemIdentifier` | `ReminderStore.swift:109-111,118-119,143,146,160,170,173,186,221,246,298,364`; `SingleThread/ContentView.swift:365`; `InMemoryEventStore.swift:88` |
| `isCompleted` | Read as filter only: `InMemoryEventStore.swift:56`; written at `ReminderStore.swift:148` |

### Properties NOT read in production
- `recurrenceRules` / `hasRecurrenceRules` — only tests assert them (`SingleThreadTests/ReminderStoreTests.swift:482-497`, `EventKitStoringTests.swift:194`); they are **written** via `addRecurrenceRule` at `EventKitStoring.swift:60` and `InMemoryEventStore.swift:101`
- `url` — write-only in a mock fixture (`ContentView.swift:575`)
- `location`, `alarms`/`hasAlarms`, `attachments`, `completionDate`, `creationDate`, `lastModifiedDate`, `startDateComponents`/`endDateComponents`, `timeZone`, `organizer`, `calendarItemExternalIdentifier` — no production or test references found

## Q2: Data flow `EKReminder` → `ReminderDisplay` → the three rendering surfaces

### The mapping type — `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
- Exactly five fields: `title`, `notes: String?`, `dueDate: Date?`, `priorityMarker: String`, `listName: String?`
- `init(reminder: EKReminder)` (`:12-18`) maps: title / `ReminderNotesFormatter.format(notes)` / `dueDateComponents?.date` / `ReminderPriority.marker(for: priority)` / `calendar?.title`
- Second direct constructor `init(title:notes:dueDate:priorityMarker:listName:)` (`:22-34`) for previews/placeholders/tests

### Surface 1 — iOS `ReminderCardView`
- Constructed at `SingleThread/ContentView.swift:348-352` with `display: ReminderDisplay(reminder:)`, plus `showDate`, `showList`, `showsOverPhoto`
- Parameters declared `SingleThread/ReminderCardView.swift:15-23`; body usage `:27-70`: priorityMarker (colored via `ReminderPriority.level(forMarker:)`, `:30-35`), title `:38`, dueDate gated on `showDate` `:41-45`, listName gated on `showList` + non-empty `:47-50`, notes `:52-55`
- Never touches `EKReminder` directly

### Surface 2 — watchOS `WatchReminderView` (does NOT use `ReminderDisplay`)
- Zero `ReminderDisplay` references in `SingleThreadWatch/` (verified by grep)
- Receives `store: ReminderStore` + `showDateState: ShowDateState` (`WatchReminderView.swift:9-11`); renders `store.visibleReminders.first` (`:73`)
- Reads raw `EKReminder` fields inline (`reminderDetails`, `:164-181`): priority level/marker `:166-168`, title `:172`, `dueDateComponents?.date` gated by `showDateState.isEnabled` `:175`, formatted notes `:177`. **No list name is rendered on watch**
- Production construction: `SingleThreadWatch/SingleThreadWatchApp.swift:85`

### Surface 3 — widget `NextThingWidgetView`
- Timeline entry `NextThingEntry` carries `.reminder(ReminderDisplay)` state + top-level `showsDate`/`showsList` flags (`SingleThreadWidget/NextThingWidget.swift:8-20`)
- Real path `makeEntry` (`:80-82`): `ReminderDisplay(reminder: current)` from `store.visibleReminders.first`; placeholder/snapshot use direct constructor (`:31`, `:40`), preview uses full 5-arg constructor (`:222`)
- View receives only `entry: NextThingEntry` (`:114-116`); field usage in `reminderView` (`:156-186`): priorityMarker `:161-164` (plain text, no color), title `:166-168`, dueDate gated by `entry.showsDate` `:170-173`, listName gated by `entry.showsList` `:175-178`, notes `:180-183`
- Preference gates sourced at entry build time: `ShowDatePreference().isEnabled` `:58`, `ShowListPreference().isEnabled` `:59`

### Cross-surface note
The watch is the only surface that bypasses `ReminderDisplay` and re-applies formatters directly to `EKReminder`; iOS card and widget consume only the shared struct.

## Q3: Existing preference types end to end

All default to `AppGroup.defaults` (`UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` — `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8-13`); watchOS and tests explicitly pass `defaults: .standard`.

| Type | File | Key | Missing-key default | API |
|---|---|---|---|---|
| `ShowDatePreference` | `ShowDatePreference.swift` | `"showDate"` (`:11`) | `true` (`:17`) | `isEnabled` / `set(_:)` |
| `ShowListPreference` | `ShowListPreference.swift` | `"showList"` (`:9`) | `false` (`:16`) | `isEnabled` / `set(_:)` |
| `ShowUndatedRemindersPreference` | `ShowUndatedRemindersPreference.swift` | `"showUndatedReminders"` (`:11`) | `false` (`load() :16`) | `load()` / `save(_:)` |
| `SortOptionStore` | `SortOption.swift` | `"sortOption"` (`defaultsKey :18`) | `.priority` (`:22-30`) | `load()` / `save(_:)` |
| `ExcludedListStore` | `ExcludedListStore.swift` | `"excludedListTitles"` (`:7`) | `[]` (`:12-15`) | `load() -> [String]` / `save(_:)` |

### Where each is read per target
**iOS app**: prefs are written via `@AppStorage(..., store: AppGroup.defaults)` in `ContentView.swift:215-225` and `SingleThreadApp.swift:103-104`, not via the typed wrappers. `showDate` also observed in `SingleThreadApp.swift:81-85` → `syncService?.pushAll()`.
- `showDate` widget read: `NextThingWidget.swift:58`; sync push snapshot: `SkippedReminderSyncService.swift:111-113`
- `showList`: passed into `ReminderCardView` (`ContentView.swift:145-146,159-160`); widget read `NextThingWidget.swift:59`. No watchOS usage.
- `showUndatedReminders`: `ContentView.swift:111` sets `store.showsUndatedReminders`; onChange reload `:115-117`. Widget reads the key as a raw literal: `AppGroup.defaults.bool(forKey: "showUndatedReminders")` (`NextThingWidget.swift:63`) — bypasses the typed wrapper.
- `sortOption`: launch read `SingleThreadApp.swift:22`; write path `SingleThreadApp.swift:62` → push; widget `NextThingWidget.swift:64`; intents `ReminderIntents.swift:20,43`; watch read `SingleThreadWatchApp.swift:21`
- `excludedListTitles`: UI binding → `ReminderStore.setExcludedListTitles` (`ReminderStore.swift:312-317`) → `excludeStore.save`; store constructed with default `ExcludedListStore()` (`ReminderStore.swift:27-28`)

**watchOS**: `ShowDateState` wraps a `ShowDatePreference(defaults: .standard)` (`SingleThreadWatch/ShowDateState.swift:8,28`); `apply(_:)` persists + publishes (`:19-22`). Undated/sort/exclusions loaded at `SingleThreadWatchApp.swift:21,24`.

## Q4: iOS Settings screen organization and side effects

### `SingleThread/SettingsView.swift`
- Two views: `ExcludedListsView` (`:12-52`, Form of Toggles over `Binding<Set<String>>` via computed `excludedBinding(for:)` `:45-52`) and `SettingsView` (`:54-253`)
- `SettingsView` owns no state — all rows bind back to ContentView's `@AppStorage` values (comment `:58-60`). Rows: Appearance picker `:74-77`, Text Size `:78-81`, Sort By `:82-85`, Allow landscape (iOS) `:87-91`, Show microphone `:95-97`, Background `:98-101`, Background Fade `:102-105`, Show action buttons (iOS) `:107-110`, Show undated reminders `:112-114`, Show date `:115-117`, Show list `:119-121`, Excluded lists NavigationLink `:123-128`
- Side effects inside SettingsView: landscape toggle → `AppDelegate.applyLock` `:163-164`; show date toggle → `WidgetCenter.shared.reloadAllTimelines()` `:188-191`

### `@AppStorage` bindings — `SingleThread/ContentView.swift:190-225`
- `.standard` suite: `appearanceMode` `:190-191`, `textSize` `:193-194`, `allowsLandscape` `:197-198`, `showMicrophoneButton` `:201-202`, `backgroundEnabled` `:204-205`, `backgroundFadePercent` `:207-208`, `enableActionButtons` `:211-212`
- `AppGroup.defaults` suite: `showUndatedReminders` `:215-216`, sort option (key `SortOption.defaultsKey`) `:218-219`, `showDate` `:221-222`, `showList` `:224-225`
- `excludedLists` is not `@AppStorage` — computed `Binding<Set<String>>` forwarding to `store.excludedListTitles`/`setExcludedListTitles` (`:243-248`)

### Side effects on change
- ContentView root onChange handlers (`:100-127`): undated → set store property + `reload()`; sort → `store.setSortOption`; appearance → `AppDelegate.applyAppearance`
- `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `enableActionButtons`, `showList` have **no** onChange callbacks — pure render-time consumers
- `WidgetCenter.reloadAllTimelines()` call sites: exactly two — `SettingsView.swift:190` (showDate toggle) and `SingleThreadApp.swift:69` (`store.onRemindersChanged` hook)
- Store-layer triggers feeding widget reload: `setSortOption` (`ReminderStore.swift:230-235`), `setExcludedListTitles` (`:312-318`), `refreshExcludedListTitles` (`:324-327`), `showsUndatedReminders` didSet (`:100-105` → `onShowUndatedRemindersChanged` → `pushAll()` via `SingleThreadApp.swift:46`)

## Q5: WatchConnectivity preference propagation iPhone → Watch

### Shared service — `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- One file compiled into both targets (`#if os(iOS) || os(watchOS)`, `:17`)
- Payload keys (`PayloadKey`, `:181-191`): `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`, `sortOption`, `showDate`, plus command keys `completeReminderIdentifier` / `deleteReminderIdentifier`
- Push: `pushAll()` (`:104-120`) sends one combined latest-wins `updateApplicationContext`; `showDate` included only when `sendsShowDate == true`
- Receive: `didReceiveApplicationContext` (`:156-158`) → `apply` (`:151-181`): per-key `if let … as?` → persist into injected store → fire hook. Commands arrive via `didReceiveMessage` (`:160-172`)
- Activation: `activate()` (`:92-98`); hooks are nonisolated(unsafe), write-once-before-activate (doc `:34-55`)
- Per-preference hooks (identical shape): `onSkippedIdentifiersReceived`, `onExcludedListTitlesReceived`, `onSortOptionReceived`, `onShowUndatedRemindersReceived` (`:148-150`), `onShowDateReceived` (`:151-153`)

### Roles
- iOS sender wiring: `SingleThreadApp.swift:29-64` constructs service with `sendsShowDate: true`; store-change hooks and the `@AppStorage("showDate")` onChange (`:81-85`) both call `pushAll()`
- Watch wiring: `SingleThreadWatchApp.swift:27-56` with `sendsShowDate: false`; `onShowDateReceived` → `showDateState?.apply(value)` (`:45-47`), set before `activate()`
- `ShowDateState` (`SingleThreadWatch/ShowDateState.swift`): `@Observable` wrapper; init reads `preference.isEnabled` (`:12-14`); `apply` persists + publishes (`:19-22`); consumed at `WatchReminderView.swift:175` to gate the date row

### Steps a new synced preference flows through (observed pattern)
1. Typed store in `SingleThreadCore` with defaults key (Q3 table)
2. New `PayloadKey` case (`SkippedReminderSyncService.swift:181-191`)
3. Injected store property + include in `pushAll()` payload (`:104-120`)
4. Persist-on-receive branch + new `on…Received` hook in `apply` (`:151-181`)
5. iOS: hook fires `pushAll()` (e.g. `SingleThreadApp.swift:46,62-65,81-85`)
6. Watch: hook applies value before `activate()` (e.g. `SingleThreadWatchApp.swift:34-58`)

## Q6: How these areas are tested today

### Unit tests — Swift Testing everywhere (`import Testing`, `#expect`, `#require`); XCTest only in UI-test bundle
- **`ReminderDisplayTests`** (`SingleThreadTests/ReminderDisplayTests.swift`): field-by-field mapping assertions against a real `EKReminder` built by `makeReminder(title:)` factory (`:67-70`, real `EKEventStore()`); covers title `:7-10`, notes formatting `:12-22`, dueDate incl. nil `:24-45`, priority markers `:47-56`, calendar-title listName `:58-67`, direct constructor roundtrip `:74-84`. This is the canonical idiom for new mapped fields
- **`ShowDatePreferenceTests`** (`SingleThreadTests/ShowDatePreferenceTests.swift`): unique-key + `defer` cleanup against `UserDefaults.standard` (`:7-8`); missing-key default `:6-11`, set/get roundtrips `:13-24`. Canonical toggle-store pattern (same style: `ShowListPreferenceTests.swift:5-27`, `ExcludedListStoreTests.swift:8-38`)
- **`ShowDateTests`** (`SingleThreadTests/ShowDateTests.swift`): renders `ReminderCardView` via factory (`:47-55`) and asserts on `String(describing: body)` sentinels — date row presence via `"FormatStyleStorage"` `:15-18`, list row via calendar-title string `:20-36`. Pattern for card-level toggle rendering
- **`SettingsViewTests`** (`SingleThreadTests/SettingsViewTests.swift`): builds SettingsView with `.constant(...)` bindings for every row (`:12-35`, platform-gated `#if os(iOS)` `:63-65`) and asserts label strings present in body description (`:44-61`). Pattern for asserting a new settings row exists
- **`EventKitStoringTests`** (`SingleThreadTests/EventKitStoringTests.swift`): recording fake `FakeEventStore: EventKitStoring` (`:9-121`) with knobs (`authStatus`, `saveShouldThrow`, `returnedCalendars`) and call counters (`saved`, `fetchCallCount`, …); suites `@MainActor @Suite(.serialized)` covering write paths, lifecycle/reload counts (`fetchCallCount == 2` after save+reload), available-list dedup. Protocol seam defined at `SingleThreadCore/.../EventKitStoring.swift:8`
- **Seed seam**: `UITestingSeed.fromLaunchArguments` (`UITestingSeed.swift:18`) parses `--seed '<json>'`; app wiring `SingleThreadApp.swift:119-153` builds `InMemoryEventStore(reminders:calendars:)` (`InMemoryEventStore.swift` is the shipped in-memory `EventKitStoring`); parser unit-tested in `UITestingSeedTests.swift`; consumed by UI tests via `app.launchArguments = ["--seed", seedJSON]` (`SingleThreadUITests/SingleThreadUITestsFlows.swift:23`) and `["--ui-testing"]` (`SingleThreadUITests.swift:29`, `ActionButtonsUITests.swift:25`). New JSON seed fields extend the parser + `InMemoryEventStore.makeReminder` (`InMemoryEventStore.swift:97-103`)
- **`SingleThreadWatchTests/WatchSyncPipelineTests.swift`** (only file in that target): local `WatchFakeSession: SkipSyncSession` (`:20-41`, duplicated because fakes can't cross test bundles); push test asserts context contents incl. omission (`pushAllFromWatchOmitsShowDate :61-81`); receive test wires each `on…Received` closure and asserts store state + callback flags (`receiveAppliesEveryPresentKey :83-141`); absent-key no-op (`:143-180`); relaunch persistence via fresh store instance (`:182-192`). Pattern for any new synced key's push/receive coverage

## Cross-Cutting Observations
- **Two persistence tiers**: appearance/UI prefs live in `UserDefaults.standard`; reminder-content prefs (`showDate`, `showList`, `showUndatedReminders`, `sortOption`, `excludedListTitles`) live in `AppGroup.defaults` so the widget can read them (`ContentView.swift:61-67` comment)
- **Typed wrappers vs raw literals coexist**: iOS writes through `@AppStorage(key, store: AppGroup.defaults)` while the sync service and widget use the typed stores; `showUndatedReminders` is additionally read raw in the widget (`NextThingWidget.swift:63`)
- **Watch bypasses `ReminderDisplay`** — it re-implements the same formatting inline (`WatchReminderView.swift:164-181`) and renders no list name; iOS card and widget share the struct
- **Every synced pref follows one identical 6-step plumbing chain** (Q5) with identically-shaped `on…Received` hooks and identically-shaped test suites
- **Widget reload triggers**: only `showDate` toggle and `store.onRemindersChanged`; other display toggles (`showList`) need none because entries embed the flag at build time (`NextThingWidget.swift:58-65`)
- `EKReminder` Sendable retroactive conformance documented in `ReminderDateFilter.swift:1-16` — all reads must stay MainActor-isolated
- No snapshot-testing framework; view assertions use `String(describing: body)` sentinels; UI-test screenshots are `XCTAttachment(screenshot:)` artifacts only

## Open Areas
- `EKReminder.startDateComponents` semantics vs `dueDateComponents` for reminders was not verified against device behavior (SDK docs only)
- Whether macOS branch of `ContentView` (`:174-192` sheet) diverges further from iOS bindings was only lightly inspected
- Widget intent/config surface beyond `ReminderIntents.swift:20,43` (sort option) was not exhaustively mapped
