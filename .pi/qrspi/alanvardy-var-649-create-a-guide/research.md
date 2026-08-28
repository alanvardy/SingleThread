# Research Findings

Codebase: SingleThread — watchOS companion + iOS configurator + shared `SingleThreadCore`.
All paths relative to repo root. `file:line` references verified against source.

---

## Q1: Watch root view (`WatchReminderView`) composition

### Findings
- Entry gating: `WatchReminderView.body` switches on `viewModel.store.authorizationStatus` inside a `Group` (`WatchReminderView.swift:40-57`): `.notDetermined` → `ProgressView("Requesting access…")` (`:44-45`), `.fullAccess` → `reminderContent` (`:46-47`), anything else → access-denied `Text` (`:48-51`). The whole group gets `.task { await viewModel.task() }` (`:52-54`).
- `reminderContent` is the composited `ZStack` (`WatchReminderView.swift:58-96`):
  - Conditionally one of three content layers — `allDoneState` (`:63`, def `:100-108`), `reminderCard` (`:64`, def `:137-167`), or `noRemindersState` (`:66`, def `:110-118`).
  - On top of that, a refresh `ProgressView` when `viewModel.isRefreshing` (`:68-73`), pinned top via `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 8)`.
  - The whole `ZStack` gets `.overlay { if viewModel.completionGlow.isActive { completionGlowOverlay } }` (`:86-88`) and `.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: viewModel.completionGlow.isActive)` (`:90-94`).
- `completionGlowOverlay` (`WatchReminderView.swift:141-148`): a `Color.green.opacity(0.3)` full-screen flash — `.ignoresSafeArea()` (`:144`), `.allowsHitTesting(false)` touch passthrough (`:145`), `.accessibilityHidden(true)` (`:146`), `.transition(.opacity)` (`:147`).
- Reduce Motion: `@Environment(\.accessibilityReduceMotion) private var reduceMotion` (`WatchReminderView.swift:63`); when enabled the `.animation(...)` is `nil` (`:91`), so the glow appears/disappears instantly (no fade).
- iOS equivalent: same composition in `ContentView.swift:51-64` (ZStack) + `.overlay` glow (`:80-84`) + `.animation(reduceMotion ? nil : .easeInOut(0.4), value: ...)` (`:85-87`). The iOS `completionGlowOverlay` (`ContentView.swift:480-490`) is structurally identical but uses `.opacity(0.1)` vs watch `.0.3`, and exposes accessibility only during the glow UI test: `.accessibilityHidden(!isGlowUITesting)` (`:487`), `.accessibilityIdentifier("completionGlowOverlay")` (`:488`), `.accessibilityLabel("Completion glow")` (`:489`). The watch overlay is unconditionally hidden from the a11y tree.
- Glow driver: `CompletionGlow` (`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift:12-40`) — `@MainActor @Observable`, `isActive` flips true on `trigger()`, auto-dismisses after `duration` (default 0.25 s, injectable). Watch triggers it in `WatchReminderViewModel.swift:49-51`: `if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled { completionGlow.trigger() }`.

### Patterns
- Overlays are placed via `.overlay` on the ZStack, not as a ZStack child. Decorative full-screen overlays follow a fixed recipe: `Color` + `opacity` + `ignoresSafeArea` + `allowsHitTesting(false)` + `accessibilityHidden(true)` + `transition(.opacity)`, with fade driven by the parent `.animation(_, value:)`.

---

## Q2: Watch state-holder (`ShowXState`) + persisted preference (`ShowXPreference`)

### Findings
- The five watch state holders are byte-identical except name + paired preference: `ShowDateState`, `ShowRecurrenceState`, `ShowAlarmsState`, `ShowListState`, `ShowCompletionGlowState` (each `SingleThreadWatch/ShowXState.swift`). Shape (`ShowDateState.swift:10-21` shown, repeats at `ShowRecurrenceState.swift:10-21`, `ShowAlarmsState.swift:10-21`, `ShowListState.swift:10-21`, `ShowCompletionGlowState.swift:9-19`):
  ```
  @Observable final class ShowDateState {
      init() { isEnabled = preference.isEnabled }
      private(set) var isEnabled: Bool
      func apply(_ value: Bool) { preference.set(value); isEnabled = value }
      private let preference = ShowDatePreference(defaults: .standard)
  }
  ```
  Comment blocks state these replaced former `@AppStorage` read-backs whose observation of out-of-band UserDefaults writes is OS-version-dependent; updates now arrive through the sync pipeline's explicit `onShow*Received` callback.
