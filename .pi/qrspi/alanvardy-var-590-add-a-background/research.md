# Research Findings

## Q1: Root view structure (`ContentView.body`), layering, safe areas, Appearance system

### Findings
- `body` is a `ZStack` whose **first child is `Color.systemBackground.ignoresSafeArea()`** — the only full-bleed layer; content children follow: `authGatedContent` (when `store.loadsReminders`) else `reminderList` — `SingleThread/ContentView.swift:61-68`.
- `Color.systemBackground` is defined in `SingleThread/Color+CrossPlatform.swift:12-18` (wraps `UIColor.systemBackground` / `NSColor.windowBackgroundColor`).
- Modifier chain on the ZStack, in order: `.overlay(alignment: .topTrailing)` settings gear button (`ContentView.swift:70-88`) → `.task { store…; await store.start() }` (:89-92) → `.onChange(of: showUndatedReminders/sortOption/appearanceMode)` (:93-101) → `.modifier(TextSizeModifier(textSize:))` (:103) → `.sheet(isPresented: $isShowingSettings)` presenting `SettingsView` (:106-133).
- No other `ignoresSafeArea`, no `safeAreaInset` anywhere in the file. Bottom chrome uses `ZStack(alignment: .bottom)` overlaying `bottomBar`; centering math done manually via `GeometryReader.safeAreaInsets` (`reminderList`, `ContentView.swift:294-383`, insets at :296-298).
- Where a new full-screen visual layer would sit in the existing hierarchy: inside the ZStack between background color and content (behind everything), or after content (above content, below the gear `.overlay`), or as an additional `.overlay`/`.background` modifier.
- **Appearance system**: `AppearanceMode` enum (system/light/dark) at `SingleThread/AppearanceMode.swift:14-19`; selected by Picker in `SettingsView.swift:93-100` bound to ContentView's `@AppStorage("appearanceMode")` (`ContentView.swift:184-185`, default `.system`).
- Application is at the **UIWindow level**, not per-view: `AppDelegate.applyAppearance(_:to:)` sets `window.overrideUserInterfaceStyle = mode.windowOverrideStyle` on all windows from connected scenes (`SingleThread/AppDelegate.swift:15-23`). Triggered live via `.onChange(of: appearanceMode)` (`ContentView.swift:96-101`) and at activation via `applicationDidBecomeActive` → `applyAppearance(AppearanceMode.load())` (`AppDelegate.swift:45-48`); `AppearanceMode.load(from:)` reads `"appearanceMode"` from `UserDefaults.standard`, falling back to `.system` (`AppearanceMode.swift:62-68`).
- Because styling is window-level, the ZStack background color automatically resolves light/dark variants; no per-view appearance logic exists.

## Q2: Networking / remote-data code and async/background patterns

### Findings
- **No networking code exists in any target.** Zero hits for `URLSession`, `URLRequest`, `dataTask`, `URL(string:)` network use, `BGTask`, background modes, or `scenePhase` across app, Core, watch, widget. Only non-network URL uses: `ReminderDeepLink.swift:16` (`x-apple-reminderkit://`) and test fixture `ContentView.swift:568`. No actors declared, no Timers.
- Established async idioms a remote fetch would follow:
  - Store pattern: `@MainActor @Observable final class ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:8-9`); `start() async` documented "Call from `.task` in the view layer" (`ReminderStore.swift:124-139`); single refresh path `reload(clearSkipped:) async` (`ReminderStore.swift:251-320`).
  - Completion-handler→async bridge: `withCheckedContinuation` + `ResumptionGate`, resuming on MainActor because EventKit delivers off-main (`ReminderStore.swift:376-394`; `ResumptionGate.swift:41-50`).
  - Settle delays: `try? await Task.sleep(...)` (e.g. `eventKitSettleDelay` 200ms, `ReminderStore.swift:372-374`); fire-and-forget `Task {}` inside MainActor class (`ReminderStore.swift:220-225`).
  - View-layer entry points: `.task` (`SingleThread/ContentView.swift:89-92`; `SingleThreadWatch/WatchReminderView.swift:42-44`), `.refreshable { await store.reload(clearSkipped: true) }` (three body branches, `ContentView.swift:309-311`, `:323-325`, `:376-378`), fire-and-forget `Task { await store.reload()/complete… }` from `.onChange` and buttons.
  - Widget: `NextThingWidget.getTimeline` wraps work in `Task {}`, 15-min refresh policy (`SingleThreadWidget/NextThingWidget.swift:43-48`).
  - AppIntents: `@MainActor public func perform() async throws` constructing a fresh store (`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:18-53`).
