# Research Findings

Focus: the `SingleThread` iOS/macOS app target and the shared `SingleThreadCore`
local Swift package. All line references are from the current working tree.

## Q1: How is the display order of reminders computed today?

`ReminderSort.areInIncreasingOrder` lives in
`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift` (whole file = 36
lines). It is a `public nonisolated enum` with a single static comparator.

### Findings
- Comparator declaration: `ReminderSort.swift:7`
  `public static func areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool`.
- **Tier 1 — priority rank** (`ReminderSort.swift:8-19`):
  `ReminderPriority.rank(for:)` is called for both priorities (`:8-9`), then a
  `switch (lhsRank, rhsRank)` (`:10-18`) returns early when exactly one side has
  a rank (`:13-16`) or both have different ranks (`:11-12`, lower rank sorts first).
- **Tier 2 — due date** (`ReminderSort.swift:21-32`): compares
  `dueDateComponents?.date` (`:21-22`), soonest first (`:24-25`), dated before
  undated (`:26-29`).
- **Tier 3 — title tiebreak** (`ReminderSort.swift:34`):
  `localizedCaseInsensitiveCompare(...) == .orderedAscending`.
- `ReminderPriority.rank(for:)` (`ReminderSkip.swift:72-79`) delegates to
  `ReminderPriority.level(for:)` (`ReminderSkip.swift:50-57`), which maps the
  CalDAV values `1→high`, `5→medium`, `9→low`, anything else (incl. `0`)→`nil`
  (`:52-55`). `rank` maps high→`0`, medium→`1`, low→`2`, none→`nil`
  (`:74-77`). Doc comment states "lower sorts first… nil for no priority (sorts
  after all prioritized)" (`ReminderSkip.swift:70-71`).
- **Call sites of `areInIncreasingOrder`** (repo-wide grep; only two in source):
  - Production: `ReminderStore.visibleReminders` — `ReminderStore.swift:62`.
  - Test helper: `titles(of:)` — `SingleThreadTests/ReminderSkipTests.swift:298`.

Note: `ReminderSort.areInIncreasingOrder` is the *only* production sort; there is
no other ordering path.

## Q2: How does the ordered list become "the current reminder"?

`visibleReminders` is the single source of the current reminder.

### Findings
- `ReminderStore.visibleReminders` (`ReminderStore.swift:59-63`) is the
  `reminders` array filtered by `!skippedIDs.contains($0.calendarItemIdentifier)`
  (`:61`) then sorted by `ReminderSort.areInIncreasingOrder` (`:62`). The today/overdue
  date window is *not* applied here — it is applied earlier at EventKit fetch time
  (see Q5).
- **`.first` consumers (all read the already-sorted array):**
  - `ReminderStore.completeCurrentReminder()` — `ReminderStore.swift:101-104`
    (`visibleReminders.first` guard at `:102` → `completeReminder(identifier:)`).
  - `ReminderStore.skipCurrentReminder()` — `ReminderStore.swift:136-143`
    (guard at `:137`; async apply after settle sleep).
  - `ReminderStore.skipCurrentReminderImmediately()` — `ReminderStore.swift:152-157`
    (guard at `:153`; synchronous apply, added for the widget intent).
  - `ContentView.swift:230` — iOS/macOS current-reminder card
    `if let reminder = store.visibleReminders.first`.
  - `ContentView.swift:302` — `if store.visibleReminders.first != nil` (macOS action buttons).
  - `WatchReminderView.swift:66` — watch current-reminder card.
  - `NextThingWidget.swift:59` — widget `guard let current = store.visibleReminders.first`.
  - `ReminderIntents.swift` (in `SingleThreadCore`, **no** dedicated App Intents target):
    `CompleteReminderIntent.perform()` reloads then `store.completeCurrentReminder()`
    (`:18-21`); `SkipReminderIntent.perform()` reloads then
    `store.skipCurrentReminderImmediately()` (`:40-47`). Both resolve the current
    reminder indirectly via `.first`.
- Empty-state checks read the *size* not `.first`: `ContentView.swift:142`,
  `WatchReminderView.swift:57`.
- **Process boundaries** (from `SingleThread.xcodeproj/project.pbxproj`):
  - iOS/macOS app target `SingleThread` (`:195`, product-type application `:218`)
    runs `ContentView` + `ReminderStore` in-process.
  - Watch app `SingleThreadWatch` (`:267-289`) is a separate process.
  - Widget `SingleThreadWidget` (`:291-311`) is an app-extension (`.appex`),
    separate process.
  - `SingleThreadCore` is linked by all targets (`project.pbxproj:214,284,307`);
    each process instantiates its own `ReminderStore` and re-fetches EventKit
    independently. Only the skip list crosses processes (App Group UserDefaults).

