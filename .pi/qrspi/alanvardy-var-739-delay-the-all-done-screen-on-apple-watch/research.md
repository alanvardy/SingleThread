# Research Findings

Branch: `alanvardy-var-739-delay-the-all-done-screen-on-apple-watch` — completion / empty-state / glow flow on watchOS.

## Q1: Empty-state presentation

### Findings
- Root gate is a `switch` on `viewModel.store.authorizationStatus` in `WatchReminderView.body` (`SingleThreadWatch/WatchReminderView.swift:43-54`):
  - `.notDetermined` → `ProgressView("Requesting access…")` (`:46-47`).
  - `.fullAccess` → `reminderContent` (`:48-49`).
  - `default` (denied/restricted/etc.) → `Text("Enable Reminders access in Settings").multilineTextAlignment(.center)` (`:50-52`).
  - Driven by `.task { await viewModel.task() }` (`:55-57`) → `WatchReminderViewModel.task()` (`WatchReminderViewModel.swift:41-43`) → `ReminderStore.start()` (`ReminderStore.swift:123-132`), which sets `authorizationStatus` then reloads (`.fullAccess`) or requests access.
- `reminderContent` (`WatchReminderView.swift:75-99`) is a `ZStack` with three mutually exclusive branches:
  - `if viewModel.store.allSkipped` → `allDoneState` (`:77-78`; view at `:125-131`): `Text("All Done").font(.headline)` + `refreshButton`.
  - `else if let reminder = viewModel.store.visibleReminders.first` → `reminderCard(reminder)` (`:79-80`; view at `:169-193`).
  - `else` → `noRemindersState` (`:81-82`; view at `:133-143`): `Text("No Reminders")` (`:135`) + subtitle selected by `viewModel.store.hasHidden` — `"Nothing due right now"` when `hasHidden`, else `"No reminders yet"` (`:137`) + `refreshButton`.
- Overlay A — refresh spinner: `if viewModel.isRefreshing { ProgressView() … alignment: .top }` (`:85-89`), rendered above whichever branch, driven by `WatchReminderViewModel.isRefreshing` (`WatchReminderViewModel.swift:38`) toggled in `refresh(clearSkipped:)` (`:54-66`).
- Overlay B — completion glow: `.overlay { if viewModel.completionGlow.isActive { completionGlowOverlay } }` (`WatchReminderView.swift:91-95`).
- Store selectors feeding the branches (`ReminderStore.swift`):
  - `visibleReminders` (`:99-106`): `reminders` filtered by `skippedIDs` + `excludedListTitles`, sorted by `sortOption`.
  - `allSkipped` (`:108-109`): `!reminders.isEmpty && visibleReminders.isEmpty`.
  - `hasHidden` (`:46`): set in `reload()` at `:288`/`:297` via `hasHiddenFor(shown:allIncomplete:)` (`:115-118`); seedable via init (`:23`, `:32`).
- Distinction: a completed/deleted-only empty list (reminders array empty) → **No Reminders**; reminders exist but all hidden by skip/exclude → **All Done**.
- Previews enumerate all states: `#Preview("Requesting Access"/"Reminder"/"All Skipped"/"No Reminders"/"Nothing Due"/"No Access")` (`WatchReminderView.swift:270-323`).

## Q2: Completion / skip / delete mutation flow