- The paired preference structs all sit in `SingleThreadCore/Sources/SingleThreadCore/` and share `init(defaults: UserDefaults = AppGroup.defaults, key: String = "<...>")`, an `isEnabled` computed property reading `defaults.object(forKey: key) as? Bool ?? <default>`, and a `set(_:)` write. Default key / missing-key default:
  - `ShowDatePreference.swift:9,17,22` → key `"showDate"`, nil→`true`
  - `ShowRecurrencePreference.swift:9,17,22` → key `"showRecurrence"`, nil→`true`
  - `ShowAlarmsPreference.swift:9,17,22` → key `"showAlarms"`, nil→`true`
  - `ShowCompletionGlowPreference.swift:9,17,22` → key `"showCompletionGlow"`, nil→`true`
  - `ShowListPreference.swift:8,16,19` → key `"showList"`, nil→`false` (new feature)
  - Doc comments deliberately use `object(forKey:) as? Bool ?? default` because `bool(forKey:)` coerces a missing key to `false`, defeating the true-on-first-launch intent (e.g. `ShowDatePreference.swift:3-5`, `ShowListPreference.swift:3-6`).
- API split: the four `isEnabled`/`set` preferences vs `ShowUndatedRemindersPreference` which uses `load()`/`save()` (`ShowUndatedRemindersPreference.swift:13-24`), nil→`false` (mirrors `SortOptionStore`, documented at `:3`).
- Initialization: `WatchAppViewModel.init` builds all five state holders with default inits (`WatchAppViewModel.swift:28-32`) and stores them as `let` properties (`:40-44`), injecting them into a newly-built `WatchReminderViewModel` in the computed `reminderViewModel` property (`:48-56`). The holders read their `.standard` preference in `init()`.
- Consumption: `WatchReminderView` reads `isEnabled` to gate card fields — date (`:196`), list (`:201`), recurrence (`:206`), alarms (`:211`); `WatchReminderViewModel.swift:49` gates the glow. `ShowCompletionGlowState.isEnabled` also gates the glow in the VM.
- Sync wiring: `setupSyncService` passes each holder's paired preference with `defaults: .standard` as the service's `*Store` (`WatchAppViewModel.swift:109-114`), then `wireStateReceiveHooks(_:)` (`:151-171`) weak-captures each state and sets `onShow*Received` to `Task { @MainActor in showXState?.apply(value) }` (`:157`, `:169`, …).

### Patterns
- A `ShowXState` is an `@Observable` holder that (1) reads the current preference in `init`, (2) persists+republishes via `apply(_:)`, and (3) never observes the store directly — it is updated explicitly through sync callbacks. The paired `ShowXPreference` is a value-type wrapper over a single `object(forKey:)` read/write.

---

## Q3: `AppGroup.defaults` resolution and watch-local vs shared preferences

### Findings
- `AppGroup.swift:8` declares `suiteName = "group.app.alanvardy.SingleThread"`; `AppGroup.swift:12-14` implements `defaults` as `UserDefaults(suiteName: suiteName) ?? .standard` — a computed property evaluated on every access, falling back to `.standard` when the suite is unavailable (watchOS, unregistered simulators, previews).
- The entitlement files both register only `group.app.alanvardy.SingleThread`: `SingleThread/AppGroup.entitlements` and `SingleThread/SingleThread.entitlements` (the latter also holds audio-input + calendar permission keys). The watch target has no entitlements file, so `AppGroup.defaults` always falls through to `.standard` on watchOS.
- Preference family defaults are all `AppGroup.defaults` (Q2): `ShowDatePreference.swift:10`, `ShowRecurrencePreference.swift:10`, `ShowAlarmsPreference.swift:10`, `ShowListPreference.swift:8`, `ShowCompletionGlowPreference.swift:10`, `ShowUndatedRemindersPreference.swift:6`. Same for `SkippedReminderStore` (`ReminderSkip.swift:121-143`, default `AppGroup.defaults`, key `"skippedReminderIdentifiers"`), `ExcludedListStore.swift:6` (key `"excludedListTitles"`), `SortOptionStore` (`SortOption.swift:25`, key `SortOption.defaultsKey` = `"sortOption"`).
- iOS `@AppStorage` split in `ContentView.swift`:
  - `.standard` cosmetics (not synced): `appearanceMode` (`:144`), `textSize` (`:147`), `allowsLandscape` (iOS, `:151`), `showMicrophoneButton` (`:155`), `enableActionButtons` (iOS, `:165`), plus explicit `backgroundEnabled` (`:158`) and `backgroundFadePercent` (`:161`).
  - `AppGroup.defaults` (synced/functional): `showUndatedReminders` (`:169`), `sortOption` via `SortOption.defaultsKey` (`:172`), `showDate` (`:175`), `showList` (`:178`), `showRecurrence` (`:181`), `showAlarms` (`:183`), `showCompletionGlow` (`:186`).