## Q3: How are the existing settings preferences modeled and wired?

### Findings
- **`AppearanceMode`** — `SingleThread/AppearanceMode.swift:8`
  `enum AppearanceMode: String, CaseIterable`; cases `system/light/dark` (`:9-11`).
  Computed: `colorScheme: ColorScheme?` (`:16-22`, `.system→nil`), `systemImage: String`
  (`:25-31`), `title: String` (`:34-40`).
- **`TextSize`** — `SingleThread/TextSize.swift:8`
  `enum TextSize: String, CaseIterable`; cases `system/small/medium/large/extraLarge`
  (`:9-13`). Computed: `dynamicTypeSize: DynamicTypeSize?` (`:18-26`, `.system→nil`),
  `systemImage: String` (`:29-37`), `title: String` (`:40-48`). Doc comment notes it
  "follows the same `String, CaseIterable` pattern as `AppearanceMode`"
  (`TextSize.swift:5-7`).
- **`@AppStorage` keys on `ContentView`** (`SingleThread/ContentView.swift`):
  `"appearanceMode"` (`:115`, default `.system` `:116`), `"textSize"` (`:118-119`),
  `"allowsLandscape"` (`:122-123`, `#if os(iOS)`), `"showMicrophoneButton"`
  (`:126-127`). Keys are inline string literals; no `store:` argument (all target
  `UserDefaults.standard`).
- Effects applied in `ContentView.body`: `.preferredColorScheme(...)` (`:65`),
  `.modifier(TextSizeModifier(...))` (`:66`), `.sheet(...)` presenting `SettingsView` (`:67`).
- **Binding handoff** (`ContentView.swift:68-79`): iOS branch passes 4 bindings incl.
  `$allowsLandscape` (`:69-73`); `#else` branch passes 3 (`:75-78`).
- `TextSizeModifier` (`ContentView.swift:425-433`): applies
  `content.dynamicTypeSize(size)` when non-nil, else returns content.
- **`SettingsView` platform-conditional initializers** (`SingleThread/SettingsView.swift`):
  iOS 4-binding init (`:11-20`), non-iOS 3-binding init (`:22-29`). Stored `@Binding`
  properties at `:75-80`, `@Environment(\.dismiss)` `:81-82`.
- **Form rows** (`SettingsView.swift:34-71`): Appearance `Picker` (`:37-42`), Text Size
  `Picker` (`:43-48`), iOS-only Allow Landscape `Toggle` + `.onChange` →
  `AppDelegate.applyLock` (`:49-56`), Show Microphone `Toggle` (`:57-59`), Done
  toolbar button (`:61-67`). The view re-applies its own
  `.preferredColorScheme`/`TextSizeModifier` (`:69-70`).

## Q4: How and where are persisted preferences read outside SwiftUI bindings?

### Findings
- **`AppDelegate.applyLock(allowsLandscape:)`** (`SingleThread/AppDelegate.swift:17-29`,
  iOS-only) does **not** read UserDefaults — it receives the value as a parameter;
  caller is the toggle's `.onChange` (`SettingsView.swift:53-54`). It computes the mask
  (`:18-20`) and calls `setNeedsUpdateOfSupportedInterfaceOrientations()` +
  `requestGeometryUpdate` (`:25-28`).
- **`supportedInterfaceOrientationsFor`** (`AppDelegate.swift:31-39`) reads
  `UserDefaults.standard` directly: key `"allowsLandscape"` existence check (`:34`),
  `bool(forKey:)` with default `true` (`:35-37`), returns `.allButUpsideDown` or `.portrait`
  (`:38`). This is the only production read of a preference key as a raw string literal
  outside `@AppStorage`.
- The `"allowsLandscape"` string literal is duplicated: `ContentView.swift:122` vs
  `AppDelegate.swift:34,36`.
- **Skip-list persistence** lives in `SkippedReminderStore` (`ReminderSkip.swift:111-133`):
  init defaults `AppGroup.defaults` + key `"skippedReminderIdentifiers"` (`:114`),
  `load()` → `stringArray ?? []` (`:121-123`), `save(_:)` (`:125-127`).
