# Research Findings

## Path notes
- Real iOS view path is `SingleThread/ContentView.swift` (566 lines). There is **no** `SingleThread/SingleThread/ContentView.swift` — a repo-wide search returns only `./SingleThread/ContentView.swift`.
- Core package files live under `SingleThreadCore/Sources/SingleThreadCore/`.
- Watch app sources under `SingleThreadWatch/`; widget under `SingleThreadWidget/`.

---

## Q1: iPhone bottom bar composition in `ContentView.swift`

### Findings
- **`body`** (`ContentView.swift:49-117`) is a `ZStack { Color.systemBackground...; if store.loadsReminders { authGatedContent } else { reminderList } }`. It has an `.overlay(alignment: .topTrailing)` gear `Button { isShowingSettings = true }` (`:58-63`) with `.accessibilityLabel("Settings")`, and `.sheet(isPresented: $isShowingSettings)` (`:98-117`) hosting `SettingsView`.
- **`reminderList`** (`ContentView.swift:278`) runs inside `GeometryReader { geometry in ... }` which computes `viewHeight = geometry.size.height - safeAreaInsets.top - safeAreaInsets.bottom` (`:280-282`). It has **three branches**:
  1. **`if allSkipped` (`:283-290`)** — a bare `ScrollView` showing `allDoneStateCopy()` ("All Done" / `checkmark.circle`, "Pull to refresh…"), `.refreshable { await store.reload(clearSkipped: true) }`. **No bottom bar, no mic button** in this branch.
  2. **`else if store.reminders.isEmpty`** (`:297-311`) — `ZStack(alignment: .bottom) { ScrollView(emptyCopy…); bottomBar }`. `emptyStateCopy(store.hasHidden)` (`ContentView.swift:133-157`) picks "Nothing due" (`calendar`) vs "No Reminders" (`checklist`). Contains `bottomBar` (`:310`).
  3. **`else` has-reminder** (`:312-363`) — `ZStack(alignment: .bottom) { List { if let reminder = store.visibleReminders.first { ReminderCardView(...) } } ; bottomBar }`. The `List` adds iOS `.contextMenu` (View in Reminders / Delete), `.swipeActions(edge:.leading)` (Complete), `.swipeActions(edge:.trailing)` (Skip), and `.refreshable { await store.reload() }`. Contains `bottomBar` (`:363`).
