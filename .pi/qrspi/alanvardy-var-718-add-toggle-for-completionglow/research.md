# Research Findings

Branch: `alanvardy-var-718-add-toggle-for-completionglow`

## Q1: How is the completion feedback modelled and consumed today?

### Findings
- `CompletionGlow` is a self-contained `@MainActor @Observable public final class` (`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift:13`) with no external deps except `Foundation` `Task`/`Task.sleep`.
- State/configuration: `public private(set) var isActive = false` (`CompletionGlow.swift:21`); `public var duration: TimeInterval = 0.25` (`:25`, injectable — doc notes it's for tests); `private var dismissTask: Task<Void, Never>?` (`:47`).
- `trigger()` state machine (`CompletionGlow.swift:30-42`): sets `isActive = true` (`:31`), cancels prior `dismissTask` (`:32`), spawns a `Task` that sleeps `duration` seconds then sets `isActive = false` (`:34-42`); the `catch` on a cancelled task deliberately leaves `isActive` untouched so retriggering resets the timer.
- iOS consumer: `SingleThread/ContentViewModel.swift:36` owns `let completionGlow = CompletionGlow()`; `completeCurrentReminder()` calls `completionGlow.trigger()` only when `store.completeCurrentReminder()` returns `true` (`ContentViewModel.swift:106-109`). No `#if os` gating on this method.
- **watchOS mirror**: `SingleThreadWatch/WatchReminderViewModel.swift:33` owns an instance; `completeCurrentReminder()` triggers identically on success (`:44-50`).
- iOS view gate: `.overlay { if viewModel.completionGlow.isActive { completionGlowOverlay } }` (`SingleThread/ContentView.swift:81-83`), fade `.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: completionGlow.isActive)` (`:86-87`); `reduceMotion` from `@Environment(\.accessibilityReduceMotion)` (`:198`). Overlay content is `Color.green.opacity(0.3).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true).transition(.opacity)` (`:467-474`).
- watch view gate: same `.overlay` gate (`WatchReminderView.swift:84-86`), `.animation` bound to `isActive` (`:89-90`), overlay `Color.green`-style definition (`:139-146`), `reduceMotion` env (`:61`).
- Trigger call sites on iOS all route through `viewModel.completeCurrentReminder()`: `ContentView.swift:212` (macOS action button), `:338` (swipe action), `:411` (iOS complete button).
- Skip is not routed through the glow: watch Skip button calls `viewModel.store.skipCurrentReminder()` directly (`WatchReminderView.swift:103`).

## Q2: How are the "show X" display preferences persisted and modelled?

### Findings
- Shared store backend: `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:5-11`).
- All four structs share an identical shape: `init(defaults: UserDefaults = AppGroup.defaults, key: String = "...")`, read-only computed `isEnabled`, and `set(_:)`.
  - `ShowDatePreference`: key `"showDate"`, missing key → `true` (`ShowDatePreference.swift:11,15-21`).
  - `ShowListPreference`: key `"showList"`, missing key → `false` (`ShowListPreference.swift:11,15-21`).
  - `ShowRecurrencePreference`: key `"showRecurrence"`, missing key → `true` (`ShowRecurrencePreference.swift:11,15-21`).
  - `ShowAlarmsPreference`: key `"showAlarms"`, missing key → `true` (`ShowAlarmsPreference.swift:11,15-21`).