- **`AppGroup.defaults`** (`AppGroup.swift:13-14`) = `UserDefaults(suiteName: suiteName) ?? .standard`,
  `suiteName = "group.app.alanvardy.SingleThread"` (`:8`). Falls back to `.standard`
  on watchOS / unregistered simulators / previews (doc `:10-12`).
- **Which suite each reader can access:**
  - iOS/macOS app: App Group entitlement declared (`SingleThread/AppGroup.entitlements:6-8`,
    `SingleThread/SingleThread.entitlements:6-8`; used per platform in `project.pbxproj:592-594,642-644`).
    Reads `@AppStorage` (`.standard`) AND the skip list (App Group).
  - Widget extension: entitlements set to `AppGroup.entitlements` (`project.pbxproj:844,872`),
    so `AppGroup.defaults` resolves to the shared suite — widget shares the skip list
    (via `NextThingWidget.swift:55,59` and `ReminderIntents.swift:41,47`).
  - Watch app: **no `CODE_SIGN_ENTITLEMENTS`** in its build configs
    (`project.pbxproj:787-833`), so `UserDefaults(suiteName:)` returns nil and
    `AppGroup.defaults` falls back to local `.standard` (`AppGroup.swift:14`).
    Cross-device skip sync is carried by `SkippedReminderSyncService`
    (`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:57-64,81-89`).

## Q5: How is the eligible reminder set determined before ordering?

### Findings
- **`reload(clearSkipped:)`** (`ReminderStore.swift:159-181`) builds the EventKit
  predicate at `:164-167`:
  `predicateForIncompleteReminders(withDueDateStarting: ReminderDateFilter.overdueCutoff(),
  ending: ReminderDateFilter.endOfToday(), calendars: nil)`. `calendars: nil` = all calendars.
- `ReminderDateFilter.endOfToday()` (`ReminderDateFilter.swift:28-36`): startOfToday +1 day
  −1 second (23:59:59 today); nil-fallback to startOfToday (`:32-34`).
- `ReminderDateFilter.overdueCutoff(days: 30)` (`ReminderDateFilter.swift:41-50`): startOfToday
  − 30 days; nil-fallback (`:46-48`). Excludes overdue-by-more-than-30-days reminders.
- Fetch bridges EventKit's completion handler via `fetchReminders(matching:)`
  (`ReminderStore.swift:232-238`); result assigned to `reminders` (`:169`).
  **Eligible set = incomplete reminders due in `(30 days ago 00:00, today 23:59:59]`.**
- **Skip-list resolution** (`ReminderStore.swift:174-179`, non-`clearSkipped` branch):
  `ReminderSkipLogic.resolve(fetched: fetched.map(\.calendarItemIdentifier), skipped: skipStore.load())`
  intersects persisted IDs with currently-fetched IDs, dropping stale ones; result
  becomes `skippedIDs` (`:178`). `ReminderSkipLogic.resolve` is pure logic
  (`ReminderSkip.swift:12-15`); `skipping(_:fetched:skipped:)` (`:19-24`) prunes after append.
- `clearSkipped` branch empties `skippedIDs`, `skipStore.save([])`, fires
  `onSkipSetChanged?([])` (`ReminderStore.swift:170-173`).
- Skip mutations outside reload route through `updatedSkipSet(afterSkipping:)`
  (`ReminderStore.swift:214-219`) → `ReminderSkipLogic.skipping`, then
  `applySkipSet(_:)` (`:222-227`) updates memory + persistence + hooks.
- **Composition in `visibleReminders`** (`ReminderStore.swift:59-63`): filter skipped IDs
  (`:61`) **then** sort (`:62`). Order of pipeline: fetch-predicate eligibility → skip-list
  resolution → visible filter → `ReminderSort`.

## Q6: How are ordering and settings behavior tested and previewed?

### Findings
- **`ReminderSortTests`** (`SingleThreadTests/ReminderSkipTests.swift:237-304`, Swift
  Testing `@Test` methods) exercises the comparator indirectly via `titles(of:)`:
  - `sortsHighPriorityBeforeLow` (`:241-245`), `sortsHighBeforeMediumBeforeLow` (`:248-253`),
    `sortsPrioritizedBeforeNoPriority` (`:256-260`), `sortsWithinSamePriorityByDate`
    (`:263-267`), `sortsDatedBeforeUndated` (`:270-274`), `breaksTiesAlphabetically` (`:277-281`).
  - Helpers: `makeReminder(title:priority:dateComponents:)` (`:285-295`, real
    `EKEventStore()`+`EKReminder(eventStore:)`), `titles(of:)` (`:297-299`, the direct
    `areInIncreasingOrder` call site), `date(_:)` (`:301-303`, `DateComponents(year:2024,month:1,day:)`).
  - Note: `rank(for:)` has no direct test; it is covered only through `ReminderSortTests`.