- **`bottomBar`** (`ContentView.swift:369-399`) is a `VStack(spacing: 8) { ... }.padding(.bottom, 16)` with children, in order:
  1. `#if os(macOS) if store.visibleReminders.first != nil { actionButtons }` (`:373`) — macOS-only action row.
  2. `if let error = dictationError { Text(error).font(.caption).foregroundStyle(.red)... }` (`:376`).
  3. `if let feedback = creationFeedback { creationFeedbackView(for:) }` (`:383`), **else** `if isDictating { if !dictationText.isEmpty { Text(dictationText)... }; recordingIndicator }` (`:385-393`), **else if canDictate, showMicrophoneButton { micButton }` (`:394-395`).
- **`micButton`** (`ContentView.swift:403-417`): `Button { Task { await startDictation() } }` with `Image(systemName: "mic.fill").font(.title2).foregroundStyle(.white).frame(width:56,height:56).background(.blue, in: Circle()).shadow(radius:4)`, `.accessibilityLabel("Dictate reminder")`, `.accessibilityAddTraits(.isButton)`.
- **Recording indicator** (`:418-427`): `Image("mic.fill")` on a `.red` circle with `.symbolEffect(.pulse, options: .repeating)`, `.accessibilityLabel("Recording")`.
- **`creationFeedbackView`** (`:429-439`): `Image(feedback.systemImage)` on `feedback.backgroundColor` circle; `CreationFeedback` enum (`.success`→`checkmark`/`.green`/"Task created", `.failure`→`xmark`/`.red`/"Task creation failed", `ContentView.swift:60-110`).
- **State driving the bottom bar** (`ContentView.swift:184-219`, `ContentView.swift:125-127`):
  - `@AppStorage("showMicrophoneButton") private var showMicrophoneButton = true` (`:184-185`).
  - `@State private var isDictating = false` (`:195`), `@State private var dictationText = ""` (`:196`), `@State private var dictationError: String?` (`:197`), `@State private var creationFeedback: CreationFeedback?` (`:198`).
  - `allSkipped { !store.reminders.isEmpty && store.visibleReminders.isEmpty }` (`:213-215`).
  - `canDictate { speechTranscriber.authorizationStatus == .authorized || == .notDetermined }` (`:217-220`).
  - `isShowingSettings` (`:199`) toggles the settings sheet.
- **Positioning**: in the two non-all-skipped branches the `bottomBar` sits inside `ZStack(alignment: .bottom)` with the scrolling `ScrollView`/`List` — so it is **pinned to the bottom edge of the safe area** (below the scroll region), not part of the scroll content.

---

## Q2: Watch action buttons vs macOS/iOS actions

### Findings
- **`WatchReminderView.swift`** (`SingleThreadWatch/WatchReminderView.swift`) — `actionButtons` defined at `:85-98`, rendered in `reminderCard` (`:154-159`) inside a `VStack(alignment:.leading)` below the `ScrollView` and its `.confirmationDialog` (Refresh / Delete). Two buttons in an `HStack`:
  - **Complete** (`:88-94`): `Task { await store.completeCurrentReminder() }`, `Label("Complete", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)`, `.tint(.green)`, `.accessibilityLabel("Complete reminder")`, `.accessibilityAddTraits(.isButton)`.
  - **Skip** (`:95-101`): `store.skipCurrentReminder()` (sync), `Label("Skip", systemImage: "circle.slash").labelStyle(.iconOnly)`, `.tint(.orange)`, `.accessibilityLabel("Skip reminder")`, `.accessibilityAddTraits(.isButton)`.
  - Watch Delete lives in the `confirmationDialog("Reminder", ...)` (`:150-157`) as `Button("Delete", role:.destructive) { Task { await store.deleteCurrentReminder() } }`.
- **macOS `actionButtons`** (`ContentView.swift:223-240`): `HStack(spacing: 32)` with **Complete** (`.tint(.green)`, `keyboardShortcut("c")`, `.accessibilityLabel("Complete reminder")`), **Skip** (`store.skipCurrentReminder()`, `.tint(.orange)`, `keyboardShortcut("s")`), **Delete** (`.tint(.red)`, `keyboardShortcut("d")`). All three are `Label(...).labelStyle(.iconOnly).font(.title)`. Same icon names (`checkmark.circle.fill`, `circle.slash`, `trash`).
- **iOS swipe/context actions** (in `ContentView.swift:320-360`, the else-List branch): `.swipeActions(edge:.leading)` Complete button (`.tint(.green)`, label `checkmark.circle.fill`); `.swipeActions(edge:.trailing)` Skip button (`.tint(.orange)`, label `circle.slash`); `.contextMenu` has "View in Reminders" (`ReminderDeepLink.url(...)`, `ContentView.swift:322-329`) and "Delete" (`.tint(.red)`, label `trash`). Each wraps the store call the same way: complete/delete via `Task { await store.*CurrentReminder() }`, skip synchronously.
- **Widget** (`SingleThreadWidget/NextThingWidget.swift`) — a third action-button surface with the **same shared pattern**: `HStack(spacing:12)` Complete/Skip `Label(...).labelStyle(.iconOnly)` on `.tint(.green)`/`.tint(.orange)`, but issued as **`Button(intent:)`** — `CompleteReminderIntent()` / `SkipReminderIntent()` (`:82-106`). `ReminderIntents.swift` shows those Intents each build their own `ReminderStore(loadsReminders:true)`, `setSortOption(...)`, `reload()`, then call `completeCurrentReminder()` / `skipCurrentReminderImmediately()` (`ReminderIntents.swift:12-21`,`:33-42`).
- **Shared visual/label pattern across all three**: Complete = `checkmark.circle.fill` + `.tint(.green)`; Skip = `circle.slash` + `.tint(.orange)`; Delete = `trash` + `.tint(.red)`. All buttons are `.labelStyle(.iconOnly)` with an explicit `.accessibilityLabel(...reminder)` and `.accessibilityAddTraits(.isButton)`. Complete/Delete wrap through `Task { await store.*Current() }`; Skip is always synchronous.

---

## Q3: Settings menu structure & toggle wiring

### Findings
- **`SettingsView`** (`SingleThread/SettingsView.swift:60-187`) is a modal `NavigationStack { Form { ... } }` with Pickers for **Appearance**, **Text Size**, **Sort By** (`:98-113`), iOS-only `Toggle` "Allow Landscape" (`allowsLandscape`) wired to `AppDelegate.applyLock` onChange (`:114-120`), then `Toggle`s **Show Microphone**, **Show Undated**, **Show Date** (`:121-126`), plus an `onChange(of: showDate)` that also calls `WidgetCenter.shared.reloadAllTimelines()` on iOS/macOS (`:127-132`). A `NavigationLink` pushes **`ExcludedProjectsView`** (`:134-138`).
- **`ExcludedProjectsView`** (`SettingsView.swift:12-55`): a pushed `Form { Section { ForEach(availableProjects) { Toggle(isOn: excludedBinding(for:)) } } }`, with `.navigationTitle("Excluded Projects")`; each per-project `Toggle` is a derived `Binding<Bool>` (`excludedBinding`, `:47-57`, `@Binding private var excludedProjects`).
- **Declarations**: `SettingsView` owns **no state** — every preference is a `@Binding` (`:174-187`): `appearanceMode`, `textSize`, `sortOption`, iOS `allowsLandscape`, `showMicrophoneButton`, `showUndatedReminders`, `excludedProjects`, `showDate`. Dismissal via `@Environment(\.dismiss) private var dismiss` + `ToolbarItem(.confirmationAction) { Button("Done") { dismiss() } }` (`:171-173`, `:62-68`).
- **ContentView call site** — `.sheet(isPresented: $isShowingSettings) { SettingsView(appearanceMode: $appearanceMode, textSize: $textSize[, allowsLandscape: $allowsLandscape], showMicrophoneButton: $showMicButton, showAgCategory: ...) ) } (`ContentView.swift:98-117`). All passed as `$` bindings that reference `ContentView`'s `@AppStorage`/`@State`/`@Binding` fields.
- **Persistence split** (in `ContentView.swift`):
  - `@AppStorage("showMicrophoneButton")` (`:184-185`) → default **app-standard** UserDefaults.
  - `@AppStorage("allowsLandscape")` (iOS, `:182-183`) → standard.
  - `@AppStorage("showUndatedReminders", store: AppGroup.defaults)` (`:186-187`) → **App Group** persistence.
  - `@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)` (`:188-189`).
  - `@AppStorage("showDate", store: AppGroup.defaults)` (`:190-191`).
  - `excludedProjectsBinding` (`ContentView.swift:210-214`) → not `@AppStorage`; a `Binding` get/set routed to `store.excludedProjectTitles`.