### Findings
- **Complete**: Complete button (`WatchReminderView.swift:101-111`, `Label("Complete", systemImage: "checkmark.circle.fill")` at `:106`, a11y label "Complete reminder" at `:110`) → `Task { await viewModel.completeCurrentReminder() }` (`:104`) → `WatchReminderViewModel.completeCurrentReminder()` (`WatchReminderViewModel.swift:48-52`): `if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled { completionGlow.trigger() }`.
  - Store: `completeCurrentReminder()` (`ReminderStore.swift:171-173`) → `completeReminder(identifier:)` (`:145-151`). watchOS branch (`:147-151`): `reminders.removeAll { … == identifier }` (**the in-memory mutation that invalidates the observing view**) then `onCompleteReminder?(identifier)`.
  - Relay: hook wired at `WatchAppViewModel.swift:167` → `SkippedReminderSyncService.requestCompleteReminder` (`SkippedReminderSyncService.swift:177-185`): `session.sendMessage([PayloadKey.completeReminderIdentifier: identifier], replyHandler: nil)` — fire-and-forget watch→phone, no success gate.
  - **Ordering**: the mutation (`ReminderStore.swift:148`) executes before the glow trigger (`WatchReminderViewModel.swift:45`), with no suspension between them on the watch path (watchOS branch of `completeReminder` never awaits). A single body render sees the emptied content branch **and** `completionGlow.isActive == true` simultaneously; there is no frame with the empty state but no glow. The branch swap itself has no transition — only the glow overlay animates (`.transition(.opacity)`, `.animation` at `WatchReminderView.swift:96-98`).
  - **Phone receive**: `SkippedReminderSyncService.session(_:didReceiveMessage:)` (`:204-211`) → `onCompleteReminderReceived` wired at `SingleThread/AppViewModel.swift:41-43` → `Task { await store?.completeReminder(identifier:) }` → iOS branch (`ReminderStore.swift:152-168`): EventKit save → `Task.sleep(eventKitSettleDelay)` (`:160`) → `reload()` → `onRemindersChanged?()` (`:320`).
- **Skip**: Skip button (`WatchReminderView.swift:113-117`, a11y "Skip reminder" at `:120`) → `viewModel.store.skipCurrentReminder()` (direct store call, no view-model indirection) → `ReminderStore.skipCurrentReminder()` (`ReminderStore.swift:232-238`): computes next skip set, then defers the actual mutation — `Task { try? await Task.sleep(eventKitSettleDelay); applySkipSet(updated) }` — so `skippedIDs` mutates **~200 ms after** the tap (the deferred mutation point; `applySkipSet` at `:382-386` sets `skippedIDs`, saves, fires `onSkipSetChanged` + `onRemindersChanged`). Empty state reached via `allSkipped` becoming true (All Done). No glow on skip path.
  - Relay: `store.onSkipSetChanged = { _ in service.pushAll() }` (`WatchAppViewModel.swift:164`) → `SkippedReminderSyncService.pushAll()` (`:146-175`) → `updateApplicationContext` (latest-wins, auto-delivers on reconnect).
  - Widget-only variant `skipCurrentReminderImmediately()` (`ReminderStore.swift:257-261`) writes synchronously (no settle sleep).
- **Delete**: card tap → `confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation)` (`WatchReminderView.swift:179-188`) → `Button("Delete", role: .destructive)` → `Task { await viewModel.store.deleteCurrentReminder() }` (`:185-186`) → `ReminderStore.deleteCurrentReminder()` (`:198-199`) → `deleteReminder(identifier:)` (`:181-193`). watchOS branch (`:183-185`): `reminders.removeAll` (invalidation point) then `onDeleteReminder?(identifier)`. Relay via `requestDeleteReminder` (`WatchAppViewModel.swift:168`, `SkippedReminderSyncService.swift:187-195`) → phone `onDeleteReminderReceived` (`AppViewModel.swift:44-46`) → iOS `deleteReminder` (`ReminderStore.swift:186-193`): `eventStore.remove` → `eventKitSettleDelay` → `reload()`. No glow on delete path.
- Refresh/clear: `refreshButton` runs `refresh(clearSkipped: viewModel.store.allSkipped)` (`WatchReminderView.swift:162-165`) — i.e. clearing the skip list when currently on All Done.

## Q3: Transient animation and timer mechanics

### Findings
- `CompletionGlow` (`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift`): `@MainActor @Observable public final class` (`:11-13`).
  - State: `public private(set) var isActive = false` (`:21`).
  - Default duration: `public var duration: TimeInterval = 0.50` (`:27`) — doc comment (`:23-26`) explains 0.50 s was chosen so the 0.4 s watch animation envelope doesn't fade the glow out before it's perceptible.
  - `trigger()` (`:32-46`): `isActive = true` → `dismissTask?.cancel()` (`:34`) → snapshot `seconds = duration` (`:35`) → `dismissTask = Task { [weak self] … try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); self?.isActive = false }` (`:36-44`); the `catch` deliberately leaves `isActive` untouched on cancellation (`:40-43`).
  - **Re-trigger semantics**: a second `trigger()` while active cancels the running dismiss task and restarts a fresh `duration` countdown ("the timer resets", `:34`).
  - No reduce-motion handling inside the type — purely time-driven; motion suppression lives at the view layer.
