# Research Findings

## Q1: Full flow of an excluded title on iOS (settings toggle → ReminderStore → ExcludedProjectStore → visibleReminders)

### Findings
- **Settings UI**: `ExcludedProjectsView` (`SingleThread/SettingsView.swift:12`) holds `@Binding private var excludedProjects: Set<String>` (`SettingsView.swift:39`) and `private let availableProjects: [String]` (:41). Rows are `Toggle(isOn: excludedBinding(for:))` over `ForEach(availableProjects, id: \.self)` (:26-31); `excludedBinding(for:)` (:43-53) get = `contains`, set = `insert`/`remove`.
- Pushed via `NavigationLink { ExcludedProjectsView(...) } Label("Excluded Projects", systemImage: "eye.slash")` (`SettingsView.swift:178-185`). iOS `SettingsView.init` takes `excludedProjects: Binding<Set<String>>` (`SettingsView.swift:74-96`, stored :91).
- **Binding bridge**: `ContentView.excludedProjectsBinding` — get `{ store.excludedProjectTitles }`, set `{ store.setExcludedProjectTitles($0) }` (`SingleThread/ContentView.swift:233-238`), passed to `SettingsView` at :142.
- **Store mutation**: `ReminderStore` is `@MainActor @Observable public final class` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:6-8`). State: `public private(set) var excludedProjectTitles: Set<String> = []` (:49). Persistence dep: `private let excludeStore: ExcludedProjectStore` (:357), injected with default `ExcludedProjectStore()` (:16).
  - `setExcludedProjectTitles(_ titles: Set<String>)` (:310-318): assigns in-memory set → `excludeStore.save(array)` → fires `onExcludedProjectsChanged?(array)` then `onRemindersChanged?()`.
  - `refreshExcludedProjectTitles(_ titles: Set<String>)` (:320-327): receive-only variant; assigns and fires only `onRemindersChanged?()`, never `onExcludedProjectsChanged` (prevents echo over sync).
- **Persistence**: `public struct ExcludedProjectStore` (`SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift:4`). `init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedProjectTitles")` (:7). `load()` = `stringArray(forKey:) ?? []` (:13-15); `save(_:)` = `defaults.set(titles, forKey: key)` (:17-19). Defaults suite: `"group.app.alanvardy.SingleThread"` (`AppGroup.swift:10`), fallback `.standard` (:13-15).
- **Filtering**: `visibleReminders` filters skipped IDs then `!excludedProjectTitles.contains($0.calendar?.title ?? "")` (`ReminderStore.swift:107-113`, exclusion at :110). Reads only in-memory state, never `ExcludedProjectStore` directly. Reload path: `reload(clearSkipped:)` sets `excludedProjectTitles = Set(excludeStore.load())` (:301).
- **Callbacks wired** in `SingleThread/SingleThreadApp.swift`: `onExcludedProjectsChanged → service.pushExcludedProjectTitles(titles)` (:59); `onRemindersChanged → WidgetCenter.shared.reloadAllTimelines()` (:67-68); `service.onExcludedProjectTitlesReceived → store?.refreshExcludedProjectTitles(...)` (:54-56); seed path calls `store.setExcludedProjectTitles(seed.excludedProjectTitles)` (:122-123).

## Q2: WatchConnectivity sync of excluded titles

