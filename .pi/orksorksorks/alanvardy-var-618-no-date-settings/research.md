# Research Findings

## Q1: What user preferences does the settings screen currently expose, and exactly how is each one represented?

### Findings
- The settings screen (`SingleThread/SettingsView.swift`) exposes **4 preferences**. `SettingsView` owns no state — its doc comment states every preference is bound back to `ContentView`'s `@AppStorage` (`SettingsView.swift:5-7`).
- **State ownership is root-level `@AppStorage` in `ContentView`** (`SingleThread/ContentView.swift:115-127`), not in `SettingsView`. `SettingsView` receives them as **init-injected `Binding`s** and stores them as `@Binding` (`SettingsView.swift:75-80`) — not `@AppStorage`, not `@Bindable`.

1. **Appearance mode** — `@AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system` (`ContentView.swift:115-116`). Type `AppearanceMode: String, CaseIterable` (`.system/.light/.dark`, `SingleThread/AppearanceMode.swift:8-11`). Bound via `appearanceMode: $appearanceMode` (`ContentView.swift:70`); consumed by `Picker("Appearance", selection: $appearanceMode)` (`SettingsView.swift:37-42`). Shared iOS + macOS.

2. **Text size** — `@AppStorage("textSize") private var textSize = TextSize.system` (`ContentView.swift:118-119`). Type `TextSize: String, CaseIterable` (`.system/.small/.medium/.large/.extraLarge`, `SingleThread/TextSize.swift:8-13`). Bound via `textSize: $textSize` (`ContentView.swift:71`); consumed by `Picker("Text Size", selection: $textSize)` (`SettingsView.swift:43-47`). Shared iOS + macOS.

3. **Allow Landscape (iOS-only)** — `@AppStorage("allowsLandscape") private var allowsLandscape = true` inside `#if os(iOS)` (`ContentView.swift:121-123`). Type `Bool`. Bound via `allowsLandscape: $allowsLandscape` (iOS init only, `ContentView.swift:70`); consumed by `Toggle(isOn: $allowsLandscape)` with `.onChange` calling `AppDelegate.applyLock(allowsLandscape:)` (`SettingsView.swift:49-55`). iOS-only.

4. **Show Microphone Button** — `@AppStorage("showMicrophoneButton") private var showMicrophoneButton = true` (`ContentView.swift:126-127`). Type `Bool`. Bound via `showMicrophoneButton: $showMicrophoneButton` (`ContentView.swift:73`/`:78`); consumed by `Toggle(isOn: $showMicrophoneButton)` (`SettingsView.swift:57-59`). Shared iOS + macOS. Also gates the mic button at `ContentView.swift:299`.

- **Init variant selection** is `#if os(iOS)` / `#else` in both `ContentView` (`ContentView.swift:68-79`) and `SettingsView` (`SettingsView.swift:11-31`). The sheet is presented via `.sheet(isPresented: $isShowingSettings)` (`ContentView.swift:67`).
- **Secondary (non-`@AppStorage`) read:** `AppDelegate` reads the raw `"allowsLandscape"` key at launch via `UserDefaults.standard.object(forKey:) != nil`, defaulting to `true` (`SingleThread/AppDelegate.swift:34-36`); `applyLock` is at `AppDelegate.swift:17-29`.
- **Platform scope:** `appearanceMode`, `textSize`, `showMicrophoneButton` are shared by the iOS and macOS app targets; `allowsLandscape` is iOS-only. No `@AppStorage` exists in `SingleThreadWatch/`, `SingleThreadWidget/`, or `SingleThreadCore/`.
- The only other `UserDefaults` key in the app is `"skippedReminderIdentifiers"` (App-Group backed, `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:114`), which is skip state, not a settings preference.

## Q2: How does `ReminderStore` load reminders from EventKit, and what due-date window does the fetch predicate use?