- **`.standard` vs `AppGroup.defaults`** (`AppGroup.swift:1-15`): `AppGroup.defaults = UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`. `.standard` is the app + native UserDefaults; `AppGroup.defaults` is the **shared App Group store** (with `.standard` fallback when the group is unavailable — watchOS, unregistered simulators, previews). Settings tied to a shared sibling device (sort, show-undated, show date, excluded projects) persist via `AppGroup.defaults`; device-local appearance (mic toggle, allows-landscape) use `.standard`.
- **Open/dismiss flow**: gear overlay Button sets `isShowingSettings = true` → `.sheet(isPresented:)` presents `SettingsView`; the sheet's `Done` → `dismiss()` (@Environment) closes it. `@State isShowingSettings` resets automatically when the sheet is dismissed.

---

## Q4: `ReminderStore` current-reminder action methods

### Findings
- Class `@MainActor @Observable public final class ReminderStore` (`ReminderStore.swift:5-6`). Two inits: production (`:8-17`, injectable `eventStore: EventKitStoring`, `skipStore`, `excludeStore`) and preview/test `init(loadsReminders:false, reminders:, skippedIDs:, authorizationStatus:)` that **never touches EventKit** (`:19-35`).
- **Store state** (`ReminderStore.swift:37-75`): `reminders`, `skippedIDs`, `excludedProjectTitles`, `hasHidden`, `availableProjects`, `authorizationStatus`, `sortOption`, plus callbacks `onSortOptionChanged`, `onSkipSetChanged`, `onExcludedProjectsChanged`, `onCompleteReminder`, `onDeleteReminder`, `onRemindersChanged`, `onShowUndatedRemindersChanged`.
- **`visibleReminders`** (computed, `:105-107`): `reminders.filter { !skippedIDs.contains(identifier) }.filter { !excludedProjectTitles.contains(calendarTitle) }.sorted(using sortOption)`. The "current" reminder is `visibleReminders.first`.
- **`completeCurrentReminder()`** (`:157-160`): `async`, guards `visibleReminders.first` → `await completeReminder(identifier:)`. **`completeReminder(identifier)`** (`:141-168`): on **iOS** marks `isCompleted = true`, `eventStore.save(commit:true)`, `try? await Task.sleep(eventKitSettleDelay)` (NilValue 200ms, `:341`... `eventKitSettleDelay`), `reload()`; on **watchOS** (read-only) it removes locally and calls `onCompleteReminder?(identifier)` to relay to iPhone.
- **`deleteCurrentReminder()`** (`:184-187`), `async` → **`deleteReminder(id)`** (`:174-193`): iOS removes object + `save(commit:true)`, settles, reloads; watchOS removes locally + `onDeleteReminder?(identifier)`.
- **`skipCurrentReminder()`** (`:219-236`, **sync**): guards `visibleReminders.first`, computes `updated = updatedSkipSet(afterSkipping: id)`, then **spawns `Task { sleep(eventKitSettleDelay); applySkipSet(updated) }`** — the persisted skip write happens after settling.
- **`skipCurrentReminderImmediately()`** (`:239-248`, **sync**): guards, computes the skip update, calls `applySkipSet(updated)` **synchronously and returns `Bool`**. Exists for the widget's `SkipReminderIntent`, whose WidgetKit process may be suspended right after `perform()` (the settle sleep is unsafe there).
- **`updatedSkipSet`** (`:352-354`): `ReminderSkipLogic.skipping(identifier, fetched: reminders.map(\.calendarItemIdentifier), skipped: Array(skippedIDs))`.
- **`applySkipSet`** (`:360-365`): `skippedIDs = Set(updated); skipStore.save(updated); onSkipSetChanged?(updated); onRemindersChanged?()`.
- **`reload(clearSkipped:false)`** (`:251-318`): `guard loadsReminders`, fetches via EventKit predicate (narrow/in-window or broad based on `showsUndatedReminders`), sets `reminders`, `availableProjects`; if `clearSkipped` → `skipStore.save([])` + `onSkipSetChanged?([])`; else loads `skipStore.load()`, runs `ReminderSkipLogic.resolve(fetched, skipped)` to prune stale IDs, saves the pruned list, sets `skippedIDs` (and `excludedProjectTitles`), then `onRemindersChanged?()`.
- **Communication to the rest of the app** (wired at the entry point `SingleThreadApp.swift:22-40`):
  - iOS app wires `store.onRemindersChanged = { WidgetCenter.shared.reloadAllTimelines() }` (iOS+macOS, `SingleThreadApp.swift:358-36`) and `store.onSkipSetChanged` → `service.push(...)` over WatchConnectivity; `onShowUndatedRemindersChanged`, `onExcludedProjectsChanged`, `onSortOptionChanged`, `onDeleteReminder` similarly relay; `onCompleteReminder`/`onDeleteReminder` relay watch→phone.
  - Watch wiring parallel in `SingleThreadWatchApp.swift:32-41`.

