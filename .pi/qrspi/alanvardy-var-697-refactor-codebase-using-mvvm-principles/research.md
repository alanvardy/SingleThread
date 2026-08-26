# Research Findings

Repo: `alanvardy-var-697-refactor-codebase-using-mvvm-principles`
Scope: SwiftUI view layer + app-entry composition (iOS + watchOS), `SingleThreadCore` observable store, tests.

## Q1: Responsibilities inside the SwiftUI view structs

### ContentView (`SingleThread/ContentView.swift`, 635 lines)

Computed presentation state (all read-only, derive from `store`/`backgroundImage`/`@AppStorage`):
- `showsActionButtons` (iOS+gated) `:71-76` — `enableActionButtons && store.visibleReminders.first != nil`.
- `backgroundDisplayed` `:78-80` — `backgroundEnabled && backgroundImage.imageData != nil`.
- `allSkipped` `:253-255` — `!store.reminders.isEmpty && store.visibleReminders.isEmpty`.
- `canDictate` `:257-260` — reads `speechTranscriber.authorizationStatus` (Speech seam).
- Body branching on store state: `allSkipped` `:323`, empty copy `:337`, `backgroundDisplayed` `:361-362`, action-buttons gate `:445`, dictation bar `:425-447`.

Bindings built from store state:
- `excludedListsBinding: Binding<Set<String>>` `:242-251` — `get`/`set` both hit `store` (`store.excludedListTitles` / `setExcludedListTitles`); passed into the settings sheet at `:143` (iOS) and `:158` (macOS).
- `availableLists: store.availableLists` read at `:144` (iOS) / `:159` (macOS).

Dictation state + transitions (all `@State`, not in any store):
- `isDictating=false` `:235`, `dictationText=""` `:236`, `dictationError` `:237`, `creationFeedback` `:238`, `isShowingSettings` `:239`.
- Entry: mic button `:490-496` → `Task { await startDictation() }`.
- `startDictation() async` `:521-558`: `requestAuthorization()` `:557`, error writes `:525/:529`, toggles `isDictating` `:533-538`, streams transcription into `dictationText` `:538`, calls `ReminderDictationParser.parse` `:539`, then **store call** `await store.addReminder(...)` `:540-544`, sets `creationFeedback` `:548-553`, `catch`→`dictationError` `:556`.
- Render reads: `bottomBar` `:425-453` reads `dictationError`/`creationFeedback`/`isDictating`/`dictationText`/`canDictate`/`showMicrophoneButton`.

`.task` / `.onChange` side effects:
- `.task` `:111-115` — seeds `store.showsUndatedReminders`, `await store.start()`, `await backgroundImage.refreshIfNeeded(maxAge: 3600)`.
- `.onChange(of: showUndatedReminders)` `:116-119` — writes `store.showsUndatedReminders` then `Task { await store.reload() }`.
- `.onChange(of: sortOption)` `:120-122` — `store.setSortOption(newValue)`.
- `.onChange(of: appearanceMode)` `:123-128` — **AppDelegate call** `AppDelegate.applyAppearance` (iOS) / `MacAppDelegate.applyAppearance` (macOS).

Store action call sites (buttons): complete `:266/:392/:461`, skip `:278/:400/:473`, delete `:290/:383`.

Static presentation helpers living in the view:
- `emptyStateCopy(hasHidden:)` `:168-186`, `allDoneStateCopy()` `:188-193`.

### SettingsView (`SingleThread/SettingsView.swift`, 333 lines)
- Doc comment: *"Owns no state — every preference is bound back to ContentView's `@AppStorage` values."* `:58-59`; the struct owns only `@Binding`s (`:249-264`).
- `.onChange` → external services:
  - `.onChange(of: allowsLandscape)` (iOS) `:171-172` → **`AppDelegate.applyLock(allowsLandscape:)`**.
  - `.onChange(of: showDate)` `:198-199` → **`WidgetCenter.shared.reloadAllTimelines()`**.
  - `.onChange(of: showRecurrence)` `:209-210` → **`WidgetCenter.shared.reloadAllTimelines()`**.
  - `.onChange(of: showAlarms)` `:217-218` → **`WidgetCenter.shared.reloadAllTimelines()`**.