- The only "remote" transport today is WatchConnectivity: `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:23`, delegate callbacks :203/:215-227), wired in both `App.init`s (`SingleThread/SingleThreadApp.swift:25-70`; `SingleThreadWatch/SingleThreadWatchApp.swift:22-52`).

## Q3: Persistence mechanisms and preview/test injection

### Findings
- **App Group suite**: `group.app.alanvardy.SingleThread` — `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8`; `AppGroup.defaults` falls back to `.standard` on watchOS/previews/unregistered sims (`AppGroup.swift:13-14`). Watch target has no App Group entitlement, so it silently uses `.standard`.
- **UserDefaults wrapper stores in Core** (all same shape: `init(defaults: UserDefaults = AppGroup.defaults, key: String = …)` + load/save):
  - `SkippedReminderStore` — key `"skippedReminderIdentifiers"` (`ReminderSkip.swift:110-134`)
  - `ExcludedProjectStore` — key `"excludedProjectTitles"` (`ExcludedProjectStore.swift:5-27`)
  - `SortOptionStore` — key `"sortOption"`, falls back to `.priority` on unknown raw value (`SortOption.swift:24-52`)
  - `ShowDatePreference` — key `"showDate"`, missing key → `true` (`ShowDatePreference.swift:9-32`)
- **Core never reads UserDefaults directly** ("Core never reads UserDefaults", `ReminderStore.swift:65`); app layers wire hooks like `onSortOptionChanged` (`ReminderStore.swift:69-71`). Production init injects stores: `init(eventStore:skipStore:excludeStore:loadsReminders:)` (`ReminderStore.swift:13-23`).
- **App-level `@AppStorage`** (`ContentView.swift:184-210`): standard defaults — `appearanceMode`, `textSize`, `allowsLandscape` (iOS), `showMicrophoneButton`, `enableActionButtons` (iOS); App Group defaults — `showUndatedReminders`, `sortOption`, `showDate`. Duplicate `@AppStorage("showDate", store: AppGroup.defaults)` in `SingleThreadApp.swift:99-100` so the App observes changes for watch push.
- **File-system/binary storage: none** — no FileManager/NSKeyedArchiver/SwiftData/CoreData anywhere; only in-memory JSON decode of launch args (`UITestingSeed.swift:31-37`).
- **Preview/test injection**: pre-populating init `ReminderStore(loadsReminders:false, reminders:skippedIDs:authorizationStatus:excludedProjectTitles:hasHidden:)` never touches persistence (`ReminderStore.swift:26-40`); mirrored `ContentView` convenience init (`ContentView.swift:17-43`) used by all `#Preview` blocks. Unit tests inject `InMemoryEventStore` (`InMemoryEventStore.swift`) or isolated wrapper-store instances keyed by UUID (e.g. `SkippedReminderSyncServiceTests.swift:43-471`, `AppearanceModeTests.swift:92-94`).

## Q4: Settings toggles end-to-end

### Findings
- All settings state lives as `@AppStorage` in `ContentView`; `SettingsView` owns none of it (doc comment `SettingsView.swift:47-48`). Full key table:

| Key | Type | Default | Store | Decl |
|---|---|---|---|---|
| `appearanceMode` | AppearanceMode | `.system` | .standard | ContentView.swift:184-185 |
| `textSize` | TextSize | `.system` | .standard | ContentView.swift:187-188 |
| `allowsLandscape` (iOS) | Bool | true | .standard | ContentView.swift:191-192 |
| `showMicrophoneButton` | Bool | true | .standard | ContentView.swift:195-196 |
| `enableActionButtons` (iOS) | Bool | false | .standard | ContentView.swift:199-200 |
| `showUndatedReminders` | Bool | false | App Group | ContentView.swift:203-204 |
| `sortOption` | SortOption | `.priority` | App Group | ContentView.swift:206-207 |
| `showDate` | Bool | true | App Group | ContentView.swift:209-210 |

