# Research Findings — Mic button visibility (VAR-747)

## Q1: Complete decision chain for mic-button rendering

### Findings

- Entry gate: `ContentView.body` is a `ZStack` (`SingleThread/ContentView.swift:67-80`). `if viewModel.store.loadsReminders { authGatedContent } else { reminderList }` (`ContentView.swift:76-80`). The mic only exists inside `reminderList`; it is unreachable whenever `loadsReminders == true` unless EventKit authorization is `.fullAccess`.
- `authGatedContent` (`ContentView.swift:333-343`) switches on `viewModel.store.authorizationStatus` (EKAuthorizationStatus, not speech): `.notDetermined` → `ProgressView("Requesting access…")` with **no bottom bar** (`:335-336`); `.fullAccess` → `reminderList` (`:338`); default `.denied`/`.restricted` → `ContentUnavailableView("Reminders Access", lock.shield, "Enable access in Settings…")` with **no bottom bar** (`:339-341`).
- `reminderList` (`ContentView.swift:347`) has three branches:
  - `allSkipped` (`!reminders.isEmpty && visibleReminders.isEmpty`, `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:127-130`): "All Done" `ContentUnavailableView` in a ScrollView — **no `bottomBar` call at all** (`ContentView.swift:352-367`).
  - `reminders.isEmpty`: empty-state view inside `ZStack(alignment: .bottom)` **with `bottomBar`** (`ContentView.swift:369-379`).
  - else: `List` inside `ZStack(alignment: .bottom)` **with `bottomBar`** (`ContentView.swift:381-449`).
- `bottomBar` (`ContentView.swift:455-495`) is a `VStack(spacing: 8)` rendering top-to-bottom:
  1. **macOS-only** hand-rolled Complete/Skip/Delete cluster when `visibleReminders.first != nil` (`ContentView.swift:457-463`, buttons at `:288-329`).
  2. **Error banner** — standalone `if let error = viewModel.dictation.dictationError` red caption (`ContentView.swift:462-468`). Not part of the else-chain: it renders *above* and *alongside* the mic, not instead of it.
  3. **Mutually exclusive `if/else if` chain** (`ContentView.swift:469-492`), priority order:
     - `creationFeedback` non-nil → `creationFeedbackView(for:)` success/failure icon (`:469-470`, body at `:624-632`) — *replaces* the mic while shown (~1 s, `DictationViewModel.swift:51-52`).
     - else `isDictating` → live transcript `Text` + pulsing red `recordingIndicator` (`:471-479`, indicator at `:550-556`) — *replaces* the mic while recording.
     - else `canDictate, showMicrophoneButton` → platform branch (`:480-492`):
       - iOS: `if !viewModel.store.canMutate { upgradePrompt }` (`:482-483`); else `if viewModel.showsActionButtons { actionCluster }` (`:484-485`, cluster at `:522-527` = completeButton + **micButton** + skipButton); else plain `micButton` (`:486-487`, at `:538-547`). The mic is *not* removed by the action-buttons gate — it stays inside the cluster; it is removed by the freemium gate and by the whole `canDictate && showMicrophoneButton` gate.
       - non-iOS (macOS): plain `micButton`, no freemium/action-buttons check (`ContentView.swift:489-491`).
- Gate definitions:
  - `canDictate` = `speechTranscriber.authorizationStatus == .authorized || == .notDetermined` (`SingleThread/DictationViewModel.swift:27-30`).
  - `showMicrophoneButton` = `@AppStorage("showMicrophoneButton")` default `true`, **`UserDefaults.standard`** suite (`ContentView.swift:190-191`).
  - `canMutate` = `entitlementStore.isEntitled || completionCounter.count < 100` (`ReminderStore.swift:132-134`); counter (`CompletionCounterStore`, key `completionCount`, App Group defaults, `SingleThreadCore/Sources/SingleThreadCore/CompletionCounterStore.swift:12-15`) increments once per successful non-watchOS EventKit save (`ReminderStore.swift:185`); `isEntitled` from StoreKit 2 `Transaction.updates`/`currentEntitlements` (`SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift:5-31`).
  - `showsActionButtons` = iOS-only: `UserDefaults.standard.bool(forKey: "enableActionButtons") && store.visibleReminders.first != nil` (`SingleThread/ContentViewModel.swift:40-49`).