- `ExcludedListsView` (nested) builds per-list `Binding<Bool>` in `excludedBinding(for:)` `:40-50` over the parent `Binding<Set<String>>`; no store/AppDelegate calls of its own.

### WatchReminderView (`SingleThreadWatch/WatchReminderView.swift`, 309 lines)
- Computed: `allSkipped` `:78-80`; `authorizationStatus` switch `:46-54`; `reminderContent` reads `allSkipped`/`store.visibleReminders.first`/`store.reminders.isEmpty` `:84-133`; `noRemindersState` reads `store.hasHidden` `:138`.
- Store call sites: `.task { await store.start() }` `:56-57`; `store.completeCurrentReminder()` `:100`; `store.skipCurrentReminder()` `:113`; `store.deleteCurrentReminder()` `:175`; `await store.reload(clearSkipped:)` in `refresh()` `:224-230`.
- Reads the three injected state observables: `showDateState.isEnabled` `:191`, `showRecurrenceState.isEnabled` `:202`, `showAlarmsState.isEnabled` `:207`.
- **No `.onChange` and no `WidgetCenter`/`AppDelegate` calls** on the watch view — all sync is app-layer wired (`SingleThreadWatchApp`).

Note: the view→store→sync stitching is *not* in the views; it lives in `SingleThreadApp.init` / `SingleThreadWatchApp.init`.

## Q2: `ReminderStore` surface (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`, 382 lines)

- `@MainActor` `:5`, `@Observable` `:6`, `public final class ReminderStore` `:7`; single `public init(...)` `:14` (e.g. tests inject store/state; production accepts defaults).
- Owns three `private` injected persistence stores (docs say it "never reads/writes" outside them): `eventStore: any EventKitStoring` `:373`, `skipStore` `:374`, `excludeStore` `:375`.

### Pure state views bind to (read on the `ContentView`/`WatchReminderView`)
- `private(set) var reminders: [EKReminder]` `:39`, `skippedIDs: Set<String>` `:40`, `excludedListTitles: Set<String>` `:41`, `hasHidden = false` `:46`, `availableLists` `:48`, `authorizationStatus` `:49`; `let loadsReminders: Bool` `:50`.
- `var sortOption` (direct-assignable) `:54` — docs note a direct write does **not** fire hooks (`:56-58`).
- `showsUndatedReminders` with `didSet` firing `onShowUndatedRemindersChanged` `:92-97`.
- Computed: `visibleReminders` `:99-107` (filters skipped + excluded, sorts via `ReminderSort`); `hasHiddenFor(shown:allIncomplete:)` static `:109-112`.

Mutating methods (each fires one or more hooks):
- `start() async` `:117-129` — guards `loadsReminders`, `requestAccess()` vs `reload()`. Call from `.task`.
- `completeReminder(identifier:)` `:133-148`; `completeCurrentReminder()` `:150-152`; `deleteReminder(identifier:)` `:160-174`; `deleteCurrentReminder()` `:176-178`; `addReminder(title:notes:dueDate:recurrenceRule:)` `:186-209` (`@discardableResult`, `Bool`); `skipCurrentReminder()` `:211-219` (fire-and-forget `Task`); `skipCurrentReminderImmediately()` `:236-241` (widget intent, no settle sleep); `setSortOption(_:)` `:222-226` (fires `onSortOptionChanged` + `onRemindersChanged` only on change).
- `reload(clearSkipped:) async` `:243-301` — the primary fetch/persist/hook entry; computes `hasHidden` `:267/:276`, persists skip set and fires `onSkipSetChanged?([])` on `clearSkipped` `:288-289`, always fires `onRemindersChanged?()` `:299`.
- `setExcludedListTitles(_:)` `:304-310` fires `onExcludedListsChanged` + `onRemindersChanged`; `refreshExcludedListTitles(_:)` `:316-323` does **not** fire `onExcludedListsChanged` (receive-path no-echo).
- Internal/private: `requestAccess()` `:325-330`; static `eventKitSettleDelay = 200_000_000` `:343`; `updatedSkipSet` `:353-358`; `applySkipSet` `:361-368`; `fetchReminders` `:371-383`.