---

## Q5: Skipped-identifier persistence & phone/watch/widget sync

### Findings
- **`SkippedReminderStore`** (`ReminderSkip.swift:111-133`): `init(defaults: UserDefaults = AppGroup.defaults, key: String = "skippedReminderIdentifiers")`; `load() { defaults.stringArray(forKey: key) ?? [] }` (`:121-123`), `save(ids) { defaults.set(ids, forKey: key) }` (`:125-127`). This is **the storage key/backing in `UserDefaults`** — the skip list is a `[String]` of `EKReminder.calendarItemIdentifier` values.
- **`ReminderSkipLogic`** (`ReminderSkip.swift:5-31`): pure functions `resolve(fetched, skipped)` (set-intersection + dedup) and `skipping(identifier, fetched, skipped)` (append + resolve). No UIKit/EventKit dependencies.
- **`AppGroup.swift`** (`:5-15`): `suiteName = "group.app.alanvardy.SingleThread"`; `AppGroup.defaults = UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard`. The App Group is shared between the iOS app and the **widget extension** (the widget reads the same UserDefaults suite), but **not** the watch app (watchOS has no user App Group — falls back to `.standard`).
- **`SkippedReminderSyncService`** (`SkippedReminderSyncService.swift`, iOS+watchOS compiled under `#if os(iOS) || os(watchOS)`): `NSObject, WCSessionDelegate`. `SkipSyncSession` protocol (`:9-21`) is the WatchConnectivity seam.
  - `push(skipIDs, showUndatedReminders)` (`:83-92`): builds `[skippedReminderIdentifiers, showUndatedReminders, sortOption, (optionally) showDate]` and calls `session.updateApplicationContext(context)` — a **latest-wins** payload where the sender sends its full set.
  - `pushExcludedProjectTitles`, `pushSortOption`, `pushShowDate` (`:101-136`).
  - `requestCompleteReminder(id)` (`:141`) / `requestDeleteReminder(id)` (`:151`) — used for **interactive** messages (`session.sendMessage`).
  - `session(_:didReceiveApplicationContext)` (`:164-186`): the counterpart **receives** the context, writes each received key (skip ids → `skipStore.save`, `excludeStore.save`, sort → `sortStore.save` + `setSortOption`, showUndated → `onShowUndatedRemindersReceived?`, showDate → `showDateStore.set`). **Latest-wins + replacement** semantics, so a clear (`[]`) propagates.
  - `PayloadKey` enum (`:226-236`) defines `skippedReminderIdentifiers` = `"skippedReminderIdentifiers"`, plus excluded, complete, delete keys, `showUndatedReminders`, `sortOption`, `showDate`.