- Watch writes are done explicitly to `.standard`: each `Show*State` builds `XPreference(defaults: .standard)` (`WatchAppViewModel.swift:110-114`; the holders' private preference at each state file), and `showsUndatedReminders` is restored via `.standard` (`WatchAppViewModel.swift:26`). Sort is restored via `SortOptionStore().load()` (defaults to `AppGroup.defaults`→`.standard` fallback on watch, `:23`).
- Reads/writes summary: phone persists functional prefs to `AppGroup.defaults`; watch (no suite) reads/writes the same keys on `.standard`. So the *key names* are shared but the stores differ by platform — sync (Q4) is what carries values across.

### Patterns
- Two-tier persistence: `.standard` = device-local appearance/behavior; `AppGroup.defaults` = shared functional data (skips, exclusions, sort, show-*). On watchOS the shared tier silently degrades to `.standard`.

---

## Q4: How `SkippedReminderSyncService` propagates show-\* phone→watch

### Findings
- Protocol seam: `SkipSyncSession` (`SkippedReminderSyncService.swift:8-15`) abstracts `activate`/`updateApplicationContext`/`sendMessage`; `WCSession: SkipSyncSession` (`:17`).
- `pushAll()` (`SkippedReminderSyncService.swift:146-174`) builds one latest-wins application context via `updateApplicationContext`:
  - **Unconditional:** `skippedReminderIdentifiers` (`:149`), `excludedListTitles` (`:150`), `showUndatedReminders` (`:151`), `sortOption` (`:152`).
  - **Conditional per `sends*` flag:** `showDate` (`:154-155`), `showRecurrence` (`:157-158`), `showAlarms` (`:160-161`), `showList` (`:163-164`), `showCompletionGlow` (`:166-167`). Each reads `<Preference>.isEnabled`.
- Payload keys: private enum `PayloadKey` (`SkippedReminderSyncService.swift:234-246`) with string constants `skippedReminderIdentifiers`, `excludedListTitles`, `completeReminderIdentifier`, `deleteReminderIdentifier`, `showUndatedReminders`, `sortOption`, `showDate`, `showRecurrence`, `showAlarms`, `showList`, `showCompletionGlow` — shared as one wire-format source to prevent drift.
- Receive path: `session(_:didReceiveApplicationContext:)` (`:200`) → `apply(context:)` (`:270-323`). Each present key is decode → persist (`store.save/set`) → invoke its `on*Received` hook; absent keys are no-ops. Hooks are `nonisolated(unsafe)` (`:77-141`) and snapshotted before invocation (write-once-before-`activate()` invariant).
- Interactive (watch→phone) `sendMessage` requests: `requestCompleteReminder` (`:176-182`), `requestDeleteReminder` (`:184-190`); handled in `didReceiveMessage` (`:204-211`).
- **Phone side** (`SingleThread/AppViewModel.swift`): service created only when `WCSession.isSupported() && !usesInMemoryStore` (`:27`), passing `sendsShowDate: true` (others default true) so the phone pushes **all** show flags (`:28-35`). Completes/deletes/exclusions received (`:39-51`); `service.activate()` then `syncService = service` (`:52-53`). Push hooks on the store: `onSkipSetChanged`, `onShowUndatedRemindersChanged`, `onExcludedListsChanged` → `pushAll()` (`:54-56`); `onSortOptionChanged` persists then pushes (`:67-69`). `setupSyncObservation()` (`:179-188`) registers `UserDefaults.didChangeNotification` for `object: AppGroup.defaults`; `handlePreferencesChanged()` (`:193-224`) compares the five show-* `isEnabled` against cached last-values and calls `syncService?.pushAll()` on change.
- **Watch side** (`SingleThreadWatch/WatchAppViewModel.swift`): `setupSyncService` (`:102-138`, guarded by `WCSession.isSupported()` `:104`) creates the service with **all five `sendsShow*` = `false`** (`:115-116`), so the watch *never pushes* the show flags — they are **watch-local / phone-push-only**. Watch still receives and forwards the unconditional keys, plus `onShow*Received` → state holders via `wireStateReceiveHooks` (`:151-169`).
- Direction summary:
  - watch-local / phone-pushes: `showDate`, `showRecurrence`, `showAlarms`, `showList`, `showCompletionGlow`.
  - bidirectional push: `skippedReminderIdentifiers` (both sides `pushAll` on `onSkipSetChanged`), `showUndatedReminders`, `sortOption`.
  - phone-push only: `excludedListTitles` (watch has no onExcludedListsChanged push hook).
  - interactive watch→phone: complete/delete `sendMessage` requests.

---

## Q5: iPhone Settings screen structure and preference flow

### Findings
- `SettingsView` (`SingleThread/SettingsView.swift`): owns no persisted state; holds `@Bindable SettingsBindings` + a separately-passed `excludedLists: Binding<Set<String>>`. `NavigationStack` + `List` (`:30`) with Section 1 NavigationLinks: **Interface**→`InterfaceSettingsView` (`:33-51`), **Reminder**→`ReminderSettingsView` (`:63-70`), **Filtering & Sorting**→`FilterSortSettingsView` (`:72-81`), **Background**→`BackgroundSettingsView` (`:82-91`); Section 2 has Privacy Policy + About (`:96-`). `.navigationTitle("Settings")` (`:97`), a **Done** toolbar button calling `dismiss()` (`:98-104`), `.modifier(TextSizeModifier(textSize:))` (`:106`).
- `SettingsBindings` (`SingleThread/SettingsBindings.swift:14-15`) is an `@MainActor @Observable` bag of 15 stored props (`:52-65`) mirroring ContentView `@AppStorage` defaults (`:19-50`). **`excludedLists` is NOT in the bag** — doc at `:8-12` says it is store-backed (not `@AppStorage`) and passed separately. `allowsLandscape`/`enableActionButtons` are declared unconditionally (no `#if` in a parameter list) and are inert on macOS (`:12-13`).
- `SettingsViewModel` (`SingleThread/SettingsViewModel.swift`): thin side-effect holder. `allowsLandscapeChanged(_:)` (iOS) → `AppDelegate.applyLock` (`:13-15`); `showPreferenceChanged()` (iOS/macOS) → `WidgetCenter.shared.reloadAllTimelines()` (`:21-23`).
- `ReminderSettingsView` (`SingleThread/ReminderSettingsView.swift`): `Form` of five `Toggle`s bound `$showDate` (`:16`), `$showList`, `$showRecurrence`, `$showAlarms`, `$showCompletionGlow`. Three fire `viewModel.showPreferenceChanged()` via `.onChange`: `showDate` (`:22-24`), `showRecurrence` (`:36-38`), `showAlarms` (`:46-48`). `showList`/`showCompletionGlow` have no onChange.
- `InterfaceSettingsView` (`SingleThread/InterfaceSettingsView.swift`): two `Picker`s (appearance, textSize), an iOS `allowsLandscape` Toggle with `.onChange` → `allowsLandscapeChanged` (`:44-46`), `showMicrophoneButton` Toggle, iOS `enableActionButtons` Toggle (no side effect).
- Presentation/write-back (`SingleThread/ContentView.swift`): gear button (`:57-73`) sets `settingsBag = makeSettingsBag(); isShowingSettings = true` (`:67-68`). `makeSettingsBag()` (`:499-529`) builds a fresh `SettingsBindings` from current `@AppStorage` values. The `.sheet(isPresented:)` (`:109-136`) renders `SettingsView(...)` and chains `.onChange(of: bag.X) { _, new in X = new }` for **every** bag field (`:120-135`) writing back to the `@AppStorage`-backed property. Dismiss nils `settingsBag` (`:105-107`) so a fresh bag is built next open.
- Phone→watch path for a preference toggle: (1) edit the Toggle mutates the bag binding → (2) `.onChange(of: bag.X)` in `ContentView.swift` assigns the `@AppStorage` property (persists to `AppGroup.defaults` for show-\*/sort) → (3) `AppViewModel.setupSyncObservation()` (iOS) observes `UserDefaults.didChangeNotification` on `object: AppGroup.defaults` (`AppViewModel.swift:179-188`) → (4) `handlePreferencesChanged()` sees a delta and calls `pushAll()` (`AppViewModel.swift:193-224`) → (5) `pushAll()` sends the combined context → (6) watch applies via `wireStateReceiveHooks`/`onShowUndatedRemindersReceived` etc.
- Note: `showList` and `showCompletionGlow` reach the watch via the app-context push path, not via the widget-timeline reload hook (only date/recurrence/alarms reload widgets).

---

## Q6: Watch UI-testing seam and deterministic test setup

### Findings
- Watch launch args read directly in `WatchAppViewModel.init` (`SingleThreadWatch/WatchAppViewModel.swift:14-20`): `--ui-testing` → `Self.uiTestingStore(arguments:)`, else `ReminderStore(loadsReminders: true)`.
- `uiTestingStore` (`:58-96`) builds a fixed single "Buy groceries" reminder (priority 5, notes "Don't forget the milk"). `--ui-testing-excluded-list <list>` / `--ui-testing-live-excluded <list>` give that reminder a calendar of that title and return an `InMemoryEventStore`-backed store; `excludedListTitles` is seeded `[list]` only for `--ui-testing-excluded-list` (`:80-89`). Plain path returns the single-reminder in-memory store (`:91-95`).
- `--ui-testing-live-excluded` proof seam: `scheduleUITestLiveExcludedDelivery` (`:174-221`) delivers a real `["excludedListTitles":[list]]` application context 5 s after launch (`DispatchQueue.main.asyncAfter`) via the public `service.session(_:didReceiveApplicationContext:)`.
- `UITestingSeed` (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`): parses `--seed '<json>'` (`:27-37`, schema `reminders`/`calendars`/`excludedLists`), and `resetPersistedState()` (`:41-49`) removes the `persistedKeys` list (`:49-64`) from both `AppGroup.defaults` and `UserDefaults.standard`.
- **The watch seam does NOT parse `--seed` and does NOT call `resetPersistedState()`** — only iOS `AppViewModel.makeStore` (`SingleThread/AppViewModel.swift:164-223`) calls `UITestingSeed.resetPersistedState()` on the `--seed` path (`:167-168`). iOS also handles `--reset-glow-preference` (removes `"showCompletionGlow"` key, forces `enableActionButtons` true) on the `--ui-testing` branch (`:186-190`), with an explicit comment that this leaves a persistent `.standard` value on the test simulator.
- Watch unit suites:
  - `ShowCompletionGlowStateTests.swift` — `@Suite(.serialized)` because tests write the same real `showCompletionGlow` key; manual `set/removeObject` + `defer` cleanup, no first-launch reset.
  - `WatchSyncPipelineTests.swift` — a private `WatchFakeSession: SkipSyncSession` (`:12-29`) with `activated`/`lastContext`/`pushShouldThrow`; tests use UUID-suffixed `.standard` keys to avoid collisions; several assert cross-creation persistence ("survives relaunch").
  - `WatchReminderViewRegressionTests.swift` — canvas-render regression over `ReminderDisplay` fields.
- Watch UI tests (`SingleThreadWatchUITests/`): `SingleThreadWatchUITests.swift:20-37` launches `--ui-testing` and runs `testTapRevealsConfirmationDialog`; `SingleThreadWatchUITests.swift:35-37` runs `app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` (watchOS branches). `SingleThreadWatchUITestsFlows.swift` drives the excluded-list/live-exclusion/complete/skip/delete flows via `--ui-testing` + the excluded-list flags.
- There IS **no existing first-launch/reset forced between watch UI test runs**: the watch `--ui-testing` path persists `.standard` values and nothing wipes them between launches. The only first-launch-ish resets live on the iOS `--seed` (`resetPersistedState`) and `--reset-glow-preference` paths.
- Label note: the iOS accessibility audit in `SingleThreadUITests/SingleThreadUITests.swift` narrows categories on CI (`:35-42`) — the watch audit does not have this CI branch.

---

## Q7: Gestures / touch targets on the watch reminder card

### Findings
- The watch card's **only** gesture is `onTapGesture` on the reminder `ScrollView` body (`WatchReminderView.swift:164`), which sets `viewModel.isShowingRefreshConfirmation = true` → `.confirmationDialog("Reminder", isPresented:)` (`:169-180`) exposing **Refresh** (`:172`) and **Delete** (`:176`, `role: .destructive`). The tappable region is marked `.accessibilityAddTraits(.isButton)` (`:166`).
- `actionButtons` (`WatchReminderView.swift:90-119`): an `HStack` of two persistent buttons — **Complete** (`:91-102`, `Task { await viewModel.completeCurrentReminder() }`, `.tint(.green)`, `.accessibilityLabel("Complete reminder")`) and **Skip** (`:104-112`, sync `viewModel.store.skipCurrentReminder()`, `.tint(.orange)`, `.accessibilityLabel("Skip reminder")`). Both `.accessibilityAddTraits(.isButton)`.
- **The watch card has NO swipe/gesture actions.** A repo grep for `swipe|swipeActions|DragGesture|gesture` in `SingleThreadWatch/` returns no matches. Swipe actions exist only on iOS `SingleThread/ContentView.swift:345` (`swipeActions(edge: .leading)` → Complete) and `:353` (`swipeActions(edge: .trailing)` → Skip).
- The full-screen refresh `ProgressView` (`WatchReminderView.swift:68-73`) and the completion-glow overlay (`:141-148`, `allowsHitTesting(false)` + `accessibilityHidden(true)`) both sit above the card without blocking its touch targets.
- Placement summary relevant to an overlay describing swipes: the card's interactive surface is the whole `ZStack` area — tap = dialog, bottom `HStack` = Complete/Skip buttons; there is no `.scrollContentBackground`/edge swiping on the watch card. The decorative overlay recipe (`allowsHitTesting(false)`, `accessibilityHidden(true)`) is the established way to add a non-interactive full-screen layer without blocking these targets.

---

## Cross-Cutting Observations
- **Overlay recipe** is identical phone/watch: decorative full-screen `Color` + `opacity` + `ignoresSafeArea` + `allowsHitTesting(false)` + `accessibilityHidden(true)` + `transition(.opacity)`, faded by a shared `.animation(reduceMotion ? nil : .easeInOut(0.4), value: completionGlow.isActive)`.
- **Preference idiom across the codebase**: a shared `struct XPreference`/`Store` (default `AppGroup.defaults`, injectable `defaults`/`key`, `object(forKey:) as? Bool ?? default` reads to avoid the `bool(forKey:)` false-coercion) + a platform `@Observable` holder (watch uses explicit `@Observable ShowXState`; iOS uses `@AppStorage` + `SettingsBindings` bag).
- **Single wire protocol** (WCSession application context) carries skips + exclusions + sort + show-undated + the five show-* flags; the five show-* are phone-push/watch-local (watch passes all `sendsShow*: false`).
- **Diagnostic vs functional split on disk**: `.standard` for cosmetic device-local prefs, `AppGroup.defaults` for synced functional prefs; watch falls back to `.standard` because it lacks the App Group capability.
- **Testing determinism**: watch uses a fixed single-reminder `--ui-testing` seed (no `--seed`, no reset), whereas iOS details the `--seed`/`--reset-glow-preference`/`resetPersistedState()` seams.
- Default-seeding semantics and read naming are inconsistent **across** the family intentionally: four show-* preferences default true, `showList`/`showUndatedReminders` default false, and `ShowUndatedRemindersPreference` uses `load()/save()` while the five show-* use `isEnabled/set`.

## Open Areas
- Whether `@AppStorage(store: AppGroup.defaults)` posting `didChangeNotification` on the exact suite instance always fires (iOS path relies on this; `AppViewModel` observes `object: AppGroup.defaults`). The codebase documents the intent but it was not runtime-verified here.
- The `showList`/`showCompletionGlow` changes do not call `showPreferenceChanged()` (no widget reload) yet DO reach the watch via `pushAll()` — the watch-ward path is complete, but whether a widget/local UI update is expected for these toggles is not resolved by the code.
- `SkippedReminderSyncServiceTests` references (the iOS suite) were not read in full for this research set; the watch-side `WatchSyncPipelineTests` were, and they cover the same behavior natively.