Closure hooks (all optional, wired by app layer, nil by default):
- `onSortOptionChanged ((SortOption)->Void)?` `:58`; `onSkipSetChanged (([String])->Void)?` `:62`; `onExcludedListsChanged (([String])->Void)?` `:67`; `onCompleteReminder ((String)->Void)?` `:72`; `onDeleteReminder ((String)->Void)?` `:77`; `onRemindersChanged (()->Void)?` `:82`; `onShowUndatedRemindersChanged ((Bool)->Void)?` `:86`.

Deliberately not touched (per docs / code):
- Reads/writes neither `UserDefaults` nor Connectivity directly — persistence/Connectivity wiring is exclusively the app-layer hooks' job (`:56-58`).
- The receive-side `refreshExcludedListTitles` "never echoes a push" (`:316-323`).
- watchOS write methods deliberately don't touch EventKit at all (see Q4).

## Q3: Preference persistence + threading into views

Two suites (`SingleThreadCore/.../AppGroup.swift`):
- `AppGroup.suiteName = "group.app.alanvardy.SingleThread"` `:11`; `AppGroup.defaults = UserDefaults(suite:) ?? .standard` `:17` (falls back to `.standard` on watchOS/unregistered simulators/previews).

`@AppStorage` keys in `ContentView`:
- `.standard` suite — `appearanceMode` `:193`, `textSize` `:196`, `allowsLandscape` (iOS) `:200`, `showMicrophoneButton` `:204`, `backgroundEnabled` `:207`, `backgroundFadePercent` `:210`, `enableActionButtons` (iOS) `:214`.
- `AppGroup.defaults` suite — `showUndatedReminders` `:218`, `SortOption.defaultsKey="sortOption"` `:221`, `showDate` `:224`, `showList` `:227`, `showRecurrence` `:230`, `showAlarms` `:232`.
- `SingleThreadApp` holds a *duplicate* of `showDate`/`showRecurrence`/`showAlarms` (same `AppGroup.defaults` keys) `:111-118` so the App-level `.onChange` can observe sync writes.

Typed preference stores (Core) read the same keys: `ShowDatePreference` defaults to `AppGroup.defaults`, key `"showDate"`, missing→`true` (`ShowDatePreference.swift:10-17`); `ShowRecurrencePreference`/`ShowAlarmsPreference`/`ShowListPreference` mirror it; `SortOption` defaults (`SortOption.swift:18,25`).

Bindings into SettingsView: it owns no state (`SettingsView.swift:58-59`); reads 14 iOS `@Binding` props `:249-277`. ContentView feeds all of them as `$` from its `@AppStorage` in the `.sheet` (`ContentView.swift:139-167`; `excludedListSets` passed as derived `excludedListsBinding`).

`.onChange` reaction graph:
| Trigger | Reaction | Location |
|---|---|---|
| `showUndatedReminders` | `store.showsUndatedReminders = value` + `await store.reload()` | `ContentView.swift:116-119` |
| `sortOption` | `store.setSortOption` | `ContentView.swift:120-122` |
| `appearanceMode` | `AppDelegate.applyAppearance` / `MacAppDelegate` | `ContentView.swift:123-128` |
| `allowsLandscape` | `AppDelegate.setLock` | `SettingsView.swift:171-172` |
| `showDate` | `WidgetCenter.reloadAllTimelines()` | `SettingsView.swift:198-199` |
| `showRecurrence` | `WidgetCenter.reloadAllTimelines()` | `SettingsView.swift:209-210` |
| `showAlarms` | `WidgetCenter.reloadAllTimelines()` | `SettingsView.swift:217-218` |
| `showDate`/`showRecurrence`/`showAlarms` | `syncService?.pushAll()` | `SingleThreadApp.swift:83-93` |
| store mutations | `store.onRemindersChanged = reloadAllTimelines` | `SingleThreadApp.swift:69-72` |