### Findings
- Transport: `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:23`, `#if os(iOS) || os(watchOS)` :4) wraps `WCSession` via the `SkipSyncSession` seam (:8-17). Pushes use `updateApplicationContext`; interactive complete/delete use `sendMessage`.
- **Payload keys** — private enum `PayloadKey` (:234-242): `"skippedReminderIdentifiers"` (:235), `"excludedProjectTitles"` (:236), `"completeReminderIdentifier"`/`"deleteReminderIdentifier"` (:237-238), `"showUndatedReminders"`, `"sortOption"`, `"showDate"` (:239-241). Doc says keys are shared sender/receiver so wire protocol cannot drift.
- **Push paths**: combined skip push writes skips + showUndated + sortOption (+ showDate when `sendsShowDate`) (:90-99). `pushExcludedProjectTitles(_:)` (:107-115) sends a **single-key context** `[excludedProjectTitles: titles]` (:109) — it replaces the whole application context without carrying the skip set. By contrast `pushSortOption` (:118-128) and `pushShowDate` (:134-144) re-carry `skippedReminderIdentifiers` (:122, :137).
- **Receive path**: `session(_:didReceiveApplicationContext:)` (:168-202) — each key independently `if let … as?` guarded. Exclusions: `excludeStore.save(receivedTitles)` (:183) then `onExcludedProjectTitlesReceived?(receivedTitles)` (:184-186; hook declared `nonisolated(unsafe)` :78). Absent keys are documented no-ops (:171-177 comment).
- **Application per side**:
  - iPhone: `SingleThreadApp.swift:45-47` receive hook → `refreshExcludedProjectTitles(Set(titles))`; :56 push hook.
  - Watch: `SingleThreadWatchApp.swift:41-43` identical receive hook; push wiring at :48. Watch service built with `sendsShowDate: false` (:23-27); its `excludeStore` defaults through `AppGroup.defaults` → `.standard` on watchOS.
  - Both assign hooks before `activate()` (write-once-before-activate invariant, service :47-55).
- **Asymmetries observed**:
  1. Direction: watch app has no caller of `setExcludedProjectTitles` anywhere in `SingleThreadWatch/` — exclusions flow phone→watch only; the watch's push wiring (:48) is unreachable from watch UI.
  2. Context replacement: exclusions-only push clobbers other context keys in the *stored* context (receive side is per-key gated so in-memory state survives).
  3. Persistence split on receive: the service's own `excludeStore.save` persists received titles (:183); `refreshExcludedProjectTitles` does not persist — a second `ExcludedProjectStore` instance converging on the same defaults/key.

## Q3: User-facing "project(s)" text across targets

### Findings
- iOS literal strings: `Label("Excluded Projects", systemImage: "eye.slash")` (`SettingsView.swift:183`); `.navigationTitle("Excluded Projects")` (:34); footer `Text("Excluded projects are hidden from the reminder list.")` (:31).
- Dynamic row labels: each toggle shows the raw calendar/project title (`SettingsView.swift:25-28`).
- No `.accessibilityIdentifier` exists anywhere in any target; no accessibility label contains "project".
- Preview fixtures: `mockReminderInProject` calendar titled `"Groceries"` (`ContentView.swift:572-580`); `#Preview("All Excluded")` passes `excludedProjectTitles: ["Groceries"]` (:610-620); three `ExcludedProjectsView` previews pass `["Work", "Personal"]` (`SettingsView.swift:240-241, 257-258, 272-273`).
- UI tests: watch test `testExcludedProjectDoesNotRenderReminder` uses launch args `["--ui-testing", "--ui-testing-excluded", "Work"]` (`SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift:25-27`). Consumed by `SingleThreadWatchApp.swift:74-89` (sets `calendar.title = project`, seeds exclusions). iOS UI tests contain no project-related launch args or queries.
- Widget target has zero occurrences of "project". Unit snapshot check asserts body contains `"Excluded Projects"` (`SingleThreadTests/SettingsViewTests.swift:55`).
- Internal symbols using "project": `excludedProjectTitles`, `availableProjects`, `setExcludedProjectTitles`, `refreshExcludedProjectTitles`, `onExcludedProjectsChanged`, `ExcludedProjectStore`, `ExcludedProjectsView`, `excludedProjectsBinding`, seed JSON key `"excludedProjects"`.

## Q4: Compatibility constraints around persisted/exchanged keys