- Separate UI: the undo button overlay is gated by `hasUndoableReminder, showUndoButton, canMutate` (`ContentView.swift:99`) and the settings gear is always present (`ContentView.swift:83-96`) — neither interacts with the mic gate.

## Q2: Speech-recognition authorization status

### Findings

- Seam: `SingleThread/AuthorizationRequiring.swift:1-27` — `@MainActor protocol AuthorizationRequiring` (`:9-13`) plus production `SpeechAuthorizationRequiring.requestAuthorization` which is the **only** direct call to `SFSpeechRecognizer.requestAuthorization` in the repo (`:19-21`).
- Protocol: `SpeechTranscribing` exposes `var authorizationStatus: SFSpeechRecognizerAuthorizationStatus` (`SingleThread/ReminderDictation.swift:10-11`) and `requestAuthorization() async` (`:13`).
- Ownership: `ReminderDictation` (`@MainActor @Observable`, `ReminderDictation.swift:22-24`) stores `private(set) var authorizationStatus` (`:37`), **seeded once at init** from `SFSpeechRecognizer.authorizationStatus()` (`:32`; init at `:27-33`). `requestAuthorization()` (`:41-53`) wraps the callback API in `withCheckedContinuation`, hops back to the main actor via `resumeOnMainActor` (`:46-48`; helper in `SingleThreadCore/Sources/SingleThreadCore/ResumptionGate.swift:46-52`), then writes the returned status (`:51-52`).
- Read path: `DictationViewModel.canDictate` reads `speechTranscriber.authorizationStatus` (`DictationViewModel.swift:27-30`); `ContentView` never touches the enum directly (only `import Speech` at `ContentView.swift:8`; the view reads `viewModel.dictation.canDictate` / `dictationError`).
- Per-state behavior:
  - `.notDetermined` → `canDictate == true`, **mic renders and is tappable**; `startDictation()` first awaits `requestAuthorization()` (`DictationViewModel.swift:23-26`), then `guard status == .authorized else { dictationError = "Speech recognition access is required." }` (`:27-30`).
  - `.authorized` → `canDictate == true`, direct to transcription (`DictationViewModel.swift:31-35`).
  - `.denied` / `.restricted` → `canDictate == false`, mic suppressed; tapping is impossible because the button doesn't render. If a prior tap caused the denial, the error text persists: `dictationError = "Speech recognition access was denied."` (`DictationViewModel.swift:38-40`).
- Status surfaces as **error text only** (red caption in `bottomBar`, `ContentView.swift:462-468`). There is no dedicated authorization-status UI, no Settings deep link, and no explanation when the mic is suppressed beyond that error string; the error is cleared on the next successful dictation start (`DictationViewModel.swift:36`).
- Staleness: `authorizationStatus` is a snapshot captured at `ReminderDictation.init` (`ReminderDictation.swift:32`) and only refreshed by an explicit `requestAuthorization()` call — there is no app-activation/foreground re-read. A re-created `ReminderDictation` (see Q6) re-seeds from the live system status.

## Q3: `showMicrophoneButton` storage, sync, and cross-install divergence

### Findings