So: `UserDefaults` (.standard vs AppGroup.defaults), the preferences themselves are persisted by `@AppStorage`; the sync push is triggered by app-scope `.onChange` (`SingleThreadApp:83-93`) and the store hooks.

## Q4: Watch vs iOS — shared vs duplicated state handling

Three watch-only `@Observable` classes (in `SingleThreadWatch/`): ShowDate/ShowRecurrence/ShowAlarmsState, structurally identical.
- `@Observable final class ShowDateState` `ShowDateState.swift:9`; wraps `ShowDatePreference(defaults: .standard)` `:28` (note: **`.standard`, not AppGroup**, unlike iOS).
- `init()` reads `isEnabled = preference.isEnabled` `:12-14`; `private(set) var isEnabled: Bool` `:18`; `apply(_:)` persists + publishes `:22-26`.
- Doc rationale (`:4-7`): replaces a former `@AppStorage("showDate")` read-back whose observation of out-of-band `UserDefaults` writes is OS-version-dependent; updates now arrive via `onShowDateReceived`.

`#if os(watchOS)` branches inside shared `ReminderStore` (4 sites):
- `reload()` skips `eventStore.refreshSourcesIfNecessary()` on watch `:246-247`.
- `completeReminder` — watch: local remove + `onCompleteReminder?(id)` `:134-136`; iPhone: `eventStore.save` + settle + `reload()` `:137-146`.
- `deleteReminder` — watch: local remove + `onDeleteReminder?(id)` `:161-163`; iPhone: EventKit remove + reload `:164-172`.
- `addReminder` — watch: returns `false` (read-only) `:191`; iPhone: saves + reloads, returns `true` `:192-208`.
- `skipCurrentReminder` has **no** branch — identical both platforms (skip list stored client-side; only the phone talks to EventKit).
- Docs describe these as deliberate: "watch mutations don't touch EventKit; they mutate in-memory and relay via hooks" (`:36-47` hooks).

### Sync directionality (divergence)
- iPhone: sets `ShowDate/Recurrence/AlarmsPreference` with AppGroup defaults + `sendsShowDate:true` (`SingleThreadApp.swift:30-33`); wires **receive** handlers for `onCompleteReminderReceived`/`onDeleteReminderReceived`/`onExcludedListTitlesReceived` before `activate()` (`:39-49`); `onShowUndatedRemindersChanged`→`pushAll` (`:53`); show-date/watch relays via `.onChange`+`pushAll` (`:83-93`).
- Watch: service built with `.standard` preference stores and `sendsShowDate/Recurrence/Alarms: false` (receive-only) (`SingleThreadWatchApp.swift:30-33`); wires **receive** handlers `onShowUndatedRemindersReceived`, `onSkippedIdentifiersReceived`, `onShowDateReceived`→`showDateState.apply`, `onShowRecurrenceReceived`/`onShowAlarmsReceived`, `onSortOptionReceived`, `onExcludedListTitlesReceived` (`:34-54`); `activate()` `:57`; send side only `store.onSkipSetChanged`→`pushAll` `:57`, `onCompleteReminder`→`requestCompleteReminder` `:58-60`, `onDeleteReminder`→`requestDeleteReminder` (`:60-62`).
- The watch app does **not** store service/session as properties — service lives in the `if WCSession.exists()` scope of `init`.
- `SkippedReminderSyncService` (Core) `pushAll()` snapshots via injected stores menu: `skipStore`, `excludeStore`, `sortStore`, `showUndatedStore`, `showDate/Recurrence/AlarmsStore` (`SkippedReminderSyncService.swift:126-145`); receive path per-key decode → persist/hook (handler section `:259-287`).