- Fifth sibling `ShowUndatedRemindersPreference` uses `load()`/`save(_:)` and key `"showUndatedReminders"`, missing → `false` (`ShowUndatedRemindersPreference.swift:6-22`).
- `@AppStorage` mirrors on `AppGroup.defaults` in `SingleThread/ContentView.swift`: `"showUndatedReminders"` (`:169`), `SortOption.defaultsKey` (`:172`), `"showDate"` (`:175`), `"showList"` (`:178`), `"showRecurrence"` (`:181`), `"showAlarms"` (`:183`). AppStorage defaults mirror the struct defaults (showList=false, others true).
- iOS-only vs shared: all structs live in shared `SingleThreadCore` and are used across every target. No preference is storage-gated iOS-only.
- Widget reads all four via the shared structs (`SingleThreadWidget/NextThingWidget.swift:64-67`).
- Watch persists to `.standard` (not the App Group) via `Show*State` holders: `ShowDateState.swift:28`, `ShowListState.swift:28`, `ShowAlarmsState.swift:28`, `ShowRecurrenceState.swift:28`, and `WatchAppViewModel.swift:26,110-114` for `ShowUndatedRemindersPreference(defaults: .standard)`. The watch's values are pushed from iOS via `SkippedReminderSyncService`.
- The only iOS-only piece is the **parent-app observation** that propagates changed prefs to the watch (`#if os(iOS)` in `SingleThread/AppViewModel.swift:81-83`, `syncService` field `:47`).

## Q3: How is the iPhone/macOS settings surface structured for these preferences?

### Findings
- `SettingsBindings` is a `@MainActor @Observable` class holding all 13 `@AppStorage`-backed preference values (`SingleThread/SettingsBindings.swift:15-16,47-59`). It mirrors the `@AppStorage` defaults from `ContentView` exactly; `excludedLists` is intentionally omitted (store-backed, not `@AppStorage`) (`:8-11`). `allowsLandscape`/`enableActionButtons` are iOS-only but declared unconditionally because `#if` isn't allowed inside a parameter list (`:9-13`).
- Bag lifecycle in `ContentView.swift`: gear action sets `settingsBag = makeSettingsBag()` then `isShowingSettings = true` (`:67-68`, recreated each open); on dismiss the bag is nilled (`:105-108`); `makeSettingsBag()` builds it from current `@AppStorage` values with `#if os(iOS)` vs `#else` variants (`:488-517`).
- `.sheet` write-back `.onChange` writes every bag value back to `@AppStorage` so settings survive relaunch: iOS-only `allowsLandscape` (`:125`)/`enableActionButtons` (`:126`); shared write-backs incl. `showDate`, `showList`, `showRecurrence`, `showAlarms` (`:121-149`).
- `SettingsView` (no owned state) is `NavigationStack { List }` with 4 `NavigationLink` rows (`SettingsView.swift:27-90`): Interface → InterfaceSettingsView (with `#if os(iOS)` split for the iOS-only props, `:32-44`); Reminder → ReminderSettingsView passing the 4 show bindings + viewModel (`:49-58`); Filtering & Sorting → FilterSortSettingsView; Background → BackgroundSettingsView. Ends with a Done toolbar button (`:84-88`) and `TextSizeModifier` (`:90`).
- `ReminderSettingsView` (`SingleThread/ReminderSettingsView.swift`) is a `Form` with four `Toggle` rows: Show date (`:18-23`), Show list (`:24-27`, **no `.onChange` hook**), Recurrence indicator (`:28-32`), Reminder alerts (`:37-41`).
- `.onChange` hooks call `viewModel.showPreferenceChanged()` for `showDate` (`:22-24`), `showRecurrence` (`:33-35`), `showAlarms` (`:42-44`) — each wrapped in `#if os(iOS) || os(macOS)`.
- `SettingsViewModel` (`SingleThread/SettingsViewModel.swift`): `showPreferenceChanged()` calls `WidgetCenter.shared.reloadAllTimelines()` (`:19-22`, gated `#if os(iOS) || os(macOS)`); `allowsLandscapeChanged(_:)` calls `AppDelegate.applyLock(allowsLandscape:)` (`:12-15`, iOS-only). `WidgetKit` imported only under the gating (`:1-3`).
- Observed asymmetries (facts): `showList`, `showMicrophoneButton`, `enableActionButtons`, `appearanceMode`, `textSize` have no widget-timeline reload hook; only 3 of 4 reminder toggles attach `showPreferenceChanged()`.

## Q4: How are display preferences propagated from iPhone to watch?