- Watch rendering: `completionGlowOverlay` (`WatchReminderView.swift:149-160`) — `Color.green.opacity(0.3).ignoresSafeArea().allowsHitTesting(false)` (`:150-153`), `accessibilityHidden(!isGlowUITesting)` (`:154`), a11y id `"completionGlowOverlay"` (`:156`), `.transition(.opacity)` (`:158`). Animated by `.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: viewModel.completionGlow.isActive)` (`:96-98`) on the whole `reminderContent`.
- Glow owners: watch `WatchReminderViewModel.swift:36`; iOS `ContentViewModel.swift:38`.
- Timing/delay conventions inventory:
  - `MinimumDisplayDuration` (`SingleThreadCore/Sources/SingleThreadCore/MinimumDisplayDuration.swift:6-13`): `remainingSleep(elapsed:minimum:)` = `max(0, minimum - elapsed)`. Used only by `WatchReminderViewModel.refresh(clearSkipped:)` (`WatchReminderViewModel.swift:59-63`) to keep the refresh spinner ≥ 1 s (`refreshMinimumDisplayDuration: TimeInterval = 1`, `:72`). Unit-tested in `SingleThreadTests/MinimumDisplayDurationTests.swift:11-30`.
  - `eventKitSettleDelay` (`ReminderStore.swift:364`): `200_000_000` ns constant; used as `Task.sleep` before `reload()` after save/remove in complete (`:160`), delete (`:189`), add (`:222`), and before `applySkipSet` in `skipCurrentReminder` (`:236`). Rationale doc `:361-363`: EventKit may not reflect an in-flight save immediately.
  - `CompletionGlow`'s `Task.sleep` (`CompletionGlow.swift:38`) — auto-dismiss timer (see above).
  - `WatchReminderViewModel` refresh-minimum `Task.sleep` (`WatchReminderViewModel.swift:63`).
  - `DispatchQueue.main.asyncAfter(deadline: .now() + 5)` — UI-test-only seam delivering a fake `didReceiveApplicationContext` (`WatchAppViewModel.swift:208-212`).
  - iOS `Task.sleep(1_000_000_000)` in `DictationViewModel.swift:63` (recording rollout) and `Task.sleep(5_000_000_000)` in `ReminderDictation.swift:187` (auto-stop after silence).
  - Tests: `CompletionGlowTests.swift:37-51` (auto-dismiss, 0.05 s duration + 20 ms sleep), `ReminderDictationTests.swift:52,58` (50 ms).
- No `ContinuousClock`, `Duration`, or `.seconds(...)` usages anywhere in the targets (grep across `SingleThread/`, `SingleThreadCore/`, `SingleThreadWatch/`, `SingleThreadWidget/`).

## Q4: Observation and re-render model