### Rendering divergence
- iPhone renders via `ReminderList`/`WatchReminderView? No — iOS `ReminderStore` computed state + `ReminderCardView`. Watch builds its own `WatchReminderView` with `authorizationStatus` gating `:46-54`, min-display refresh via `MinimumDisplayDuration` `:63-63{,65}`, and reads the three `Show*State` objects.
- iOS renders the same three flags from `@AppStorage` converted to plain `Bool`s passed into `ReminderCardView`; watch uses the `...State` observable objects.

## Q5: App-entry point composition

### `SingleThread/SingleThreadApp.swift`
- `@main struct SingleThreadApp: App` `:14`; all wiring in `init()` `:17-78`.
- Store creation via private factory `Self.makeStore(arguments:)` (lines 132-176):
  - `--seed '<json>'` (`:133-149`): `UITestingSeed.fromLaunchArguments` `:135`, `resetWell` `:136`, `InMemoryEventStore` `:137-140`, `ReminderStore(eventStore:loadsReminders:true)` `:141-143`, applies excluded titles `:146-148`.
  - `--ui-testing` (`:150-166`): sets `UserDefaults.standard` `"enableActionButtons"` :true `:158`, builds an `EKEventStore`+`EKReminder` "Buy groceries" `:159-163`, `ReminderStore(loadsReminders:false, reminders:, authorizationStatus:.fullAccess)` `, returns `(store, false)` with in-memory `:166`.
  - default (`:168-172`): `loadsReminders` = `!--(--ui-testing)`/`--no-reminders`, `ReminderStore(loadsReminders:)`, `(store,false)`.
- `store.sortOption = SortOptionStore().load()` (direct, no hook) `:20`.
- **Created inline in `init`**: the `SkippedReminderSyncService` + its stores within `#if os(iOS)` guarded by `WCSession.isSupported()` `:24-63`; `BackgroundImageStore()` `:74`; the `WidgetCenter.reloadAllTimelines` hook via `store.onRemindersChanged` `:70-72`.
- Owned as `@main`-struct stored properties: `store` `:104`, `usesInMemoryStore` `:106`, `backgroundImage` `:122`, `syncService` `:111` (optional, nil when not interacting).
- `@UIApplicationDelegateAdaptor(AppDelegate.self)` `:101` / `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` (watchOS) `:107`.

### `SingleThreadWatch/SingleThreadWatchApp.swift`
- `@main struct SingleThreadWatchApp: App`; `init()` `:10-72`; store from `uiTestingStore(arguments:)` for `--ui-testing`, else `ReminderStore(loadsReminders:true)` `:12-18`; restores `sortOption` `:21` and `showsUndatedReminders` `:24`.
- Sync service built with `.standard` preference stores, `sendsShow*: false` `:30-36`; receive hooks `:39-53`; `activate()` `:56`; send hooks `:57-62`.
- `--ui-testing-live-excluded` seam `:64-72` — async delivers a real `applicationContext` through the session delegate.
- Owned stored state: `showDateState`/`showRecurrenceState`/`showAlarmsState` + `store` `:88-100`.
- body composes `WatchReminderView(store:showDateState:...)` `:83-85`.

### Test seams
- iPhone `--seed` uses `UITestingSeed` (/InMemoryEventStore) for deterministic write-flow UI tests; `--ui-testing` fakes a single reminder + toggles `enableActionButtons` to avoid the Reminders TCC prompt.
- Watch `--ui-testing`/`--ui-testing-excluded-list`/`--ui-testing-live-excluded`.

## Q6: Previews + tests around store / view-computed logic

### ContentView `#Preview`s (`ContentView.swift:563-651`)
Six previews, all inject pre-seeded state rather than a live store:
- "Empty" `:589-597`, "Nothing Due" `:595-601` (hasHidden), "With Reminder" `:604-611`, "All Skipped" `:612-618` (`skippedIDs`), "All Excluded" (`excludedListTitles`) `:620-627`, "No Access" `:629-636`.
- Mock reminders `mockReinder` "Buy groceries"/`mockCalReinder` "Buy milk" `:563-588`.