- Sole persistence: `@AppStorage("showMicrophoneButton") private var showMicrophoneButton = true` (`SingleThread/ContentView.swift:190-191`). **No `store:` argument → `UserDefaults.standard`**, NOT the App Group suite. Default is the property initializer `true`.
- **No `UserDefaults.register(defaults:)` exists anywhere in the repo** (repo-wide grep: zero `register(defaults:)` calls). The `true` default lives only in the `@AppStorage` initializer and the `SettingsBindings` doc-mirror (`SingleThread/SettingsBindings.swift:29, 48, 71`), so any code path that reads the raw key (e.g. `UserDefaults.standard.bool(forKey:)`) gets `false` when unset. `UITestingSeed.resetPersistedState()` removes the key and the others in its list from **both** `AppGroup.defaults` and `.standard` (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:40-66, 68-93`; `showMicrophoneButton` listed at `:81`).
- Settings plumbing (iOS + macOS): bag built from live `@AppStorage` values on gear tap (`makeSettingsBag`, `ContentView.swift:640-677`, mic value read at `:651` iOS / `:666` macOS), presented via `.sheet` (`:169-171`), bag nilled on dismiss (`:164-170`), write-back via `.onChange(of: bag.showMicrophoneButton) { _, new in showMicrophoneButton = new }` (`ContentView.swift:612`). Toggle: `InterfaceSettingsView.swift:55-57` — `Toggle("Show microphone", …)` **not** wrapped in `#if os(iOS)`, so it exists on macOS too (wired at `SingleThread/SettingsView.swift:41` iOS / `:50` non-iOS).
- **Not synced anywhere**: `showMicrophoneButton` is absent from the WatchConnectivity payload keys (`SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:266-280`; synced keys are only skip IDs, excluded lists, show-undated, sort, showDate/List/Recurrence/Alarms/CompletionGlow, completionCount, isEntitled). There is **no NSUbiquitousKeyValueStore / CloudKit / iCloud sync** in the repo (only a doc string at `SingleThread/PrivacySettingsContent.swift:25`). The mic toggle is produced by the user on each install independently.
- Watch target has **no `CODE_SIGN_ENTITLEMENTS`**, so `UserDefaults(suiteName:)` is nil there and `AppGroup.defaults` falls back to `.standard` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8-14`; pbxproj watch configs `SingleThread.xcodeproj/project.pbxproj:946, 974`). iOS/macOS app and widget use `group.app.alanvardy.SingleThread` (`SingleThread/AppGroup.entitlements`, `SingleThread/SingleThread.entitlements`; pbxproj:732-734, 782-784, 992, 1023).
- Cross-install divergence: because the value is stored under `UserDefaults.standard` in the app sandbox, is never syncable, and its only default is a property-initializer literal (no registration), two installs on the same account have **independent copies** — one can be `false`, the other unset (rendered as `true` by `@AppStorage`, but `false` to any raw `bool(forKey:)` read). Nothing in the codebase mirrors it to the other install.
- Contrast: other prefs do use the App Group suite (`showUndatedReminders`, `sortOption`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow` — `ContentView.swift:200-216`), and those are the ones the watch sync pushes.

## Q4: Platform/config conditions that affect whether dictation *works*

### Findings

- SFSpeechRecognizer creation: lazily at first transcription — `@ObservationIgnored private lazy var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: locale)` with `locale = .current` by default (`SingleThread/ReminderDictation.swift:28, 89`).
- Render-time capability checks: **none**. At render the only dictation condition is `canDictate` (authorization enum, `DictationViewModel.swift:27-30`) + the toggle. The recognizer's availability is checked only at transcribe time: `guard let recognizer = speechRecognizer, recognizer.isAvailable else { throw DictationError.recognizerUnavailable }` (`ReminderDictation.swift:61-63`, error text "Speech recognition is not available." at `:214`). A nil `SFSpeechRecognizer(locale:)` (unsupported locale) surfaces only as this error at tap time.
- Locale / on-device: `SFSpeechRecognizer.supportedLocales()` and `supportsOnDeviceRecognition` are **never consulted** anywhere in the repo (zero matches), even though `request.requiresOnDeviceRecognition = true` is hard-set (`ReminderDictation.swift:120`).
- Microphone permission: `ensureMicrophoneAccess()` (`ReminderDictation.swift:96-109`) checks `AVCaptureDevice.authorizationStatus(for: .audio)`; notDetermined → `requestAccess`, denied/restricted → `DictationError.microphoneDenied` ("Microphone access was denied.", `:215`). Also only at transcribe time.
- Audio session: `#if os(iOS)` only — `AVAudioSession.setCategory(.record, mode: .measurement, options: .duckOthers)` + `setActive` in `prepareRecording` (`ReminderDictation.swift:112-116`), deactivated in `tearDownRecording` (`:140-142`).
- Usage descriptions: no physical Info.plist for app/watch/tests targets — `GENERATE_INFOPLIST_FILE = YES` everywhere (`project.pbxproj:743, 793, 834, 863, 891, 915`; only `SingleThreadWidget/Info.plist` exists on disk). `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are set via `INFOPLIST_KEY_…` on the app target, **without an SDK suffix, so they apply to the macOS build too** (`project.pbxproj:744, 746` and `794, 796`). `NSRemindersUsageDescription` at `:745` / `:795`; the watch target only declares `NSRemindersFullAccessUsageDescription` (`:942, 970`) — no speech/mic keys on watchOS.
- Deployment/platform: app target builds `iphoneos iphonesimulator macosx` — `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, `MACOSX_DEPLOYMENT_TARGET = 26.5` (`project.pbxproj:757, 760, 807, 810`); watch target `WATCHOS_DEPLOYMENT_TARGET = 26.5` (`:957, 985`).
- Entitlements: app-group entitlement only (`com.apple.security.application-groups` = `group.app.alanvardy.SingleThread`) — no special speech/audio entitlement (none required for SFSpeechRecognizer).