- **Phone → watch** (iOS entry `SingleThreadApp.swift:22-40`): builds `SkippedReminderSyncService(session: WCSession.default, skipStore:, ...)`; wires `store.onSkipSetChanged → service.push(ids, showUndatedReminders:)`; `store.onShowUndatedRemindersChanged → service.push(...)`; on iOS. `store` hooks push the combined context whenever skip/showsUnenc/sort change.
- **Watch receives** (`SingleThreadWatchApp.swift:18-32`): constructs `SkippedReminderSyncService(session:, sendShowDate:false)` and wires `service.onShowUndatedRemindersReceived` → sets `store.showsUndatedReminders` then `store.reload()`; `service.onSortOptionReceived` → `store.setSortOption`. `store.onSkipSetChanged → service.push(...)` propagates back to phone.
- **Observed across devices**: store-side `applySkipSet` writes `skipStore.save()` (App Group key for the iOS **watch** → `SkippedStore`? No: iOS uses `SkippedReminderStore()` which defaults to `AppGroup.defaults`), then fires `onSkipSetChanged`; the companion pushes the full context; the counterpart's `didReceiveApplicationContext` persists the received skip IDs, and the store picks them up on its next `reload()` (`skipStore.load()` in `reload`, `ReminderStore.swift:207`). A skip made on one device is observed on a sibling through this **shared `skippedReminderIdentifiers` key + latest-wins context push + `reload()` prune**.

---

## Q6: test suites covering these areas

Also see `AGENTS.md` for project-wide "*make test* / *make ui-test* / *./scripts/test.sh*" conventions.