### Findings
- `ReminderStore` is `@MainActor @Observable public final class` (`ReminderStore.swift:5-6`); `CompletionGlow` likewise (`CompletionGlow.swift:11-13`). No Combine/`@Published`/NotificationCenter/polling/`withObservationTracking` anywhere in the watch target or core (grep confirms).
- Watch target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`SingleThread.xcodeproj/project.pbxproj:945` Debug, `:973` Release, watch target), so watch types without explicit annotations become MainActor-isolated; iOS target sets it too (`:769`, `:819`).
- `WatchReminderViewModel` is `@MainActor @Observable final class` (`WatchReminderViewModel.swift:6-7`); `WatchAppViewModel` is `@MainActor final class` (composition root, not `@Observable`, `WatchAppViewModel.swift:9`); the `Show*State` holders (`ShowDateState.swift:8`, `ShowRecurrenceState.swift:8`, `ShowAlarmsState.swift:8`, `ShowListState.swift:8`, `ShowCompletionGlowState.swift:7`) are `@Observable final class` with no explicit annotation (isolated via target default).
- `WatchReminderView` holds the view model as a plain stored `let` (`WatchReminderView.swift:65`) — no `@State`/`@EnvironmentObject` in the watch target; only `@Environment(\.accessibilityReduceMotion)` (`:62-63`). Body reads are plain property reads of the observable graph: `store.authorizationStatus` (`:45`), `store.allSkipped` (`:77`), `store.visibleReminders.first` (`:79`), `store.hasHidden` (`:137`), `isRefreshing` (`:85`), `completionGlow.isActive` (`:92`, `:98`), `showDateState.isEnabled` (`:207`), etc. Only binding is `@Bindable var viewModel = viewModel` inside `reminderCard` (`:170`) for the `confirmationDialog` binding.
- Composition root: `SingleThreadWatchApp.init()` builds `WatchAppViewModel` once (`SingleThreadWatchApp.swift:11-13`); `reminderViewModel` is a stored `lazy var` (`WatchAppViewModel.swift:73-79`) so the glow-duration seam mutates the same instance the view renders (tested: `SingleThreadWatchTests/WatchAppViewModelTests.swift:20-26`). Root render: `WindowGroup { WatchReminderView(viewModel: viewModel.reminderViewModel) }` (`SingleThreadWatchApp.swift:15-17`).
- Re-render mechanics as observed: mutation of any `@Observable` property read in `body` invalidates that view; SwiftUI re-evaluates the whole body. Because the watch's branch `if/else if/else` inside `ZStack` (`:77-82`) is a plain conditional, a branch switch replaces the subtree with no insertion/removal transition — only the `.animation(_, value: completionGlow.isActive)` (`:96-98`) + `.transition(.opacity)` (`:158`) on the overlay animate. The `value:` parameter means the animation fires only when `completionGlow.isActive` changes; the empty-state branch swap is not inside any animated value, hence unanimated.

## Q5: UI-test determinism seams

### Findings
- All watch launch-argument parsing in `WatchAppViewModel.init(arguments: [String] = ProcessInfo.processInfo.arguments)` (`WatchAppViewModel.swift:12-13`).
  - `--ui-testing` (`:14`): builds store via `Self.uiTestingStore(arguments:)` (`:16`, defined `:85-123`) instead of `ReminderStore(loadsReminders: true)` (`:18`). Seeded store: one mock `EKReminder` "Buy groceries", priority 5, notes "Don't forget the milk", backed by `InMemoryEventStore`, `loadsReminders: false`, `authorizationStatus: .fullAccess` (`:108-118`) — no EventKit access prompt.
  - `--ui-testing-excluded-list "<list>"` (`:96-99`, parsed in loop at `:94-95`): sets the sample reminder's calendar to that title **and** pre-seeds `excludedListTitles: [list]` (`:109-110`, via `:112-116`) so the card is suppressed from launch.
  - `--ui-testing-live-excluded "<list>"` (`:96-99` same loop): calendar set but `excludedListTitles: []` (`:112-116`) so the card renders first; `scheduleUITestLiveExcludedDelivery` (`:202-213`) delivers a real `didReceiveApplicationContext: ["excludedListTitles": [list]]` after `DispatchQueue.main.asyncAfter(.now() + 5)` (`:208-212`), exercising the live receive path → `onExcludedListTitlesReceived` → `store.refreshExcludedListTitles` (`:160-162`, `ReminderStore.swift:337-340`).
  - `--ui-testing-glow-disabled` (`:39-40`): `showCompletionGlowState.apply(false)` — pre-disables glow without a settings screen.
  - `--ui-testing-glow` (`:41-42` force-enable `apply(true)`, `:44-48` duration seam): `reminderViewModel.completionGlow.duration = 2.0` (`:48`) — the deterministic-timing seam; production default 0.50 s (`CompletionGlow.swift:27`). Force-enable comment (`:34-37`) explains it exists so the enabled-flow test never inherits a `false` persisted by an earlier disabled-flow test in the same UI-test session (UserDefaults carries across relaunches). Also read in view: `isGlowUITesting` (`WatchReminderView.swift:69-71`) exposes the overlay to accessibility (`:154`).