- Excluded projects are *not* `@AppStorage`: bridged via `excludedProjectsBinding` (`ContentView.swift:222-227`) → `ReminderStore.setExcludedProjectTitles` (`ReminderStore.swift:342-350`) → `ExcludedProjectStore.save`.
- SettingsView controls: Pickers for Appearance/Text Size/Sort By (`SettingsView.swift:93-114`), Toggles Allow Landscape (with `.onChange` → `AppDelegate.applyLock`, :116-123), Show Microphone (:124-127), Enable action buttons (:128-132, iOS), Show Undated (:133-136), Show Date (:137-143, `.onChange` → `WidgetCenter.shared.reloadAllTimelines()`), NavigationLink to `ExcludedProjectsView` (:145-153). iOS init takes 10 bindings (:57-69); macOS init drops landscape/action-buttons (:70-84).
- **Footer/attribution**: the only footer in the entire UI is `ExcludedProjectsView`'s `footer: { Text("Excluded projects are hidden…") }` (`SettingsView.swift:30`). There is **no footer or attribution text on the main settings Form today**.
- **Sync**: `SkippedReminderSyncService` pushes WatchConnectivity application-context payload keys: `skippedReminderIdentifiers`, `excludedProjectTitles`, `completeReminderIdentifier`, `deleteReminderIdentifier`, `showUndatedReminders`, `sortOption`, `showDate` (`SkippedReminderSyncService.swift`, PayloadKey ~:232-240). Phone creates service with `sendsShowDate: true` (`SingleThreadApp.swift:28-32`); store hooks `onSkipSetChanged/onShowUndatedRemindersChanged/onExcludedProjectsChanged/onSortOptionChanged` push outbound (`SingleThreadApp.swift:51-63`); `pushShowDate` sends skips+showDate together so keys don't clobber (~:131-142). Watch receives via `didReceiveApplicationContext` (~:190-228), created with `sendsShowDate: false` and `.standard` defaults (`SingleThreadWatchApp.swift:23-27`). Widget reads App Group keys directly (`NextThingWidget.swift:56-63`). Phone-only keys (appearance/textSize/landscape/mic/actionButtons) never reach watch/widget.

## Q5: Failure handling and fallback display states