### Findings
- **App Group UserDefaults key**: `"excludedProjectTitles"` (`ExcludedProjectStore.swift:7`) under suite `"group.app.alanvardy.SingleThread"` (`AppGroup.swift:10`). Related keys sharing the pattern: `"skippedReminderIdentifiers"` (`ReminderSkip.swift:114`), `"sortOption"` (`SortOption.swift:18`), `"showDate"` (`ShowDatePreference.swift:11`), raw literal `"showUndatedReminders"` read by widget (`NextThingWidget.swift:59`).
- **WC payload keys**: identical strings via `PayloadKey` (`SkippedReminderSyncService.swift:234-242`). Both targets compile the same enum from the SingleThreadCore package, so source-level drift is prevented; binary-level compatibility depends on updating both ends together.
- **UI-test seed JSON keys**: schema doc at `UITestingSeed.swift:8-16` — `"reminders"` (required), `"calendars"` (optional), `"excludedProjects"` (optional, `decodeIfPresent … ?? []` :78; CodingKeys synthesized from property names :86-92). Materialization maps `Set(excludedProjects)` → `seed.excludedProjectTitles` (:93-115, :114). Applied in `SingleThreadApp.swift:113-128`.
- **Legacy key facts**: the string `"excludedProjects"` exists ONLY as the seed-JSON key and as binding parameter names — never as a UserDefaults key. The persisted key has always been `"excludedProjectTitles"`. **No migration or fallback handling exists for any key**: every load is a direct typed read with a default fallback (`[]` / `false` / `.priority` / `true`); renamed keys silently yield defaults.
- **What breaks on rename**:
  - Installed iOS app's App Group plist and paired watch's `.standard` plist hold live exclusions under the literal key → orphaned (silently reset to empty on next `load()`/`reload()` at `ReminderStore.swift:301`).
  - Paired watches cache the last `applicationContext`; the OS re-delivers it on session activation. A receiver on an older/newer binary silently ignores mismatched keys — no protocol-version field or handshake exists.
  - `UITestingSeed.persistedKeys` reset list contains raw literals including `"excludedProjectTitles"` (`UITestingSeed.swift:51-62`) and must be updated in lockstep or seeded UI-test relaunches leak state. Widget literal (`NextThingWidget.swift:59`) is another independent copy.
- Unit tests pin literal strings: `SkippedReminderSyncServiceTests.swift:58, 319` assert raw dictionaries keyed `"skippedReminderIdentifiers"`/`"excludedProjectTitles"`; `SortOptionTests.swift:21` pins `"sortOption"`.

## Q5: EventKit modeling and existing "list" terminology

### Findings
- Reminder groupings are modeled exclusively as `EKCalendar` attached to `EKReminder.calendar`. Only production enumeration: `eventStore.calendars(for: .reminder).map(\.title).filter { !$0.isEmpty }` sorted into `availableProjects` (`ReminderStore.swift:288-291`; property declared :55-56 with doc "All reminder-list titles (sorted, deduplicated) the settings UI presents.").
- Only EKCalendar attribute touched is `.title`. **No use of `calendarIdentifier`/`EKCalendar.identifier` anywhere** (zero grep hits). All identifiers used are `EKReminder.calendarItemIdentifier` (e.g. `ReminderStore.swift:109,118-119`).
- Abstraction seam: `EventKitStoring` protocol (`EventKitStoring.swift:12,19`), conformed by `EKEventStore` (:36); fake is `InMemoryEventStore` (`InMemoryEventStore.swift:37,110` — returns seeded calendars; assigns `reminder.calendar = calendars.first` :105).
- Calendar construction sites: `SingleThreadWatchApp.swift:81-82`, `UITestingSeed.swift:96-98`, preview mock `ContentView.swift:574-575`, test fixtures `EventKitStoringTests.swift:456-458`, `ReminderStoreTests.swift:526-527`, `SkippedReminderSyncServiceTests.swift:481-482`.
- **Existing "list" terminology**: essentially absent as a symbol name — no `lists`/`reminderLists`/`availableLists` symbol exists. Prose occurrences: doc comment "All reminder-list titles…" (`ReminderStore.swift:55`) is the only place "list" describes what `calendars(for: .reminder)` yields; user string "…hidden from the reminder list." (`SettingsView.swift:31`) means the on-screen reminder list. Other hits are skip-list machinery (`ReminderSkip.swift:3-17`), SwiftUI `List` usage (`ContentView.swift:340+`), the `reminderList` scroll-view variable (`ContentView.swift:52`), and unrelated strings ("shopping-list", "checklist").

## Q6: Test coverage for the exclusion feature