### Findings
- `ReminderStore` is `@MainActor @Observable public final class` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:5-7`) owning an `any EventKitStoring` seam (`ReminderStore.swift:235`; protocol `EventKitStoring.swift:7-36`, `extension EKEventStore: EventKitStoring` `EventKitStoring.swift:39`).
- Load path: `start()` reads `authorizationStatus(for: .reminder)` and either `reload()`es on `.fullAccess` or calls `requestAccess()` (`ReminderStore.swift:68-75`); `requestAccess()` → `requestFullAccessToReminders()` → reload on grant (`ReminderStore.swift:187-197`).
- Single load path `reload(clearSkipped:)` (`ReminderStore.swift:159-178`): no-ops when `loadsReminders == false` (`:160`), `refreshSourcesIfNecessary()` on non-watchOS (`:161-163`), builds the predicate, fetches via an async bridge, assigns `reminders = fetched` (`:169`), then resolves skipped IDs and fires `onRemindersChanged`.
- **Predicate** (`ReminderStore.swift:164-167`):
  ```swift
  eventStore.predicateForIncompleteReminders(
      withDueDateStarting: ReminderDateFilter.overdueCutoff(),
      ending: ReminderDateFilter.endOfToday(),
      calendars: nil)
  ```
- **Window:** start = `overdueCutoff()` = start-of-day 30 days before today (`ReminderDateFilter.swift:41-49`); end = `endOfToday()` = start-of-today + 1 day − 1 second = 23:59:59 today (`ReminderDateFilter.swift:28-35`). `calendars: nil` = all available calendars. Inclusive at both ends.
- Fetch completes via `withCheckedContinuation`; a `nil` completion result is coerced to `[]` (`ReminderStore.swift:232-237`).
- **No post-fetch date filtering exists anywhere:** `reminders = fetched` (`ReminderStore.swift:169`); the only downstream exclusion is skip-ID filtering in `visibleReminders` (`ReminderStore.swift:59-63`). This is the app's **only** `predicateForIncompleteReminders` call site (grep confirms: `ReminderStore.swift:164` and the protocol/mock in `EventKitStoring.swift:14`/`EventKitStoringTests.swift:59`).
- **Which reminders the current fetch returns:** because the predicate passes **non-nil** start and end dates, and the app never issues a `nil`-date predicate, the returned set is incomplete reminders with a due date inside `[30 days ago 00:00:00, today 23:59:59]`. Timed and all-day reminders are matched the same way (the repo never special-cases `isAllDay`; the only date read is `dueDateComponents?.date` in `ReminderSort.swift:21-22`, `ReminderDisplay.swift:14`, `ContentView.swift:242`). **Reminders with no due date are not returned** — EventKit's `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` only includes undated reminders when both dates are `nil`, which this codebase never passes (SDK header `EKEventStore.h:397-405` documents only "incomplete reminders due in a range"). The app-side code itself performs no undated-reminder exclusion or inclusion.

## Q3: How is `visibleReminders` computed, and where do nil-`dueDateComponents` reminders land in `ReminderSort` ordering?

### Findings
- `visibleReminders` is a computed property (`ReminderStore.swift:59-63`):
  ```swift
  reminders
      .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
      .sorted { ReminderSort.areInIncreasingOrder($0, $1) }
  ```
- **Skip filtering:** `skippedIDs: Set<String>` is the in-memory set (`ReminderStore.swift:41`), persisted as `"skippedReminderIdentifiers"` via `SkippedReminderStore` (`ReminderSkip.swift:111-128`, defaulting to `AppGroup.defaults`). On reload, the persisted list is pruned by intersection with fetched IDs via `ReminderSkipLogic.resolve` (`ReminderSkip.swift:5-22`, called at `ReminderStore.swift:170-177`). Skipping appends + prunes via `ReminderSkipLogic.skipping` (`ReminderSkip.swift:24-32`) through `updatedSkipSet(afterSkipping:)` (`ReminderStore.swift:214-219`) and `applySkipSet` (`ReminderStore.swift:222-227`). Skipped reminders are excluded from `visibleReminders` but **remain in `reminders`**.
- **Skip entry points:** `skipCurrentReminder()` (`ReminderStore.swift:137-147`, async, settled) and `skipCurrentReminderImmediately()` (`ReminderStore.swift:152-161`, synchronous, for the widget).
- **`ReminderSort` ordering** (`ReminderSort.swift:6-33`), precedence order:
  1. **Priority** via `ReminderPriority.rank` (`ReminderSkip.swift:83-89`): high=0, medium=1, low=2, `nil` unset; prioritized before unprioritized.
  2. **Due date** via `dueDateComponents?.date`, soonest first.
  3. **Title** — case-insensitive alphabetic tie-break (`localizedCaseInsensitiveCompare == .orderedAscending`).
- **Nil `dueDateComponents` placement** (`ReminderSort.swift:20-31`): the date switch returns `true` for `(.some, .none)` and `false` for `(.none, .some)`, so a reminder with nil `dueDateComponents` **sorts after any dated reminder at the same priority level**, and undated reminders fall through to alphabetic title order only among themselves.
- Confirmed by tests: `visibleRemindersSortsDatedBeforeUndated` (`SingleThreadTests/ReminderStoreTests.swift:58-72`) and `sortsDatedBeforeUndated` (`SingleThreadTests/ReminderSkipTests.swift:274-279`).
- **No timed-vs-all-day distinction exists** in sorting or filtering: both compare through the single `dueDateComponents?.date` (`ReminderSort.swift:21-23`). `ReminderDisplay` also stores only `dueDateComponents?.date` (`ReminderDisplay.swift:14-16`). The only "all-day"-adjacent code is in `ReminderDictationParser`, not sorting/filtering.

## Q4: How do the watch app and widget each obtain/display the current reminder, and what state do they share vs. compute independently?

### Findings
- **App Group:** `AppGroup.suiteName = "group.app.alanvardy.SingleThread"` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8`); `AppGroup.defaults` falls back to `.standard` when the group is unavailable (`AppGroup.swift:13-15`). Registered in `SingleThread/AppGroup.entitlements:6-8` (iOS) and `SingleThread/SingleThread.entitlements:7-9` (macOS); the widget target uses the App entitlement (`project.pbxproj`), but the **watch target declares no `CODE_SIGN_ENTITLEMENTS`**, so the watch's `SkippedReminderStore` silently uses `.standard`.
- **Skip-list persistence:** `SkippedReminderStore` defaults to `AppGroup.defaults` under key `"skippedReminderIdentifiers"` (`ReminderSkip.swift:111-128`).
- **WatchConnectivity** (`SkippedReminderSyncService.swift`, guarded `#if os(iOS) || os(watchOS)`): skip sync uses `updateApplicationContext(["skippedReminderIdentifiers": …])` — latest-wins full-array replace (`pushSkipIDs`, `:55-63`; receive `:79-92` authoritatively `save`s). Completion relay is `sendMessage(["completeReminderIdentifier": …])` with `replyHandler: nil` (fire-and-forget, `:66-75`; receive `:94-98` → `onCompleteReminderReceived`). No `transferUserInfo`/`didReceiveUserInfo` anywhere.
- **Phone wiring** (`SingleThread/SingleThreadApp.swift:14-37`): creates the sync service, sets `onCompleteReminderReceived` → `store.completeReminder`, `onSkipSetChanged` → `pushSkipIDs`, `onCompleteReminder` → `requestCompleteReminder`, `onRemindersChanged` → `WidgetCenter.shared.reloadAllTimelines()`. `--ui-testing` disables reminder loading (`:16`).
- **Watch wiring** (`SingleThreadWatch/SingleThreadWatchApp.swift:9-21`): real `ReminderStore` (unless `--ui-testing`), activates WCSession, wires `onSkipSetChanged`/`onCompleteReminder`. Watch EventKit is read-only: `completeReminder` removes locally and relays via `onCompleteReminder` (`ReminderStore.swift:79-83`).
- **Watch display** (`SingleThreadWatch/WatchReminderView.swift`): `.task { await store.start() }` fetches locally (`:44`); picks `store.visibleReminders.first` (`:66-71`) with `allSkipped`/`noReminders`/`allDone` branching (`:55-58`, `:100-116`); Complete/Skip buttons call `completeCurrentReminder()`/`skipCurrentReminder()` (`:77-98`); refresh calls `store.reload(clearSkipped: allSkipped)` (`:158-173`).
- **Widget display** (`SingleThreadWidget/NextThingWidget.swift`): `NextThingProvider.getTimeline` builds one entry via `makeEntry()` and a 15-minute `.after` refresh (`:33-41`); `makeEntry()` checks `EKEventStore.authorizationStatus`, builds a fresh `ReminderStore(loadsReminders: true)`, `await store.reload()`, then `visibleReminders.first` → `.noAccess`/`.empty`/`.allDone`/`.reminder(ReminderDisplay)` (`:44-64`). Actions use AppIntents `CompleteReminderIntent`/`SkipReminderIntent` (fresh store + reload + `completeCurrentReminder()`/`skipCurrentReminderImmediately()`), which write through `applySkipSet` → `skipStore.save` → App Group `UserDefaults`.
- **Shared vs computed — summary:**
  | Surface | Fetches reminders | Skip list source | Sort/pick-first | Skip sync |
  |---|---|---|---|---|
  | iOS/macOS app | EventKit (local) | App Group + WC receive | `visibleReminders.first` | App Group + `updateApplicationContext` |
  | Watch | EventKit (local, read-only) | `.standard` (App Group fallback) + WC receive | `visibleReminders.first` | `updateApplicationContext` |
  | Widget | EventKit (local) | App Group | `visibleReminders.first` | App Group |