- iOS counterparts: `--ui-testing-glow` duration 2.0 s at `SingleThread/AppViewModel.swift:102-105` (its comment says "production duration is 0.25 s" — stale vs the current 0.50 default); `--seed <json>` on iOS (per AGENTS.md, backed by `InMemoryEventStore`; watch uses its own `--ui-testing` seam instead).
- Existing watch UI tests (`SingleThreadWatchUITests/`):
  - `SingleThreadWatchUITestsFlows.swift` — `launchApp()` helper launches with `["--ui-testing"]` (`:140-146`). Tests: card title/notes (`:21-31`, waitForExistence timeouts 5/3 s); excluded list suppresses card + asserts **"All Done"** (`:35-48`, XCTAssertFalse 3 s + XCTAssertTrue 5 s); live exclusion (`:53-68`, 5 s then 10 s); complete → asserts **"No Reminders"** (`:73-83`, 5 s); skip → asserts **"All Done"** (`:88-98`, 5 s); delete via dialog → **"No Reminders"** (`:103-117`); Refresh button on No Reminders (`:122-135`); **glow disabled** asserts `app.otherElements["completionGlowOverlay"].exists == false` after complete (`:141-156`); **glow enabled** asserts `app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3)` (`:160-177`) — deterministic because the seam extends duration to 2 s.
  - `SingleThreadWatchUITests.swift` — tap reveals confirmation dialog (`:12-28`, timeouts 5/5), accessibility audit on `.dynamicType/.hitRegion/.sufficientElementDescription/.trait` (`:31-47`).
  - `SingleThreadWatchUITestsLaunchTests.swift` — launch-only.
- Wait style is uniformly `XCTAssertTrue(app.staticTexts[ ... ].waitForExistence(timeout: N))` / `app.buttons[...]` / `app.otherElements["completionGlowOverlay"]`; no `XCTNSPredicateExpectation` or `sleep()` in watch UI tests. Test target guard: overlay element is only in the a11y tree under `--ui-testing-glow` (`WatchReminderView.swift:154`).

## Q6: Architecture boundaries and the iOS counterpart

### Findings
- **Shared (SingleThreadCore, local SPM package; `Package.swift` platforms iOS 18.7 / watchOS 26.5 / macOS 26.5)**:
  - `CompletionGlow` (`CompletionGlow.swift:13`) — shared state machine, owned by both the watch VM (`WatchReminderViewModel.swift:36`) and iOS VM (`ContentViewModel.swift:38`); not used by widget.
  - `ReminderStore` (`ReminderStore.swift:5`) — the reminder→empty-state data source for iOS, watch, and widget (built-in `#if os(watchOS)` branches for read-only EventKit, `:147-151`, `:183-185`).
  - `ShowCompletionGlowPreference` (`ShowCompletionGlowPreference.swift:8`) — persisted struct, defaults `AppGroup.defaults`, absent key → `true`.
  - `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:29`) — WCSession push/receive; payload keys (`PayloadKey` enum at `:235`); `requestCompleteReminder`/`requestDeleteReminder` (`:177-195`); single `apply(context:)` receive path (`:270-334`).
  - `SkippedReminderStore` (skip persistence, `ReminderSkip.swift:121`), `ReminderDisplay` (`ReminderDisplay.swift:6`), `MinimumDisplayDuration`, `AppGroup`, `InMemoryEventStore`, `EventKitStoring`.
- **Watch-only (SingleThreadWatch)**:
  - `ShowCompletionGlowState` (`ShowCompletionGlowState.swift:7-29`) — `@Observable` holder wrapping `ShowCompletionGlowPreference(defaults: .standard)` (`:27`); `private(set) var isEnabled` (`:18`); `apply(_:)` persists + publishes (`:23-26`). Sibling `ShowDateState`/`ShowRecurrenceState`/`ShowAlarmsState`/`ShowListState` share the identical shape. These replace watch-side `@AppStorage` (doc comment `:3-5`).
  - Empty states are inline computed views (`allDoneState` `WatchReminderView.swift:125-131`, `noRemindersState` `:133-143`) — no extracted empty-state types on watch.
  - Composition: `SingleThreadWatchApp` (`SingleThreadWatchApp.swift:11-17`) → `WatchAppViewModel` (`WatchAppViewModel.swift:12-51` init builds store, show-* states, sync service, seams) → stored `lazy var reminderViewModel` (`:73-79`) → `WatchReminderViewModel` owns `store` + `show*State` + `completionGlow` (`WatchReminderViewModel.swift:27-36`).
  - Sync wiring on watch: all `sendsShow*: false` plus `sendsShowCompletionGlow: false` (`WatchAppViewModel.swift:140-141`) — watch only *receives* show-* flags; skip pushes phone-bound via `store.onSkipSetChanged` (`:164`); completion/delete relay watch→phone (`:167-168`).