### Findings
- **Framework split**: unit (`SingleThreadTests/`) uses **Swift Testing** (`import Testing`, `@Test`, `@Suite`, `#expect`, `@MainActor`). UI (`SingleThreadUITests/`, `SingleThreadWatchUITests/`) uses **XCTest** (`XCTestCase`, `XCUIApplication`, `XCTAssert...`).
- **`SettingsViewTests.swift`** — Swift Testing, `@MainActor struct SettingsViewTests` (`:7-9`); one `@Test func settingsViewContainsAllPreferenceRows()`. It constructs `SettingsView(...)` with `.constant(...)` bindings (iOS `:11-22`; else `:24-33`), `String(describing: view.body)`, and `#expect(bodyDescription.contains("Appearance")...)` etc. (iOS additionally `"Landscape"`). No transcriber/prepop store.
- **`MicrophoneToggleTests.swift`** — defines **`MicToggleFakeTranscriber`** (`: primaryAuthor.SpeechTranscribing`, `: Background` final class, `: fields`, `: `init(authorizationStatus: .authorized)`), injected via `ContentView(loadsReminders: false, speechTranscriber: fake)`. Tests:
  - `settingsGearButtonIsPresent` (`:34`) — asserts `bodyDescription.contains("Settings")`. Constructor also calls `view.body` — invokes SettingsView's `$isShowingSettings` `@Environment(\\.dismiss)` path.
  - `micButtonHiddenWhenSpeechDenied` (`:49`) — fake `.denied`, sets `UserDefaults.standard.set(true, "showMicrophoneButton")`, asserts `!bodyDescription.contains("mic.fill")`.
  - `micButtonAbsentWhenToggleOff` (`:69`) — fake `.authorized`, `set(false)`, assert `!isEmpty`.
  - `micButtonWithToggleEnabledDoesNotCrash` (`:82`).
- **`ReminderStoreTests.swift`** — Swift Testing `@Suite(.serialized)` `@MainActor` (`:6-7`); uses `ReminderStore(loadsReminders:false, reminders: [...], skippedIDs:[...], authorizationStatus:.fullAccess)` (never touches EventKit), with `makeReminder(title:)`. Tests skip/complete:
  - `skipCurrentReminderDoesNothingWhenNoVisibleReminders` (`:249-258`);
  - `skipCurrentReminderUpdatesSkippedIDs` (`:261-273`) — sets `store.onSkipSetChanged`; calls `skipCurrentReminder()`; asserts `skippedIDs.contains(rem.calendarItemIdentifier)`; async so it awaits the settle-delayed Task.
  - `skipCurrentReminderFiresRemindersChangedHook` (`:276-287`);
  - `completeCurrentReminderDoesNothingWhenNoReminders` (`:293`), `...AllSkipped` (`:304`) asserts `reminders.count == 1` unchanged, `...DoesNotCrashWithVisibleReminder` (`:316`);
  - `completeReminderDoesNothingWhenIdentifierNotFound` (`:322`).
  - Plus `visibleReminders...` cases at `:10-45`.
- **`EventKitStoring` seam** (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`) is the iOS test seam behind `ReminderStore`: a `@MainActor protocol EventKitStoring` with `authorizationStatus`, `calendars`, `requestFullAccessToReminders`, `fetchReminders`, `save/remove/makeReminder`; extended by `EKEventStore`. Tests (e.g. `SingleThreadTests/EventKitStoringTests.swift`) inject a recording fake conforming to `EventKitStoring`.
- **UI launch seam (`--ui-testing`)**:
  - iOS `SingleThreadApp.swift:18-20`: `loads = !args.contains("--ui-testing")`; when the flag is present, `store` is created with `loadsReminders:false` → `ContentView` renders the **empty "No Reminders"** branch, no EventKit auth prompt (avoids Reminders TCC on a fresh simulator, VAR-639).
  - Watch `SingleThreadWatchApp.swift:22-35`: `--ui-testing` → `Self.uiTestingStore()` builds a **deterministic store** pre-populated with a mock `"Buy groceries"` reminder (`.fullAccess`, `loadsReminders:false`) so a real card presents without EventKit access.
  - Both entry points also treat `--no-reminders` wiring.