### Unit tests
Store predicates (`ReminderStoreTests.swift`) — pure Core, no view: `hasHidden`/`hasHiddenFor` seeding and truth-table tests `:412-441`; `visibleReminders`/`reload`/`complete`/`skip` mutation tests `:443+`.
View-computed logic (no render):
- `SingleThreadTests.swift` reads `view.body` and static funcs: `contentViewInitializesWithoutReminders` `:10`, `bodyContainsRefreshableModifier` `:18`, `contentViewEmptyStatesShowDistinctCopy(call emptyStateCopy(:))` `:26`, `contentViewAllDoneShowsAllDoneCopy` `:40`.
- `ActionButtonTests.swift` verifies `ContentView.visible` state selection `showsActionButtons` directly on an un-rendered `ContentView` `:57/:68/:85/:106`.
- `BackgroundCardTests.swift` — `backgroundDisplayed` `:42-45`, regression `imageSurvivesContentViewRecreation` `:71`.
- `MicrophoneToggleTests.swift` — `ContentView` with `Fake`Transcriber`, assert body strings `:35-88`.
- `ReminderDictationTests.swift` `:170-197` — `ContentView` + `FakeTranscriber`.
- `ReminderDictationParserTests.swift` — entirely `ReminderDictationParser.parse(...)` (Core-only) → all pass free of the view.
- Other pure-Core suites that keep passing regardless: `ShowDate/Repeat/ShowAlarms`, `ShowDatePreference` etc., `SettingsViewTests`, `AppearanceModeTests`, `SortOptionTests`, `TextSizeTests`, `SkippedReminderSyncServiceTests`, `EventKitStoringTests`, `UITestingSeedTests`, `ReminderSkipTests`, `TranscriptionAccumulatorTests`, `ReminderIntentsTests`, `ExcludedListStoreTests`, `ResumptionGateTests`.

UI tests (`SingleThreadUITests/`) — drive the real app via launch args:
- `SingleThreadUITestsFlows.swift` (use `--seed`): `:37,:43,:48,:60,:71,:82,:91,:102,:114` (list/skip/complete/delete/settings/background).
- `ActionButtonsUITests.swift` (`--ui-testing`): `:27`, `:47`.
- `SingleThreadUITestsLaunchTests` `:23`, `SingleThreadUITestsAppearanceLaunchTests` `:24/:51/:84`, `SingleThreadUITests.accessibility audit` `:24`.
- UI tests assert rendered copy ("No Reminders"/"All Done") and the Complete/Skip cluster, so moving presentation text/state out of the views must keep those exact accessible labels in the rendered tree.

## Cross-Cutting Observations
- **Central data flow**: Views never write persisted state directly — all mutations go through `ReminderStore` methods, and all sync transport flows come from store hooks / app initiates.
- **Three sync triggers collide on the same store hooks**: store mutation hooks (`ReminderStore`), `@AppStorage`.onChange in the App, and scene-scope `.onChange` in `SingleThreadApp` all converge on `service.pushAll()` and `WidgetCenter.reloadAllTimelines()`.
- **Preference duplication**: the show-date/recurrence/alarms flags are persisted in `AppGroup.defaults` (shared with the widget), but the *watch* reads them from a `.standard`-backed preference + `@Observable` holder — a suite/mechanism divergence between targets.
- View-computed presentation logic is already partly static/readable (`emptyStateCopy`, `showsActionButtons`, `backgroundDisplayed`) — most existing tests target these without rendering the body, so they are stable seams for any move of presentation state.
- **Concurrency**: iOS/watchOS app targets enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide; the Core package target does not, so `ReminderStore` opts in via explicit `@MainActor`.

## Open Areas
- The `#Preview`/test seam builds `ContentView`/store with injectable `BackgroundImageStore` and preset segments, but script .network/browser calls (dictation TCC, actual `EKEventStore` live writes) are only unit-tested, not UI-tested — because they can't be driven without real permissions.
- Whether `ContentView`'s `.sheet` thereof or a first-class `SettingsViewModel` would be needed (the sheet already owns no state; binding counts is complete).
- Whether `showUndatedRemindersReload` (which triggers a `reload()` on every toggle change) is intentionally synchronous-per-toggle is unverified beyond the single onChange site.
- Precise prior-checkground of the `--ui-testing-live-excluded` spectrum of test/`SingleThreadWatchUITests` details not fully documented (only that a live exclusion context is delivered after 5s).