## Q5: Mic visibility across platforms

### Findings

- iOS (iPhone/iPad): full `bottomBar` chain as in Q1 — mic → `upgradePrompt` (freemium, when `!canMutate`, `ContentView.swift:482-483`) → `actionCluster` (when `showsActionButtons`, `:484-485`) → `micButton` (`:486-487`). Placeholders when the mic is suppressed:
  - Freemium gate: `UpgradePromptButton` (`ContentView.swift:529-533`) — full-width capsule `Label("Upgrade to unlimited", systemImage: "lock.fill")` opening the `PurchaseSheet` (`SingleThread/PurchaseSettingsView.swift:173-192`; sheet at `ContentView.swift:172-174`).
  - Action-buttons gate: the mic is *kept* inside the Complete/mic/Skip `actionCluster` (`ContentView.swift:522-527`) — a change in this toggle does not remove the mic.
  - `canDictate == false` or toggle off or EventKit-gated: nothing replaces the mic — the bottom bar renders only the error text if any (`ContentView.swift:462-468`), and if EventKit is not `.fullAccess` there is no bottom bar at all (`:333-343`).
- macOS (same app target): `bottomBar` renders the mac action cluster above the error/mic block (`ContentView.swift:457-463`); the mic renders as plain `micButton` under only `canDictate && showMicrophoneButton` — the freemium and action-buttons gates are `#if os(iOS)`-only (`ContentView.swift:489-491` vs `:481-488`). The "Show microphone" toggle still exists on macOS (`InterfaceSettingsView.swift:55-57`, wired at `SettingsView.swift:50`). No `SFSpeechRecognizer` platform-gating: `prepareRecording`'s only `#if os(iOS)` parts are the AVAudioSession calls (`ReminderDictation.swift:112-116, 140-142`).
- watchOS: **no dictation/mic affordance exists** — zero SFSpeechRecognizer/speech/`showMicrophoneButton` references in `SingleThreadWatch/`. The watch renders Complete/Skip right-side actions (`SingleThreadWatch/WatchReminderView.swift:106-126`) and, when `!store.canMutate && !entitlementState.isEnabled`, an "Upgrade on your iPhone" prompt (`WatchReminderView.swift:132-138, 211-212`) with no StoreKit surface; refresh buttons at `:182-205`. The watch consumes settings only for the show-*/sort keys via the sync service.
- Widget: `SingleThreadWidget/NextThingWidget.swift` renders the next reminder with Complete/Skip buttons via an AppIntent (`:116, 123` families) and `lock.shield` gating states (`:139`) — no mic, no settings, no speech.

## Q6: Test coverage, lifecycle, and stale-state risk

### Findings

- `SingleThreadTests/MicrophoneToggleTests.swift` — the only dedicated mic-visibility suite (fake transcriber `MicToggleFakeTranscriber` presets `authorizationStatus`, `:9-24`):
  - `settingsGearButtonIsPresent` (`:36-49`, asserts `"Settings"` in body string).
  - `micButtonHiddenWhenSpeechDenied` (`:53-70`) — `.denied` fake; with toggle stored `true`, `String(describing: view.body)` does **not** contain `"mic.fill"` (`:69`). **The one test genuinely asserting mic absence.**
  - `micButtonAbsentWhenToggleOff` (`:74-89`) — `.authorized`, toggle `false`; asserts only that body doesn't crash, **never asserts the mic is absent**.
  - `micButtonWithToggleEnabledDoesNotCrash` (`:90-104`) — asserts no crash only. No test asserts the mic is **present** in a render.