- **iOS counterpart (SingleThread/)**:
  - Store construction + sync service wiring in `SingleThread/AppViewModel.swift:17-55` (receive handlers `:39-50`); glow duration seam `:102-105`.
  - `ContentViewModel` (`ContentViewModel.swift`): owns `completionGlow` (`:38`), `completeCurrentReminder()` gate + trigger (`:108-112`) same shape as watch; also `skipCurrentReminder()`, `deleteCurrentReminder()`, `reload(clearSkipped:)` forwarding (`:114-131`). Empty-state copy helpers `emptyStateCopy(hasHidden:)` (`:58-69`: "Nothing due"/"No Reminders" with descriptions) and `allDoneStateCopy()` (`:71-76`: "All Done").
  - `ContentView` renders the same three-way branch (`:294-308`: `allSkipped` → `ContentUnavailableView` all-done copy; `reminders.isEmpty` → empty copy; else `List` with `visibleReminders.first`) — but uses dedicated `ContentUnavailableView` + `ScrollView` + `.refreshable` states rather than the watch's inline `VStack`s + Refresh buttons. Glow overlay at `:80-87` (`.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: viewModel.completionGlow.isActive)`), overlay view `:497-507` with opacity **0.1** vs watch's **0.3** (`ContentView.swift:499` vs `WatchReminderView.swift:151`).
  - Key differences iOS vs watch: iOS mutations go through real EventKit (save/remove + `eventKitSettleDelay` + `reload()`, `ReminderStore.swift:152-168`, `:186-193`), so the empty state appears only **after** the settle/reload round-trip, well after the glow has triggered; the watch mutates its in-memory array synchronously (no reload), so the empty branch and the glow render in the same frame. iOS skip also uses `skipCurrentReminder()`'s deferred `applySkipSet` (`ReminderStore.swift:232-238`).

## Cross-Cutting Observations
- Single shared `ReminderStore` + `CompletionGlow` in Core; platform differences live entirely inside `#if os(watchOS)` branches in `ReminderStore` and in per-target view models/views. The watch is not "upstream" of the phone for reminders — EventKit is read-only there (`ReminderStore.swift:145-151`, `:183-185`; `addReminder` returns `false` on watchOS, `:212-213`).
- The observer-invalidation point and the animation trigger are deliberately decoupled: store mutations drive the content-branch switch (unanimated), while a separate `CompletionGlow` object drives the only animated change (`.animation(value: completionGlow.isActive)` + `.transition(.opacity)`).
- All transient timing on the watch is `Task.sleep`-based on MainActor (glow dismiss, refresh minimum, skip settle); the only `asyncAfter` is a UI-test-only context delivery seam. No Combine/polling anywhere.
- Watch UI tests are fully deterministic via `--ui-testing` (seeded in-memory store), duration-extension (2.0 s glow), and a11y gating of the overlay (`accessibilityHidden(!isGlowUITesting)`).
- Skip defers its mutation by the 200 ms `eventKitSettleDelay`, so the All Done state lags the tap; complete/delete mutate synchronously.
- The UI-test seams are test-target-specific but live in production code (`WatchAppViewModel`), gated on `ProcessInfo.processInfo.arguments` — same convention as iOS.

## Open Areas
- Exact SwiftUI body re-evaluation ordering across the `ZStack` branch swap + overlay `.animation` on the same frame is asserted from the code structure (single synchronous MainActor turn) but not empirically instrumented; the ordering claim (empty state and glow appear in the same render) relies on the absence of suspensions in the watchOS complete path.
- The refresh spinner overlay (`isRefreshing`) placement relative to completion animations was not exercised by any UI test — existing tests never trigger refresh-then-complete races.
- iOS `--ui-testing-glow` comment (0.25 s) is stale vs the actual 0.50 s default (`CompletionGlow.swift:27`) — noted as documentation drift, not behavior.
- Whether `Task { … }` in `skipCurrentReminder` (`ReminderStore.swift:235-238`) inherits MainActor and the exact interleaving with a simultaneous completion was not traced beyond the code (both are MainActor, so serialized in practice).