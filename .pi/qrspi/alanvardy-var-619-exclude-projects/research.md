# Research Findings

## Q1: Trace how the settings screen is built and persisted

### Findings
- `SettingsView` is a standalone `struct SettingsView: View` (`SingleThread/SettingsView.swift:7`). It owns **no** state itself (doc comment `SettingsView.swift:5-6`); all preference state lives in `ContentView` via `@AppStorage`.
- Body is `NavigationStack { Form { … } }` with a `ToolbarItem(placement: .confirmationAction)` `Button("Done")` calling `dismiss()` (`SettingsView.swift:35-36`, `:61-67`); it applies `.preferredColorScheme(appearanceMode.colorScheme)` (`:69`) and `.modifier(TextSizeModifier(textSize:))` (`:70`).
- Preferences are declared in `ContentView` as `@AppStorage` string-literal keys:
  - `@AppStorage("appearanceMode")` → `AppearanceMode.system` (`ContentView.swift:115-116`)
  - `@AppStorage("textSize")` → `TextSize.system` (`ContentView.swift:118-119`)
  - `#if os(iOS)` `@AppStorage("allowsLandscape")` → `true` (`ContentView.swift:121-124`)
  - `@AppStorage("showMicrophoneButton")` → `true` (`ContentView.swift:126-127`)
- `SettingsView` receives these as `@Binding private var` (`SettingsView.swift:75-80`), plus `@Environment(\.dismiss)` (`:81-82`). Two **platform-specific initializers** assign `_appearanceMode = appearanceMode` etc.: iOS 4-binding init (`:10-20`) and `#else` 3-binding init without `allowsLandscape` (`:21-30`).
- Presentation: gear `Button` in `ContentView` sets `isShowingSettings = true` (`ContentView.swift:47-61`), shown via `.sheet(isPresented:)` that builds `SettingsView` with `$`-bindings under `#if os(iOS)` 4-arg vs `#else` 3-arg (`ContentView.swift:67-79`).
- Controls used (`SettingsView.swift:36-59`): two `Picker(...)` over `CaseIterable` with `Label(...).tag(...)`; iOS-only `Toggle(isOn: $allowsLandscape)` with `.onChange` → `AppDelegate.applyLock(allowsLandscape:)` (`:49-56`); `Toggle(isOn: $showMicrophoneButton)` (`:57-59`).
- Supporting enum models are `String, CaseIterable` persisted by raw value: `AppearanceMode` (`SingleThread/AppearanceMode.swift:8-45`) and `TextSize` (`SingleThread/TextSize.swift:8-42`), each mapping a case to `colorScheme`/`dynamicTypeSize` (`.system → nil`).
- Orientation nuance: the iOS toggle writes `@AppStorage("allowsLandscape")`, but `AppDelegate` independently reads the raw `UserDefaults` key at launch so the lock applies before SwiftUI appears (`SingleThread/AppDelegate.swift:7-10`, `:32-38`), re-evaluated in `applyLock(allowsLandscape:)` (`:17-29`).
- Tests (Swift Testing, `@MainActor` + `@Test` + `#expect`): `SettingsViewTests.settingsViewContainsAllPreferenceRows` constructs `SettingsView` with `Binding.constant(...)` and asserts `String(describing: view.body)` contains `"Appearance"`, `"Text Size"`, `"Microphone"`, `"Done"`, and iOS-only `"Landscape"` (`SingleThreadTests/SettingsViewTests.swift:7-36`). Companion tests: `MicrophoneToggleTests` (`:27-87`), `AppearanceModeTests` (`:8-40`), `TextSizeTests` (`:8-40`), `AppDelegateTests` (`#if os(iOS)`, `:7-36`).
- Previews: `SettingsView` iOS `"Default"` / `"Dark + Extra Large"` and non-iOS `"Default"` all use `.constant(...)` (`SettingsView.swift:87-110`); `ContentView` previews `"Empty"`/`"With Reminder"`/`"All Skipped"`/`"No Access"` (`ContentView.swift:452,456,464,472`).
- The watch target has **no** settings screen or `@AppStorage`/`@Binding` preferences (grep of `SingleThreadWatch/` finds none). No settings UI tests exist in `SingleThreadUITests/`.

## Q2: Trace the reminder fetch-to-display flow