- `SingleThreadTests/ReminderDictationTests.swift`: fake transcriber (`:10-55`), `DetachedAuthorizationRequiring` delivering the callback off-main (`:67-89`); assert authorization call record/presets (`:100-109`), main-actor resumption (`:113-118`), `canDictate` true for `.authorized` fakes (`:171-199`), happy-path start→add→text flow (`:192-206`), and `DictationError` non-nil descriptions (`:212-231`) — message presence only, no path that produces them.
- `SingleThreadTests/ActionButtonTests.swift` — `showsActionButtons` toggle/visible/skipped/empty cases (`:34-88`), fake transcriber default `.authorized` (`:114-129`); comment `:11-17` says the rendered cluster (mic included) is deliberately left to UI tests.
- `SingleThreadTests/SettingsViewTests.swift:56-80` — asserts the settings form contains the static text "Show microphone" (`:77`); no toggle interaction.
- `SingleThreadTests/UITestingSeedTests.swift` — seed parse (`:21-62`), seeded store yields EventKit `.fullAccess` (`:79-82`), `resetPersistedState()` clears keys incl. `showMicrophoneButton` from both suites (`:90-118`; key list `UITestingSeed.swift:68-93`).
- UI tests (`SingleThreadUITests/ActionButtonsUITests.swift`): drive the action-buttons cluster via the `--ui-testing` / `--seed` seams (`AppViewModel.swift:236-258` forces `enableActionButtons = true`; `seededStore` at `:281-309` also sets it). No UI test asserts mic visibility or authorization-state transitions; no test exercises `.restricted` or `.notDetermined` rendering, the freemium `upgradePrompt` swap, or the `micButtonHidden` path with a *real* authorization status. `treatStoredBooleanAs…` — there is no UI seam to force an authorization state: tests can only preset fakes at the unit level.
- Lifecycle / stale state: `AppViewModel.contentViewModel` is a **computed property** that builds a fresh `ContentViewModel(store:backgroundImage:speechTranscriber: ReminderDictation())` **on every access** (`SingleThread/AppViewModel.swift:198-205`; "Rebuilt on demand" comment `:198-199`). `SingleThreadApp.body` calls it once per app-scene body evaluation (`SingleThread/SingleThreadApp.swift:17-21`) and the result is captured in `ContentView`'s stored `private let viewModel` (`ContentView.swift:54, 71`), so *within* a given ContentView's lifetime body re-evaluations reuse the same instance. A new `ContentView` (scene re-creation) gets a fresh `ContentViewModel` → fresh `DictationViewModel` → fresh `ReminderDictation` whose `authorizationStatus` **re-seeds from the live system status at init** (`ReminderDictation.swift:32`). In-flight dictation state (`isDictating`, `dictationText`, `dictationError`) is dropped when the VM is rebuilt. Within a single `ReminderDictation` lifetime, `authorizationStatus` can go stale if the user changes the system permission while the app runs (no foreground re-read; see Q2).

## Cross-Cutting Observations

- Three unrelated gates stack to hide the mic, in order: (1) EventKit `.fullAccess` (whole list/bottom bar), (2) `dictation.canDictate && showMicrophoneButton` (mic slot), (3) iOS-only `canMutate` (freemium upgrade prompt) then `showsActionButtons` (cluster keeps the mic). Only gates 2–3 are about the mic itself; gate 1 removes the entire UI.
- `notDetermined` is intentionally treated as "can dictate" — speech authorization is requested lazily on first tap, and the mic is visible before any speech permission exists.
- Settings persistence has two tiers: App-Group-backed + watch-synced preferences (`showDate`/`showList`/`showRecurrence`/`showAlarms`/`showCompletionGlow`/`showUndatedReminders`/`sortOption`) versus plain-`UserDefaults.standard` + never-synced preferences (`showMicrophoneButton`, and iOS-only `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `allowsLandscape`, notifications). `showMicrophoneButton` is squarely in the never-synced tier.
- Defaults are expressed as @AppStorage property initializers, never `register(defaults:)`; the `SettingsBindings` init defaults mirror them in-memory only (`SettingsBindings.swift:3-8, 29`).
- The sync payload key list (`SkippedReminderSyncService.swift:266-280`) is the canonical inventory of what crosses devices; mic is absent; the App Group suite is the canonical inventory of app↔widget sharing and is per-install, not cross-device.
- All dictation capability checks (`isAvailable`, locale support, on-device support, microphone permission) are deferred to tap time (`ReminderDictation.swift:60-64, 96-109`); render time consults only the authorization enum snapshot.

## Open Areas

- Why the mic "is not visible" on a specific device can't be pinned from code alone: the item is a `UserDefaults.standard`-resident toggle whose offline default is `true` but whose value diverges per install (Q3), layered on speech-authorization state that is only refreshed on demand (Q2/Q6).
- The exact re-evaluation frequency of `SingleThreadApp.body` (and thus how often `contentViewModel` rebuilds in production on iOS/macOS) is not visible from the codebase.
- No test or launch-arg seam can force a `.denied`/`.restricted` speech status in UI tests — only unit-level fakes cover those states.