### Findings
- Sender composition: iOS `AppViewModel.init` builds `SkippedReminderSyncService(session: WCSession.default, skipStore:, showDateStore: ShowDatePreference(), showRStoreC:, showAlarmsStore:, sendsShowDate: true)` (`SingleThread/AppViewModel.swift:24-59`). The defaulted params `showListStore`, `sendsShowRecurrence`, `sendsShowAlarms`, `sendsShowList` fall back to defaults (`sendsShowList: Bool = true`, etc.) in `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:28-40`.
- `pushAll()` (`SkippedReminderSyncService.swift:133-157`) builds one combined context: always `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`, `sortOption`; then adds each show* key only if its `sends*` flag is true (showDate `:144-145`, recurrence `:147-148`, alarms `:150-151`, list `:153-154`); calls `session.updateApplicationContext(context)`.
- `PayloadKey.*` strings defined once in a private enum (`SkippedReminderSyncService.swift:222-235`): `"skip..."`-style names for `showUndatedReminders`, `sortOption`, `showDate`, `showRecurrence`, `showAlarms`, `showList`.
- Receive entry: `WCSessionDelegate.session(_:didReceiveApplicationContext:)` → `apply(context:)` (`:190-194`).
- `apply(_ context:)` (`:261-337`): for each show key decodes Bool, persists via `show*Store.set(...)`, then snapshots and invokes the hook (`onShowDateReceived` etc.) (`:284-303`).
- Watch hooks route to state: `WatchAppViewModel.setupSyncService` wires `service.onShowDateReceived = { [weak showDateState] value in Task { @MainActor in showDateState?.apply(value) } }` (`WatchAppViewModel.swift:128-130`), and parallel for recurrence/alarms/list (`:131-139`).
- Watch passes all four `sends*` flags `false` (`WatchAppViewModel.swift:115`) — watch is receive-only for display prefs.
- Phone-side trigger: toggle writes `@AppStorage` → `UserDefaults.didChangeNotification` for `AppGroup.defaults`; observer `setupSyncObservation` (`AppViewModel.swift:173-180`) hops via `Task { @MainActor }` to `handlePreferencesChanged()` (`:182`).
- `handlerPreferencesChanged` (`:182-192`) compares `ShowDatePreference()/.isEnabled` + recurrence + alarms + list against cached `lastShow*` baselines (initialized at property-declaration time, `:201-204`, so first notification doesn't spuriously push); on any diff updates baselines and calls `syncService?.pushAll()`.
- Note: the phone's `service` is constructed from the same default `AppGroup.defaults`-backed stores, so the pushed snapshot reflects what the observer detected.
- Watch display prefs persist to `.standard` (not `AppGroup.defaults`), i.e. the two devices store the prefs in different defaults domains.

## Q5: How does the watch consume and render these preferences?

### Findings
- Holder types `ShowDateState`, `ShowListState`, `ShowAlarmsState`, `ShowRecurrenceState` are each an `@Observable final class` seeding `isEnabled = preference.isEnabled` in `init` (from a `.standard`-backed `Show*Preference`) and exposing `.apply(_:)` which persists + republishes: `ShowDateState.swift:8-28` (`init:13`, `private(set) var isEnabled:19`, `apply:21-24`, backing `preference` `:28`). The other three are identical.
- Doc comments (e.g. `ShowDateState.swift:5-7`) note these replace the former `@AppStorage` read-back; updates arrive via the sync pipeline's explicit callbacks.
- Composition root `WatchAppViewModel` (`@MainActor`, `SingleThreadWatch/WatchAppViewModel.swift:5-8`) instantiates the four holders (`:28-31`) then sets up sync (`:33`); computed `reminderViewModel` passes `store` + all four by reference (`:44-51`).
- `WatchReminderViewModel` (`WatchReminderViewModel.swift:7-9`) accepts the four states in `init(store:showDateState:showRecurrenceState:showAlarmsState:showListState:)` (`:11-24`) and stores them (`:27-30`). It does **not read** the flags itself — it only carries them for the view; it owns `completionGlow` (`:33`), `isRefreshing` (`:36`), `isShowingRefreshConfirmation` (`:39`).
- `WatchReminderView.reminderDetails(_ display:)` reads each gate: due date `if showDateState.isEnabled, let due = display.dueDate` (`WatchReminderView.swift:194-197`); list name `if showListState.isEnabled, let listName` (`:199-202`); recurrence `if showRecurrenceState.isEnabled, display.hasRecurrence` (`:204-207`); alarms `if showAlarmsState.isEnabled, display.hasAlarms` (`:209-212`).
- Live update path: phone push → `service.apply` persists + fires hook → `WatchAppViewModel` handler → `showGetState.apply(value)` persists + republishes `isEnabled` → because the holders are `@Observable` and the view reads `viewModel.show*State.isEnabled`, the card re-renders.

## Q6: How are the completion-feedback and display-preference behaviors tested?

### Findings
- `CompletionGlowTests` (`@MainActor @Suite(.serialized)`, `SingleThreadTests/CompletionGlowTests.swift:13`): state-face tests `glowStartsInactive` (`:15-19`), `triggerSetsActive` (`:21-26`), `retriggerKeepsActive` (`:28-34`), `glowAutoDismissesAfterDuration` (`:36-57`, sets `duration = 0.05` and polls 100×20ms rather than a fixed deadline). Source `CompletionGlow.swift:13`.
- `CompletionGlowViewModelTests` (`:60`, also `@Suite(.serialized)`): `glowStaysInactiveWhenNothingToComplete`+`glowTriggersOnSuccessfulCompletion` (`:63-75`, builds `EKReminder` via real `EKEventStore`), `glowStaysInactiveWhenAllSkipped` (`:84-95`), fixture `InMemoryEventStore()` + `ContentViewModel(store:, backgroundImage:, speechTranscriber:)` (`:98-110`).
- Fake transcriber seam `GlowFakeTranscriber: SpeechTranscribing` returns `.authorized`/`""` (`:119-129`); mirrors private copies `ActionButtonFake` (`ActionButtonTests.swift:114`) and `MicToggleFake` (`MicrophoneToggleTests.swift:9`). Protocol defined at `SingleThread/ReminderDictation.swift:10`.
- Preference tests use `UserDefaults.standard` + UUID keys + `defer { UserDefaults.standard.removeObject(forKey:) }`: `ShowDatePreferenceTests` (incl. `missingKeyIsNotFalse` doc-inguishing nil→true from `bool(forKey:)`, `:32-40`), `ShowDatePreferenceTests`/`ShowAlarmsPreferenceTests`/`ShowRecurrencePreferenceTests` (missing→enabled), `ShowListPreferenceTests` (missing→disabled).
- SettingsView tests do structural inspection — `String(describing: view.body)` substring asserts for row labels (SettingsViewTests.swift:12-112). `SettingsViewModelTests` are no-crash smoke tests (`:6-29`), iOS/macOS gated.
- iOS sync suite `SkippedReminderSyncServiceTests` (`#if os(iOS) || os(watchOS)`, `:1`) uses `FakeSession: SkipSyncSession` (`:9-33`); asserts five-key push shape when `sendsShowDate:true` (`:76-107`); show-date receive/hooks (`:432-509`); `InMemoryEventStore` + `ReminderStore` exclusion-refresh filtering (`:397-429`).
- Watch sync suite `WatchSyncPipelineTests` (`@MainActor`, `SingleThreadWatchTests/WatchSyncPipelineTests.swift:34`) duuplicates `WatchFakeSession` (`:9-31`, cross-bundle can't import iOS fake); `pushAllFromWatchOmitsShowDate` (`:35-58`), `receiveAppliesEveryKey` (`:60-109`), absent-key no-ops (`:111-146`), relaunch-survival tests per key.
- Available seams/fixtures: `InMemoryEventStore` (`@MainActor`, `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:1-124`) — reports `.fullAccess` (`:53`), filters `!$0.incomplete` (`:72-96`), `deliverCompletionOffMain` flag (`:74-90`), `makeReminder` factory (`:115-125`); the fake transcribers; `FakeSession`/`WatchFakeSession` (both `SkipSyncSession`); UUID-keyed `UserDefaults` stores wired into the sync service via default args.

## Q7: Which surfaces consume the completion feedback, and which do not?
### Findings
- **iOS app — renders (`ContentView`)**: overlay + fade driven by `viewModel.completionGlow.isActive` (`ContentView.swift:81-87`), overlay `:467-474`.
- **macOS app — renders glow**: same `ContentView` shared on both platforms (`SingleThread/SingleThreadApp.swift:9-13`); `#if os(macOS)` only swaps the app-delegate adaptor (`:20-27`), not the view. macOS Complete action button (`ContentView.swift:212`) → `completeCurrentReminder` → `completionGlow.trigger()`. No `#if os(macOS)` guard around the overlay or on the trigger path.
- **watchOS app — renders glow**: `WatchReminderView.swift:84-90`.
- **Widget — does NOT render glow**: no reference to `CompletionGlow`/overlay anywhere in `SingleThreadWidget/NextThingWidget.swift`; the widget's timeline is static (`getTimeline`/`makeEntry`, `:47-52,54-105`); the Complete/Skip intents in the widget do not trigger a transient glow.
- **Display-preference model sharing**:
  - Widget **does** share the display-prefs model: `NextThingWidget.swift` reads `ShowDatePreference()/ShowListPreference()/ShowRecurrencePreference()/ShowAlarmsPreference()` in `makeEntry()` (`:64-67`) and gates rendering on them (`:161,166,171,177`), i.e. the same structs + `AppGroup.defaults` store.
  - macOS app `@AppStorage("showDate"/"showList"/"showRecurrence"/"showAlarms", store: AppGroup.defaults)` at `ContentView.swift:184-199` (not platform-gated), passed into `ReminderCardView` (`:319-320`); settings rows shared iOS+macOS (`.onChange` gated `#if os(iOS) || os(macOS)` in `ReminderSettingsView`).
- Build facts (`SingleThread.xcodeproj/project.pbxproj`): app target `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` w/ `MACOSX_DEPLOYMENT_TARGET = 26.5` (`:760,767`); widget target lists `macosx` but sets only `IPHONEOS_DEPLOYMENT_TARGET = 18.7` and no `MACOS`. (:993,1003,1024,1034) — so no MACOSX_DEPLOYMENT_TARGET is set, meaning a macOS widget isn't actually built as configured.

## Cross-Cutting Observations
- Two preferences families that "show/ hide content" share one storage abstraction (`Show*Preference` → `AppGroup.defaults`) but the watch mirror and widget each read via the **same struct with a different defaults domain**:
  - Watch `Show*State` uses `.standard`, not the shared group.
- The sync service (`SkippedReminderSyncService`) is the single iPhone→watch transport for both skipped-reminder ids and the four display prefs, keyed on `sends*` flags (symmetric directional; phone sends, watch receive-only for the show* prefs).
- Two UI surfaces (iOS `ContentView`, watch `WatchReminderView`) each own their own `CompletionGlow` instance rather than sharing one; both share an identical `completionGlowOverlay` (`Color.green`) definition, and both honor Reduce Motion.
- Every durable value path is exercised with an in-memory/UUID-keyed seam: `InMemoryEventStore` + fake `SpeechTranscribing` on iOS, `FakeSession`/`WatchFakeSession` (`SkipSyncSession`) on the sync tests; the actual `WCSession`/ real `EKEventStore` never reach the unit tests.

## Open Areas
- Exact file:line for a few preferences varied across agents (e.g. `ShowDatePreference.swift:10-14` vs `:20-24`); the authoritative lines were read directly by the pattern finder where quoted above.
- Whether the watch display prefs are single-source-of-truth via push vs local write is not definitively tested beyond the sync-service wiring; dual persistence (service store + `Show*State.apply`) in the same `.standard` domain is noted.
- UI tests for the completion-glow toggling flow in `SingleThreadUITests` were not requested and not inspected.
- macOS builds the glow through the shared `ContentView`; there is currently no macOS-specific glow toggle — i.e., toggling it would apply to both iOS and macOS if added at the `ContentView` level.