- `ReminderStoreTests` integration tests for `visibleReminders`:
  `visibleRemindersSortsByPriority`, `visibleRemindersSortsDatedBeforeUndated`
  (`SingleThreadTests/ReminderStoreTests.swift:45-72` per agent; grep-verified pattern).
- **`SettingsViewTests`** (`SingleThreadTests/SettingsViewTests.swift:7-36`): `@MainActor`
  struct, single `@Test` (`:10`); constructs `SettingsView` with `.constant` bindings
  using `#if os(iOS)` 4-arg vs 3-arg init (`:11-22`); asserts
  `let bodyDescription = String(describing: view.body)` (`:24`) contains
  "Appearance" (`:28`), "Text Size" (`:29`), "Microphone" (`:30`), "Done" (`:31`),
  and "Landscape" under `#if os(iOS)` (`:33`). Comment notes `Form` body content is
  reflected in the description unlike `.sheet` content (`:26-27`).
- **Enum-value tests:**
  - `AppearanceModeTests` (`SingleThreadTests/AppearanceModeTests.swift:6-32`): `colorScheme`
    mapping for system/light/dark (`:8-10, :13-15, :18-20`), `allCases == [.system,.light,.dark]`
    (`:23-25`), human-readable titles (`:28-32`).
  - `TextSizeTests` (`SingleThreadTests/TextSizeTests.swift:6-44`): `dynamicTypeSize` mapping
    for all five cases (`:8-30`), `allCases` covers five (`:33-35`), titles (`:38-44`).
  - `systemImage` properties of both enums have **no** test coverage.
- **Previews** (`SingleThread/SettingsView.swift:85-110`): iOS has
  `#Preview("Default")` (`:89-94`) and `#Preview("Dark + Extra Large")` (`:97-102`);
  non-iOS has a single `#Preview("Default")` (`:104-109`). **No preview exercises ordering
  or renders a sorted reminder list.**

## Cross-Cutting Observations
- **Single ordering path**: `ReminderSort.areInIncreasingOrder` has exactly one production
  call site — `ReminderStore.visibleReminders` (`ReminderStore.swift:62`). Every surface
  (app, watch, widget, intents) derives "current reminder" from `visibleReminders.first`,
  so the sort and the `.first` convention are the entirety of ordering today.
- **Settings pattern**: preferences are `String, CaseIterable` enums (`AppearanceMode`,
  `TextSize`) with `colorScheme`/`dynamicTypeSize`/`systemImage`/`title` computed props,
  persisted via `@AppStorage` string-literals on `ContentView`, passed as `Binding`s into
  a state-owning-`ContentView` / state-free-`SettingsView` split. `TextSize.swift:5-7`
  documents that `TextSize` deliberately mirrors `AppearanceMode` "so it slots into the
  settings menu as a `Picker`."
- **UserDefaults suite split**: app preferences use `.standard` (`@AppStorage` +
  `AppDelegate`); only the skip list uses the App Group suite, and only the app + widget
  hold the App Group entitlement. The watch falls back to `.standard` and relies on
  WatchConnectivity. There is no shared key-name constant; `"allowsLandscape"` is
  duplicated between `@AppStorage` and `AppDelegate`.
- **Process model**: `SingleThreadCore` is compiled into four processes; each owns its own
  `ReminderStore`, EventKit fetch, and in-memory `reminders`/`skippedIDs`. Ordering is
  recomputed identically in each process from an independent fetch.
- **Testing convention**: unit tests use Swift Testing (`@Test`/`#expect`); view tests
  assert on `String(describing: view.body)`; enums are tested for computed-property mappings
  and `allCases`.

## Open Areas
- No code path or test inspects a `.sort` option/`SortOption`; no sort preference exists
  anywhere in `SingleThread/` or `SingleThreadCore/` (relevant to any future sort-by work).
- Watch app has no App Group entitlement (`project.pbxproj:787-833`) — inferred from build
  configs; on-device ad-hoc signing could theoretically differ.
- `systemImage` computed properties are untested.
- No preview or UI test renders a sorted list, so ordering is only covered by unit tests.