- **Only the skip-ID array (`"skippedReminderIdentifiers"`) is synced** — via App Group (phone↔widget) and `updateApplicationContext` (phone↔watch) — plus the one-way watch→phone `"completeReminderIdentifier"` `sendMessage`. **Each surface independently re-fetches EventKit and recomputes `visibleReminders.first` locally**; no "current reminder" title/display payload crosses any boundary.

## Q5: What testing and preview conventions apply to settings and reminder display, and how are preference changes validated?

### Findings
- **Seedable initializers:** `ReminderStore` production init (`ReminderStore.swift:13-21`) vs. preview/test init that pre-populates `reminders`/`skippedIDs`/`authorizationStatus` and never touches EventKit (`ReminderStore.swift:23-33`). `loadsReminders` gates `start()` (`:68-75`), `reload` (`:159-178`). `ContentView` mirrors this: `init(store:)` (`ContentView.swift:13-17`), `init(loadsReminders:)` (`ContentView.swift:19-22`), pre-populated preview init (`ContentView.swift:24-36`). `WatchReminderView` has the same pair (`WatchReminderView.swift:9-23`).
- **Preview fixtures:** `mockReminder` file-scoped `EKReminder` (`ContentView.swift:439-449`) with `#Preview`s "Empty"/"With Reminder"/"All Skipped"/"No Access" (`ContentView.swift:452-475`). `SettingsView` previews use `.constant(...)` bindings (`SettingsView.swift:86-112`). Watch previews incl. `mockWatchReminder` (`WatchReminderView.swift:206`, `#Preview` "Requesting Access"/"Reminder"/"All Skipped"/"No Reminders"/"No Access"). Widget previews ("Reminder"/"No Access"/"All Done") in `NextThingWidget.swift`.
- **No shared test factory** — each file has a private `makeReminder`: `ReminderStoreTests.swift:320` (`makeReminder(title:priority:dateComponents:)`), `ReminderSkipTests.swift:285`, `ReminderDisplayTests.swift:78`, `EventKitStoringTests.swift:299`. Main injection fake: `FakeEventStore: EventKitStoring` (`EventKitStoringTests.swift:10-105`), plus `testStore(eventStore:)` builder (`:304-310`).
- **`@Test` suites (Swift Testing):** `ReminderStoreTests.swift` (visibleReminders filter/sort `:10-66`, add `:68-116`, skip `:118-162`, complete `:164-212`, `loadsReminders:false` guards `:214-236`); `EventKitStoringTests.swift` writes/lifecycle via `FakeEventStore` (`:187-270`); `ReminderSortTests` priority/date/dated-before-undated/title (`ReminderSkipTests.swift:237-300`); `ReminderDisplayTests.swift:5`; `ReminderDateFilterTests` (`SingleThreadTests.swift:26-76`, `endOfToday`/`overdueCutoff` — no undated case); `ReminderSkipLogicTests`/`ReminderPriorityTests`/`ReminderNotesFormatterTests` (`ReminderSkipTests.swift:5,98,147`).
- **Preference validation today:** `SettingsViewTests.swift:8-31` asserts only `String(describing: view.body)` contains labels ("Appearance"/"Text Size"/"Microphone"/"Done"/"Landscape" iOS-only) — **no interaction/selection assertions**. `MicrophoneToggleTests.swift:32-86` drives `UserDefaults.standard` `"showMicrophoneButton"`. `AppDelegateTests.swift:8-32` drives `"allowsLandscape"` true/false/missing. `AppearanceModeTests.swift:6` and `TextSizeTests.swift:6` test enum mapping only, **not persistence**.
- **UI/accessibility:** `SingleThreadUITests.swift` `testAccessibilityAudit` launches with `--ui-testing` (`:19`) and runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` (`:30-34`) against the post-launch "Requesting access…" screen (does **not** open Settings). `testLaunch` screenshot exists (`SingleThreadUITestsLaunchTests.swift:18-31`).
- **Coverage gaps (factual):** no test exercises `SettingsView` Picker/Toggle selection or binding propagation; no `@AppStorage` persistence round-trip for `appearanceMode`/`textSize`; no test for undated-reminder exclusion from `reload`'s predicate (`ReminderStore.swift:164-167`); no test for the due-date `Text(due, style: .date)` rendering (`ContentView.swift:242-243`); accessibility audit does not cover the Settings screen.

## Cross-Cutting Observations
- **Single source of truth for "current reminder":** every surface (iOS app, watch, widget) derives the current reminder by the same `visibleReminders` = filter-skip + `ReminderSort` sort + `.first`. The only cross-surface shared state is the skip-ID list; the reminder set, ordering, and selection are always recomputed locally against each surface's own EventKit fetch (`ReminderStore.swift:59-63`).
- **Preferences live entirely in the iOS/macOS app target via `@AppStorage` in `ContentView`** and are injected downward into `SettingsView` as `Binding`s. `SingleThreadCore`, the watch, and the widget contain no `@AppStorage` at all. A date-related setting would therefore sit in this layer, alongside `appearanceMode`/`textSize`/`allowsLandscape`/`showMicrophoneButton` (`ContentView.swift:115-127`).
- **Undated reminders are structurally absent today at the fetch layer**: the single `predicateForIncompleteReminders` call passes a non-nil date range (`ReminderStore.swift:164-167`), so no-due-date reminders are never fetched (EventKit includes them only for a nil/nil predicate). Downstream code is nil-date-tolerant nonetheless (`ReminderSort.swift:20-31` sorts undated last; `ContentView.swift:242-243` and `WatchReminderView.swift:155` and `NextThingWidget.swift` conditionally hide the date line).
- **Test seams are consistent:** `loadsReminders:false` + a pre-populated init is the uniform way views and stores are seeded for previews and unit tests; `--ui-testing` is the uniform launch gate to skip EventKit in UI tests (`SingleThreadApp.swift:16`, `SingleThreadWatchApp.swift:11`). UI-testing mode shows the "Requesting access…" state, which is what the accessibility audit actually exercises.

## Open Areas
- **Exact EventKit behavior for undated reminders under a non-nil range** is framework-documented, not provable from repo code; Apple's docs describe the predicate as fetching reminders "due in a range," and `nil`/`nil` is required to include undated ones. The app has no code path or test that exercises undated reminders, so the empirical inclusion/exclusion is unverified in this repo.
- **Watch–widget skip propagation:** a widget-initiated skip (`SkipReminderIntent`) writes the App Group but is not immediately relayed to the watch (no `onSkipSetChanged`/WCSession hook on the widget's store), so cross-device convergence relies on later reads (`ReminderStore.swift:170-177` fires `onSkipSetChanged` only on the `clearSkipped` path).