### Findings
- **Logging chokepoints**: exactly two `Logger` instances, subsystem `"app.alanvardy.SingleThread"` — ReminderStore category (`ReminderStore.swift:353`, used at complete/delete/add failures :153/:179/:213) and ReminderSync category (`SkippedReminderSyncService.swift:244`, seven call sites). Only non-Logger logging is bare `print` in AppDelegate (`AppDelegate.swift:41,46`). No third-party logging, no NSLog.
- **Typed-error pattern (dictation)**: `DictationError` enum — Error + LocalizedError + Sendable, four cases with human-readable `errorDescription` (`SingleThread/ReminderDictation.swift:202-217`); thrown at guards :60, :62, :149, :102/:105, :191; bridged via `withCheckedThrowingContinuation` + `ResumptionGate` single-resume gate (:145-196). The view consumes errors as strings: `catch { dictationError = error.localizedDescription }` (`ContentView.swift:535-537`); rendered as red caption above bottom bar (:392-397).
- Swift `Result<Success, Failure>` is unused repo-wide; failure styles are `throws`/do-catch and Bool returns. (`ReminderDictationParser.Result` is a plain value struct, not Swift's Result.)
- **Empty states**: auth gate — ProgressView / ContentUnavailableView "Reminders Access" (`ContentView.swift:280-291`); copy factories `emptyStateCopy(hasHidden:)` → "Nothing due"/"No Reminders" (:131-141) and `allDoneStateCopy()` → "All Done" (:144-151); three reminderList branches: all-skipped ScrollView w/ pull-to-refresh clear (:299-310), empty list (:313-327), card List (:328+). `hasHidden` maintained by store (`ReminderStore.swift:44-49`, :270-283).
- **Failure semantics that already implement "keep previous value on failure"**:
  - `completeReminder`/`deleteReminder`: log-only catch; observable state mutated *after* save succeeds, so failures leave previous state untouched (`ReminderStore.swift:141-183`).
  - `addReminder -> Bool` `@discardableResult` returning false on caught error; caller drives feedback UI (`ReminderStore.swift:193-215`; `ContentView.swift:522-533`).
  - Sync service persists locally before throwing WCSession push, then logs — local state survives sync failure (`SkippedReminderSyncService.swift:120-121` etc.).
- View-side transient fallback precedent: `dictationError` / `creationFeedback` `@State` pair self-clearing after ~1s (`ContentView.swift:213-214`, :392-406, :528-534). Note: `dictationText = ""` is cleared before transcription starts (`ContentView.swift:515`).

## Q6: Testing seams and accessibility audit

### Findings
- **Protocol seam**: `@MainActor protocol EventKitStoring: AnyObject` (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:7-42`); production passthrough `extension EKEventStore: EventKitStoring` (:44-60); injected via `ReminderStore(eventStore:)` default-to-production init (`ReminderStore.swift:13-21`).
- **Test fakes**: `FakeEventStore` (recording fake with `saveShouldThrow`/`removeShouldThrow`, `SingleThreadTests/EventKitStoringTests.swift:8-103`) used by Swift Testing suites `@MainActor @Suite(.serialized)` (:107+, :216+, :322+). `InMemoryEventStore` (`SingleThreadCore/.../InMemoryEventStore.swift:13-118`) reports `.fullAccess`, mutates its array on save/remove, optional off-main completion delivery flag for concurrency tests.
- **`--seed '<json>'` seam**: `UITestingSeed.fromLaunchArguments` parses `{reminders:[{title,notes,priority}], calendars:[], excludedProjects:[]}` (`UITestingSeed.swift:10-79`); app wiring `makeStore(arguments:)` calls `UITestingSeed.resetPersistedState()`, builds `InMemoryEventStore`-backed `ReminderStore`, skips WatchConnectivity when seeded (`SingleThreadApp.swift:105-125`). Fallback `--ui-testing` seeds one hardcoded reminder with `loadsReminders: false` and writes `enableActionButtons=true` to `.standard` (`SingleThreadApp.swift:113-124`); `--no-reminders` is a third manual flag used by appearance launch tests.
- **`UITestingSeed.resetPersistedState()`** removes nine persisted keys (`skippedReminderIdentifiers`, `excludedProjectTitles`, `showDate`, `showUndatedReminders`, `sortOption`, `showMicrophoneButton`, `allowsLandscape`, `textSize`, `appearanceMode`) from both `AppGroup.defaults` and `.standard` (`UITestingSeed.swift:41-61`). Unit coverage in `UITestingSeedTests.swift:14-58`.
- **UI flows** (`SingleThreadUITests/SingleThreadUITestsFlows.swift`): launch args `["--seed", json]` helper (:21-25); covers list rendering, empty state, Skip/Complete swipes, Delete via context menu, Settings sheet controls (:27-115). Watch equivalents use `--ui-testing` / `--ui-testing-excluded <project>` (`SingleThreadWatchUITestsFlows.swift:27`).
- **Accessibility audit** (`SingleThreadUITests/SingleThreadUITests.swift:30-63`): runs `performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` locally; **contrast and textClipped deliberately excluded** (comment :45-46); on CI only `[.sufficientElementDescription, .trait]` run (runner hangs, :48-54). Implication for layered visuals: hit regions, dynamic type scaling, labels, and traits ARE enforced over layered backgrounds; color contrast between layers is NOT tested anywhere.

## Cross-Cutting Observations

- Layering convention: single root `ZStack` with a full-bleed `ignoresSafeArea` background first child; chrome via `ZStack(alignment:.bottom)` and `.overlay`, never `safeAreaInset` (`ContentView.swift:61-383`).
- Appearance is applied at UIWindow level and re-applied on every activation — any new background color participates in light/dark automatically; no per-view theming exists.
- Persistence convention: thin `init(defaults:key:)` wrapper structs bound to `AppGroup.defaults` by default, injected into `ReminderStore`; Core never touches UserDefaults directly; phone-only cosmetic settings use `.standard`, cross-surface settings use the App Group suite.
- Async convention: `@MainActor @Observable` store with async methods, kicked off via `.task`/`.refreshable`/fire-and-forget `Task {}`; callback APIs bridged with `withCheckedContinuation` + `ResumptionGate` resuming on MainActor. No networking precedent — remote fetch would be greenfield but has a well-defined store/hook pattern to slot into.
- Failure convention: mutate observable state only after the throwing operation succeeds; catch → Logger (subsystem `app.alanvardy.SingleThread`) → keep prior state; user-visible feedback via transient string `@State`.
- Test convention: every feature ships unit tests (Swift Testing, injected fakes/isolated defaults suites) + UI tests (XCTest driven through `--seed`/`--ui-testing` seams); accessibility audit guards layered visuals except contrast.
- HEAD commit on this branch contains only a DELETEME placeholder — no background implementation exists yet.

## Open Areas

- No existing remote-image/network-download code or caching conventions exist to mirror; anything fetched would define the codebase's first networking path (including its persistence format, since there is currently no file-system storage at all).
- Whether a downloaded background should participate in the window-level appearance override (dark vs light variant selection) has no existing precedent beyond how `Color.systemBackground` resolves variants.
- Widget/watch rendering of a background was not researched in depth (watch reads `.standard` defaults; widget reads App Group) — relevant only if the feature must span surfaces.