### Findings
- **Unit persistence** — `SingleThreadTests/ExcludedProjectStoreTests.swift`: `loadReturnsEmptyByDefault()` :7, `saveRoundTripsTitles()` :13, `saveReplacesExistingTitles()` :20, `saveEmptyClearsTitles()` :28, `storesAreIsolatedByKey()` :36.
- **Unit store/filtering/hooks** — `SingleThreadTests/ReminderStoreTests.swift` (`@Suite(.serialized) @MainActor`): `visibleRemindersFiltersOutExcludedProjectTitles()` :75, `visibleRemindersKeepsNilCalendarReminders()` :88, `visibleRemindersEmptyWhenAllProjectsExcluded()` :100, `setExcludedProjectTitlesPersistsAndFiresHooks()` :126, `refreshExcludedProjectTitlesUpdatesSetAndFiresRemindersChangedOnly()` :146. Fixtures: `makeReminder(title:priority:dateComponents:)` :515, overload `makeReminder(title:calendarTitle:)` :523 (attaches titled `EKCalendar`).
- **Unit sync** — `SingleThreadTests/SkippedReminderSyncServiceTests.swift` (section MARK :307): `pushExcludedProjectTitlesUpdatesApplicationContext()` :310, `receiveContextReplacesLocalExcludedTitles()` :324, `receiveContextMissingExcludedTitleKeyIsNoOp()` :339, `receivedExclusionRefreshFiltersVisibleReminders()` :355 (end-to-end service → refresh → filtered `visibleReminders`). Fake: `FakeSession: SkipSyncSession` :9; helper `inProjectReminder(title:project:)` :477.
- **Unit seed decoding** — `SingleThreadTests/UITestingSeedTests.swift`: `parsesCalendarsAndExcludedProjects()` :27 decodes `{"excludedProjects":["Work"]}`; related `parsesRemindersFromCompactJSON()` :12, `returnsNilWhenSeedAbsentOrMalformed()` :39, `resetPersistedStateClearsBackgroundEnabled()` :63.
- **Unit settings view** — `SettingsViewTests.swift`: `settingsViewContainsAllPreferenceRows()` :11 asserts body contains `"Excluded Projects"` :55, passing `excludedProjects: .constant([])` (:23, :36).
- **watchOS UI** — `SingleThreadWatchUITestsFlows.testExcludedProjectDoesNotRenderReminder()` :25 launches with `["--ui-testing", "--ui-testing-excluded", "Work"]`; helper `launchApp()` :70.
- **iOS UI**: no test exercises exclusions. `launchApp(seedJSON:)` helper exists (`SingleThreadUITestsFlows.swift:21-23`) but no test passes `excludedProjects` in seed JSON; no iOS equivalent of `--ui-testing-excluded` exists in `SingleThreadApp.swift`.

## Cross-Cutting Observations
- Naming is consistently "project" across all layers (symbols, UserDefaults key, WC payload key, UI copy), while EventKit's native concept is a reminder calendar/list. The single "list"-as-calendar mention is the `availableProjects` doc comment (`ReminderStore.swift:55`).
- Two parallel `ExcludedProjectStore` instances exist per device (one owned by `ReminderStore`, one by the sync service) converging on the same App Group defaults + key; received values are persisted by the service but local edits by the store.
- Key strings appear in multiple independent places that must stay aligned manually: `ExcludedProjectStore` default param, `PayloadKey` constant, `UITestingSeed.persistedKeys` literal list, unit-test assertions pinning raw strings.
- Every persisted/payload load path fails silent-and-default (no migrations anywhere); WC context is whole-replacement with per-key gated reads.
- Filtering is entirely by `EKCalendar.title` string matching, never by identifier.

## Open Areas
- No code answers how a rename would be staged for already-installed devices — no migration infrastructure exists anywhere in the codebase to describe.
- The tolerant-decoding branch for an absent `"excludedProjects"` seed key (`UITestingSeed.swift:78`) has no direct unit assertion.
- Whether Apple Reminders list titles are unique (two lists with the same title cannot be distinguished by the current title-based filter) is not addressed in code.