- **`SingleThreadUITests.swift`** (XCTest): `testAccessibilityAudit()` launches `app.launchArguments = ["--ui-testing"]`, `XCTest` `waitForExistence(timeout:2)`, then `app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` on iOS (skips contrast / known false-positive for system colors and textClipped); on macOS `app.performAccessibilityAudit()` (defaults).
- **`SingleThreadUITestsLaunchTests.swift`**, **`...AppearanceLaunchTests.swift`** (XCTest): launch `XCUIApplication()` with `--ui-testing`, capture `XCTAttachment(screenshot:)`.
- **`SingleThreadWatchUITests.swift`** (XCTest): `testTapRevealsConfirmationDialog()` launches with `--ui-testing`, `app.staticTexts["Buy groceries"]`, tap → asserts `Refresh` button from confirmation; `testAccessibilityAudit()` runs `.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` on watchOS.
- **`ReminderDictationTests.swift`** (Swift Testing) also injects a fake `SpeechTranscribing` via `ContentView(loadsReminder:false,..)` / `ContentView(store:,..)` (`:136,:144`) — the `SpeechTranscribing` protocol is defined in `SingleThread/ReminderDictation.swift:10`.

---

## Cross-Cutting Observations

- **One store drives all visible-reminder logic.** `ReminderStore.visibleReminders` (`ReminderStore.swift:105-107`) uniformly filters skipped + excluded + sorts; both iOS `ContentView`, watch `WatchReminderView`, and widget `NextThingProvider` all check `visibleReminders.first` (or `allSkipped`) to decide which card/empty/doc state to render.
- **Switch from a shareable "skip exclusion" concept to a *persisted identifier list*.** A skip is really "add this `calendarItemIdentifier` to the persisted skipped list under key `"skippedReminderIdentifiers"`"; on completion/deletion the same identifier is removed/none (via `reload` pruning or away in `onComplete/onDelete` relay). The `ReminderSkip` logic and sync service handle this list uniformly across **phone, watch, widget**.
- **WatchConnectivity is the cross-device transport; App Group is the widget transport.** `SkippedReminderSyncService` moves skip + exclusion + sort + show-date via `updateApplicationContext` (latest-wins) for phone↔watch, while the widget talks to the same `skippedReminderIdentifiers` key via the shared `AppGroup.defaults` and constructs its own `ReminderStore`.
- **Platform-conditional action surfaces with one shared idiom.** Complete/Skip/Delete appear as (a) macOS `actionButtons` (bottomBar), (b) iOS mobile via `.swipeActions`(+`.contextMenu`), (c) watchOS fixed `actionButtons`, (d) macOS/iOS widget `Button(intent:)`. All use the same `checkmark.circle.fill`/`circle.slash`/`trash` symbols, green/orange/red tints, `.iconOnly` labels, and `.accessibilityLabel(...)` strings.
- **store mutation vs settle delay.** Completing/deleting/adding does the EventKit write, then `sleep(eventKitSettleDelay=200ms)` then `reload()`; skipping applies after the same delay except via `skipCurrentReminderImmediately()` (widget intent) which applies synchronously.

## Open Areas

- **Watch-on-skip refresh timing.** It's observed that a received `skippedReminderIdentifiers` update lands in `skipStore`, but the watch's *in-memory* `skippedIDs` is only recomputed on the next `store.reload()`. I did not find a code path that calls `store.reload()` directly from the received skip context (only `onShowUndatedRemindersReceived`/`onSortOptionReceived` trigger reload on the watchWatchApp). Confirm whether a phone-initiated skip propagates to the watch's currently-displayed card immediately — this may be by-refresh-only.
- **Widget's `CompleteReminderIntent` writes against a fresh `ReminderStore`** (`ReminderIntents.swift`) — it does **not** call `skipStore.save` on the shared App Group directly, but goes through `completeCurrentReminder()` (which on iOS writes EventKit). Confirm whether the widget's reload observes the shared skipped-ID Store including the watch only reload path.
- **Settings `@AppStorage` default split.** `showMicrophoneButton` mirrors standard; the rest AppGroup. The `.standard` fallback in `AppGroup.defaults` means unregistered-simulator/preview use standard storage. Confirm expected behavior for each target if the App Group is missing (partial answer in `AppGroup.swift:13-14`).