### Findings
- `ReminderStore.reload(clearSkipped:)` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:159-181`):
  - `guard loadsReminders else { return }` (`:160`)
  - `#if !os(watchOS)` `eventStore.refreshSourcesIfNecessary()` (`:162`) — iOS/macOS only, skipped on watchOS
  - Builds the EventKit predicate (`:164-168`):
    - `withDueDateStarting: ReminderDateFilter.overdueCutoff()` — start of day 30 days ago (`SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift:41-50`)
    - `ending: ReminderDateFilter.endOfToday()` — last instant of today 23:59:59 (`ReminderDateFilter.swift:28-36`)
    - **`calendars: nil`** (`:167`) — searches **all** calendars
  - It is `predicateForIncompleteReminders` — only **incomplete** reminders in that due-date window are fetched.
  - `let fetched = await fetchReminders(matching: predicate)` (`:168`), then `reminders = fetched` (`:169`).
- The predicate API is declared in `EventKitStoring` (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:14-17`) and conformed by `EKEventStore` (`:39`).
- `fetchReminders(matching:)` bridges EventKit's completion handler to async/await via `withCheckedContinuation` (`ReminderStore.swift:232-236`), coalescing `nil` to `[]`.
- The show/hide decision is made in **`visibleReminders`** (`ReminderStore.swift:59-63`): the fetched `reminders` are `.filter { !skippedIDs.contains($0.calendarItemIdentifier) }` (`:61`) then `.sorted { ReminderSort.areInIncreasingOrder($0, $1) }` (`:62`). This is the display list consumed elsewhere as `.first` / `.isEmpty` (`ContentView.swift:142,230,302`, `SingleThreadWatch/WatchReminderView.swift:57,66`).
- Before filtering, `reload` reconciles `skippedIDs` (`ReminderStore.swift:171-179`): `clearSkipped` empties + persists `[]` (`:171-174`); otherwise `ReminderSkipLogic.resolve(fetched:skipped:)` prunes stale IDs and assigns `skippedIDs = Set(resolved)` (`:175-179`). Sort order (`ReminderSort.swift:7-31`): priority rank, then due date (dated before undated), then title.
- Two-stage decision in total: EventKit's predicate narrows the **fetch** (incomplete + date window + all calendars); `visibleReminders` applies the **skip exclusion + sort** on top.

## Q3: EventKit calendar/list APIs and any calendar/list model

### Findings
- EventKit calendar/list APIs appear **only as type signatures**, never as actual list/calendar **reading**. There is **no calendar or list model** anywhere in the Swift sources.
- `EKCalendar` occurs only as parameter/type, never enumerated:
  - `calendars: [EKCalendar]?` in the protocol requirement (`EventKitStoring.swift:17`)
  - Test fake: `defaultCalendar: EKCalendar?` init param/property (`SingleThreadTests/EventKitStoringTests.swift:17,33`) and `predicateForIncompleteReminders(... calendars _: [EKCalendar]?)` ignoring the argument (`:59-62`).
- `defaultCalendarForNewReminders()` is the only calendar access, and it is **write-path only**: `reminder.calendar = defaultCalendarForNewReminders()` inside `EKEventStore.makeReminder` (`EventKitStoring.swift:57`), asserted in `ReminderStoreTests.swift:313`.
- `EKSource` — zero occurrences. `calendarIdentifier` — zero occurrences in Swift sources. `calendars(for:)` (the `EKEventStore` enumeration API) — zero occurrences.
- The predicate's `calendars:` argument is constructed in exactly one production place and is **always `nil`** (`ReminderStore.swift:164-168`, `calendars: nil` at `:167`). No code path supplies a restricted `[EKCalendar]`.
- The word "list" appears only in the skip-list logic (`ReminderSkip.swift`), not as a calendar/list model. The `Calendar` type in `ReminderDateFilter.swift:29,43` and `ReminderDictationParser.swift:62` is **Foundation.Calendar** (date math), not `EKCalendar`.
- Predicate retrieval surface (`EventKitStoring.swift:14-17`; conformance at `:39`); fetch bridging at `ReminderStore.swift:232-236`; `EKReminder`/`EKRecurrenceRule` are built from real `EKEventStore()` in fixtures (e.g. `ContentView.swift:439-441`, `EventKitStoringTests.swift:299-300`).

## Q4: Skipped-reminder exclusion — persistence and pruning

### Findings
- **`SkippedReminderStore`** (`ReminderSkip.swift:111-133`): plain struct wrapping `UserDefaults` + key. `init(defaults: UserDefaults = AppGroup.defaults, key: String = "skippedReminderIdentifiers")` (`:114`). `load()` reads `defaults.stringArray(forKey:) ?? []` (`:121-123`); `save(_:)` writes `defaults.set(...)` (`:125-127`).
- **App Group backing** (`AppGroup.swift`): `suiteName = "group.app.alanvardy.SingleThread"` (`:8`); `defaults` returns `UserDefaults(suiteName:) ?? .standard` (`:13-14`), falling back to `.standard` on watchOS/unregistered simulators. The App Group entitlement is attached to iOS app + widget (`project.pbxproj:592-594,642-644,844,872`); the watch target has none (`project.pbxproj:785-833`), so watch resolves to `.standard`.
- **`ReminderSkipLogic`** (`ReminderSkip.swift:5-24`, `nonisolated`, Foundation-only):
  - `resolve(fetched:skipped:)` (`:12-15`) returns `Array(Set(fetched).intersection(skipped))` — prunes stale IDs.
  - `skipping(_:fetched:skipped:)` (`:19-23`) appends the new ID then delegates to `resolve`.
- **Ownership in `ReminderStore`**: in-memory `skippedIDs: Set<String>` (`ReminderStore.swift:41`); persistence handle `skipStore: SkippedReminderStore` (`:210`). Production init defaults `skipStore: SkippedReminderStore()` (`:15`); preview/test init builds a fresh inert one (`:33`).
- **Write points**:
  - `skipCurrentReminder()` (`ReminderStore.swift:136-145`): computes `updatedSkipSet`, then after a 200 ms `eventKitSettleDelay` (`:204`) calls `applySkipSet(updated)`.
  - `skipCurrentReminderImmediately()` (`:152-157`): synchronous, no settle delay — used by the widget.
  - `updatedSkipSet(afterSkipping:)` (`:214-219`) calls `ReminderSkipLogic.skipping(... fetched: reminders.map(\.calendarItemIdentifier), skipped: Array(skippedIDs))`.
  - `applySkipSet(_:)` (`:222-226`): sets `skippedIDs`, `skipStore.save(updated)`, fires `onSkipSetChanged?(updated)` and `onRemindersChanged?()`.
  - `reload(clearSkipped: true)` (`:171-174`): `skippedIDs = []`, `skipStore.save([])`, `onSkipSetChanged?([])`.
- **Alignment with fetched reminders** (`reload`, `:175-179`): non-clear branch reads `skipStore.load()` and prunes in memory via `resolve`, assigning `skippedIDs = Set(resolved)`. **Note**: this branch does *not* `skipStore.save(resolved)` — stale IDs are dropped from memory/`visibleReminders` but linger in `UserDefaults` until the next write (`applySkipSet`/clear-skip). This is the only point where persisted and in-memory sets can diverge.
- **Sync write path bypasses `ReminderStore`**: `SkippedReminderSyncService.didReceiveApplicationContext` extracts the array and calls `skipStore.save(receivedIDs)` directly — latest-wins replace (`SkippedReminderSyncService.swift:79-89`); stale IDs are pruned later by `reload` (comment `:84-88`).
- `ReminderStore` and `SkippedReminderSyncService` each construct their **own** `SkippedReminderStore`, but both default to `AppGroup.defaults` + key `"skippedReminderIdentifiers"`, so they converge on the same persisted key (`SkippedReminderSyncService.swift:118-120`).

## Q5: `ReminderStore` injection and testing

### Findings
- **`EventKitStoring`** (`EventKitStoring.swift`): `@MainActor public protocol EventKitStoring: AnyObject` (`:7-8`). Wraps only the EventKit surface the store calls (doc `:4-6`). Requirements: `authorizationStatus(for:)` (`:10`), `requestFullAccessToReminders()` (`:12`), `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (`:14-17`), `@discardableResult fetchReminders(matching:completion:)` (`:19-22`); `#if !os(watchOS)` adds `refreshSourcesIfNecessary()` (`:25`), `save(_:commit:)` (`:27`), `makeReminder(...)` (`:31-33`).
- `extension EKEventStore: EventKitStoring` (`:39`): only `authorizationStatus` (`:40-42`) and `makeReminder` (`:44-58`) carry bodies; `makeReminder` sets title/notes/dueDate/recurrenceRule and `reminder.calendar = defaultCalendarForNewReminders()` (`:57`).
- **`ReminderStore` injection** (`ReminderStore.swift`): `@MainActor @Observable public final class` (`:5-7`); private deps `eventStore: any EventKitStoring` (`:209`) and `skipStore` (`:210`). Two initializers:
  - Production (`:13-20`): `(eventStore: any EventKitStoring = EKEventStore(), skipStore: SkippedReminderStore = SkippedReminderStore(), loadsReminders: Bool = true)`.
  - Preview/test (`:23-34`): `(loadsReminders:reminders:skippedIDs:authorizationStatus:)` pre-populates state and "never touches EventKit", still assigning inert `eventStore = EKEventStore()` / `skipStore = SkippedReminderStore()` (`:32-33`).
- App/view wiring: `SingleThreadApp` builds `ReminderStore(loadsReminders:)` gated on the `--ui-testing` launch arg (`SingleThread/SingleThreadApp.swift:16-17`) → `ContentView(store:)` (`:49`); `ContentView` has store-accepting init (`:11-14`), default `loadsReminders` init (`:16-19`), preview init forwarding 4 args (`:22-32`). Watch: `SingleThreadWatchApp.swift:10-11` → `WatchReminderView(store:)` (`:28`); watch preview init pre-populates (`WatchReminderView.swift:13-22`).
- **`FakeEventStore`** (`SingleThreadTests/EventKitStoringTests.swift:8-103`): `@MainActor private final class FakeEventStore: EventKitStoring`. Config init (`:14-27`) with `authStatus/accessGranted/accessError/fetchResult/defaultCalendar`; recording state `saved/lastSaveCommit/lastPredicate/fetchCallCount/requestAccessCallCount/refreshCallCount` (`:40-45`). `predicateForIncompleteReminders` returns `NSPredicate(value: true)` (`:61-64`); `fetchReminders` increments + records predicate + synchronously invokes completion (`:66-73`); `save` records/throws on `saveShouldThrow` (`:80-88`); `makeReminder` builds a real `EKReminder` (`:89-102`).
- **Swift Testing conventions** (`import Testing`, `@testable import SingleThreadCore`): `@MainActor` suites; `@Suite(.serialized)` for store suites (`EventKitStoringTests.swift:111,186`; `ReminderStoreTests.swift:6`); `@Test`/`#expect`; `#if !os(watchOS)` mirrors production split (`ReminderStoreWriteTests` `:108-182`, `MakeReminderTests` `ReminderStoreTests.swift:245-317`).
- Per-test isolation: `testStore(eventStore:)` builds a `ReminderStore` with `SkippedReminderStore(defaults: .standard, key: "test-\(UUID().uuidString)")` (`EventKitStoringTests.swift:305-310`). Fixtures `makeReminder(title:)` (`:299-304`) / `makeReminder(title:priority:dateComponents:)` (`ReminderStoreTests.swift:320-326`). Skip-path tests await one-shot hooks via `withCheckedContinuation` (`ReminderStoreTests.swift:145-146,160-161`).

## Q6: Watch app & widget store construction; phone↔watch WatchConnectivity sync

### Findings
- **Watch app** owns one `ReminderStore` at entry, injected into its single view: `SingleThreadWatch/SingleThreadWatchApp.swift:10-12` constructs `ReminderStore(loadsReminders: !args.contains("--ui-testing"))`; passed to `WatchReminderView(store:)` (`:25-29`). Uses production init; the watch's `SkippedReminderStore()` → `AppGroup.defaults` → `.standard` (no App Group entitlement on watch).
- Watch usage (`WatchReminderView.swift`): `await store.start()` from `.task` (`:40-42`); `store.visibleReminders.first` (`:60`); `store.completeCurrentReminder()` (`:83`); `store.skipCurrentReminder()` (`:91`); `store.reload(clearSkipped:)` (`:177`).
- Watch-specific store behavior: `completeReminder` on watchOS removes locally + fires `onCompleteReminder?(identifier)` instead of saving EventKit (`ReminderStore.swift:84-96`, watch branch `:85-87`); `addReminder` on watchOS always returns `false` (`:117-118`).
- **Widget** builds a fresh, short-lived `ReminderStore` per operation (does not share the app instance):
  - `NextThingProvider.makeEntry()` checks `EKEventStore.authorizationStatus(for: .reminder)`, on `.fullAccess` builds `ReminderStore(loadsReminders: true)`, `await store.reload()`, reads `store.reminders.isEmpty` / `store.visibleReminders.first` (`SingleThreadWidget/NextThingWidget.swift:51-65`); `getTimeline` refreshes after 15 min (`:37-45`).
  - `CompleteReminderIntent.perform()` (`ReminderIntents.swift:19-21`) and `SkipReminderIntent.perform()` (`:41-47`) each construct `ReminderStore(loadsReminders: true)`, `reload()`, then complete / `skipCurrentReminderImmediately()` (the synchronous path, `ReminderStore.swift:152-157`).
  - Widget persistence seam: `SkippedReminderStore()` → `AppGroup.defaults` resolves to the shared suite (`AppGroup.swift:8,13-14`); widget target signed with `AppGroup.entitlements`.
- **`SkippedReminderSyncService`** (`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`, `#if os(iOS) || os(watchOS)`): `SkipSyncSession` protocol (`:8-15`) with `activate/updateApplicationContext/sendMessage`, `WCSession` conformance (`:17`); service is `NSObject`/`WCSessionDelegate` (`:23`).
  - `activate()` (`:48-53`); `pushSkipIDs(_:)` sends full array via `updateApplicationContext` (`:56-63`); `requestCompleteReminder(_:)` via `sendMessage` (`:66-73`); `didReceiveApplicationContext` replaces skip list with `skipStore.save(receivedIDs)` — latest-wins (`:79-89`); `didReceiveMessage` → `onCompleteReminderReceived` (`:92-96`); payload key enum `:118-121`.
- **Phone wiring** (`SingleThreadApp.swift:17-41`): builds store, builds `SkippedReminderSyncService(session: WCSession.default, skipStore: SkippedReminderStore())` (`:22-24`); sets `service.onCompleteReminderReceived` **before** `activate()` (`:30-33`); wires `store.onSkipSetChanged → pushSkipIDs`, `store.onCompleteReminder → requestCompleteReminder` (`:34-35`), and `store.onRemindersChanged → WidgetCenter.shared.reloadAllTimelines()` (`:39-41`).
- **Watch wiring** (`SingleThreadWatchApp.swift:14-20`): on `WCSession.isSupported()` builds + activates the service (`:15-18`); wires `onSkipSetChanged`/`onCompleteReminder` (`:19-20`); no `onCompleteReminderReceived` handler set.
- **State that flows**: (1) skip list — any skip mutation → `applySkipSet` saves locally + fires `onSkipSetChanged` → both devices push the full array via `updateApplicationContext`; receiver replaces local skip store; `reload` prunes stale IDs via `resolve` (`ReminderStore.swift:174-179`). (2) completion request — watch `completeReminder` fires `onCompleteReminder` → `sendMessage` → phone `didReceiveMessage` → shared-store `completeReminder(identifier:)` which saves via EventKit on iOS.

## Cross-Cutting Observations
- **Single dependency seam, three wrappers**: `EventKitStoring` (store), `SkipSyncSession` (WatchConnectivity), `SkippedReminderStore` (UserDefaults) are all protocol/struct seams over Apple APIs; `ReminderStore` is the `@MainActor @Observable` hub.
- **`calendars:` is effectively dead/unused parameter** — always `nil` in production, ignored by the test fake, and no calendar enumeration or model exists. Only EventKit calendar touch besides the predicate is the write default `defaultCalendarForNewReminders()`.
- **Visibility pipeline** = EventKit predicate (incomplete + 30-days-ago→end-of-today + all calendars) → `skipStore`-backed `skippedIDs` exclusion → `ReminderSort` sort, materialized lazily in `visibleReminders`.
- **Skip set convergence**: in-memory `skippedIDs` and persisted `[String]` (App Group `"skippedReminderIdentifiers"`) are reconciled by `ReminderSkipLogic.resolve` at reload and `ReminderSkipLogic.skipping` at every skip write; the reload prune is read-only (no save), and the sync receive path writes the store directly.
- **Hooks drive cross-surface fan-out**: `onSkipSetChanged`, `onCompleteReminder`, `onRemindersChanged` are the store's only output plumbing to WatchConnectivity and widgets.
- **Injection/testing style**: production init takes protocol/struct defaults; a `loadsReminders:reminders:skippedIDs:authorizationStatus:` init pre-populates for previews/tests without touching EventKit; Swift Testing with `@MainActor`, `@Suite(.serialized)`, `#expect`, `#if !os(watchOS)` guards, and UUID-keyed `UserDefaults.standard` per-test isolation.
- Watch is **read-only** for EventKit: no `refreshSourcesIfNecessary`, no `save`/`makeReminder`; completes/adds are handled by local removal/relay or `false`.

## Open Areas
- No calendar/list selection model exists, so nothing beyond `calendars: nil` can be answered about per-list behavior — it is simply never exercised.
- The reload-prune-does-NOT-save divergence in Q4 is confirmed by code but no test asserts persisted-state behavior afterward; whether any test or future feature relies on the stale-IDs-linger behavior is not covered.
- Watch-side completion reception: the watch never sets `onCompleteReminderReceived`, so phone-initiated completions (if ever sent) would not update the watch's local list — reflecting current one-directional completion flow only.