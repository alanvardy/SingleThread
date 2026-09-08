# Research Findings

## Q1: `ReminderDictation.requestAuthorization()` — callback→async transfer, invocation, and UI consumption

### Findings
- Bridge shape: `func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus` on `@MainActor @Observable final class ReminderDictation: SpeechTranscribing` (`SingleThread/ReminderDictation.swift:22-24`, `:38`).
  - Body: `let status = await withCheckedContinuation { continuation in … }` (`ReminderDictation.swift:39`).
  - Inside: `SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }` (`ReminderDictation.swift:40-41`). The completion handler resumes the continuation **directly, no dispatch/Task hop** — the only bridging construct is `withCheckedContinuation`.
  - After `await`: `authorizationStatus = status` then `return status` (`ReminderDictation.swift:44-45`).
- Seed: `init(locale:)` sets `authorizationStatus = SFSpeechRecognizer.authorizationStatus()` synchronously (`ReminderDictation.swift:27-29`).
- `private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus` (`ReminderDictation.swift:34`) — externally read-only, written only in `init`/`requestAuthorization()`.
- Protocol seam `@MainActor protocol SpeechTranscribing: AnyObject` exposes `authorizationStatus {get}` and `requestAuthorization()` (`ReminderDictation.swift:9-16`).
- Caller: `ContentView.startDictation()` (`SingleThread/ContentView.swift:501`) — `if .notDetermined` → `await speechTranscriber.requestAuthorization()` (`ContentView.swift:502-503`), then `guard status == .authorized` else `dictationError = "Speech recognition access is required."` (`ContentView.swift:504-507`).
- Wiring: `private let speechTranscriber: any SpeechTranscribing` (`ContentView.swift:221`), defaulted `speechTranscriber ?? ReminderDictation()` in all three inits (`ContentView.swift:13,18,37`).
- UI consumption: `canDictate` = `.authorized || .notDetermined` (`ContentView.swift:233-236`); `bottomBar` gating `else if canDictate, showMicrophoneButton` (`ContentView.swift:410`) → `actionCluster`/`micButton` on iOS (`:411-416`) / `micButton` otherwise (`:417-418`); post-request `.authorized` re-guard (`ContentView.swift:509-511`).

## Q2: Crash-frame meaning and speech-framework callback queue

### Findings
- Frame chain (given): `_dispatch_assert_queue_fail` ← `dispatch_assert_queue` ← `swift_task_isCurrentExecutorWithFlagsImpl` ← `ReminderDictation.requestAuthorization()` closure ← TCC. These are Swift 6 runtime executor-isolation checks against the main dispatch queue; the MainActor executor is `DispatchQueue.main`.
- `ReminderDictation.swift:41` resumes the continuation **inside the framework completion handler** with no hop, so the runtime asserts the resume runs on the MainActor's queue. A background delivery trips the assert (trap / EXC_BREAKPOINT) before isolated state is touched.
- Apple docs state `SFSpeechRecognizer.requestAuthorization(_:)` does **not** guarantee its completion block runs on your app's main dispatch queue. Sources: [requestAuthorization(_:) — Apple](https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:)#discussion); Swift 6 isolation discussion [Issue #1037 · onmyway133/blog](https://github.com/onmyway133/blog/issues/1037#1); [Swift Forums — back to actor-isolated context after a queue dispatch](https://forums.swift.org/t/how-do-i-get-back-to-actor-isolated-context-after-dispatching-to-a-queue/75389).
- The repo itself never names the speech callback queue; no in-repo line states it. The TCC attribution rests on the crash stack + absence of a hop at `ReminderDictation.swift:41`.
- Contrast: `awaitFinalResult` (transcript path) **does** hop — `@Sendable` callback (`ReminderDictation.swift:151`), off-actor extraction (`:152-157`), `Task { @MainActor in }` before resuming (`:158`) and before the timeout resume (`:178`). The authorization path (`:40-41`) omits this hop — the only direct inline resume in the dictation file.

## Q3: Swift concurrency / actor isolation configuration per target

### Findings (verified against `SingleThread.xcodeproj/project.pbxproj`)
- Settings live in per-target/project `XCBuildConfiguration` blocks; `XCConfigurationList` (`project.pbxproj:1019-1083`) links each target to its Debug/Release config IDs.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — only two targets:
  - SingleThread iOS app: Debug `project.pbxproj:697`, Release `:747` (configs `51AA3EFA/` `51AA3EFB`).
  - SingleThreadWatch: Debug `:873`, Release `:901` (configs `51AA3F2B`/`51AA3F2C`).
  - Not set on SingleThreadTests/UITests, WatchUITests, Widget, or the SingleThreadCore package.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` + `SWIFT_VERSION = 6.0` on all 12 target configs (none at project level): iOS `:696/:700`, `:746/:750`; SingleThreadTests `:771/:774`, `:796/:799`; UITests `:820/:823`, `:844/:847`; watch `:872/:875`, `:900/:903`; widget `:932/:935`, `:963/:966`; WatchUITests `:984/:986`, `:1007/:1009`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — project-level only: Debug `project.pbxproj:596`, Release `:651` (configs `51AA3EF7`/`51AA3EF8`; PBXProject list `51AA3ED1` at `:389`).
- `SingleThreadCore` is a local Swift package: `XCLocalSwiftPackageReference` (`project.pbxproj:1085-1090`) + `XCSwiftPackageProductDependency` (`:1092-1097`). Package file `SingleThreadCore/Package.swift`: `swift-tools-version: 6.0`, iOS/watchOS/macOS platforms, `.target(name: "SingleThreadCore")`. It does not set `SWIFT_DEFAULT_ACTOR_ISOLATION`.
- Documented convention (`AGENTS.md:48-58`): app/watch targets default async functions to `@MainActor` (no need to wrap in `Task { @MainActor in }`); package, tests, widget, UI tests do not default-isolate and must annotate `@MainActor` explicitly.

## Q4: Patterns for resuming continuations / re-rooting framework callbacks onto the main actor

### Findings
- **Pattern A — inline `withCheckedContinuation` resume from the framework callback (no hop):**
  - `ReminderDictation.requestAuthorization()` (`ReminderDictation.swift:39-42`).
  - `ReminderStore.fetchReminders(matching:)` via `await withCheckedContinuation { CheckedContinuation<[EKReminder], Never> in … eventStore.fetchReminders(matching:) { reminders in continuation.resume(returning: reminders ?? []) } }` (`SingleThreadCore/ReminderStore.swift:371-374`). Thread note: "`fetchReminders(matching:)` performs its work off the main thread" (`ReminderStore.swift:368-369`).
- **Pattern B — explicit `Task { @MainActor in }` hop before touching state / resuming:**
  - Recognition callback `Task { @MainActor in … continuation.resume … }` (`ReminderDictation.swift:155-158`); comment "Extract Sendable values before hopping to the main actor" (`:152`).
  - Timeout `Task { @MainActor [weak self] in … }` (`ReminderDictation.swift:178`).
  - `ResumptionGate: @unchecked Sendable { var hasResumed = false }` guards single-resume (`ReminderDictation.swift:144-147`), set before each resume (`:161`, `:171`, `:182`).
- **Pattern C — `nonisolated(unsafe)` hooks (write-once-before-activate), re-rooted in the app layer:**
  - `SkippedReminderSyncService.swift` declares `public nonisolated(unsafe) var onCompleteReminderReceived: ((String) -> Void)?` and three siblings. Comment (`:41-44`): run on WCSession's delegate queue; closures bound before `activate()` form the happens-before edge.
  - App re-rooting: `SingleThreadApp.swift:37-44` `onCompleteReminderReceived = { [weak store] identifier in Task { await store?.completeReminder(identifier:) } }` (+ delete variant).
  - Watch app `SingleThreadWatchApp.swift:26-36` hoists show-undated/sort into `Task { await store?.reload() }`.
- **Pattern D — `@retroactive @unchecked Sendable` retrofit:**
  - `extension EKReminder: @retroactive @unchecked Sendable {}` (`SingleThreadCore/ReminderDateFilter.swift:23`) — load-bearing for resuming `CheckedContinuation<[EKReminder], Never>` across EventKit's completion queue and for file-scoped mock globals in non-isolated targets. Safety invariant: "every EKReminder is created, mutated, and read only on the @MainActor … never pass across a Task.detached or nonisolated boundary" (`:15-19`).
- **Pattern E — `@Sendable` completion widget API:**
  - `SingleThreadWidget/NextThingWidget.swift:34-39` `getSnapshot(completion: @escaping @Sendable (NextThingEntry) -> Void)` completes synchronously; `getTimeline` (`:42-47`) wraps async work in `Task { … }`; doc notes widget target lacks default isolation, explicit `@MainActor` (`:48-49`).

## Q5: Dictation/authorization interactive flow and test seams

### Findings
- Real path (`ReminderDictation.swift`) — actual on-device `SFSpeechRecognizer` + `AVAudioEngine` + `AVCaptureDevice` — is **not** instantiated in any test. Repo-wide `ReminderDictation(` appears only in production nil-defaulting (`ContentView.swift:13,18,37`).
- Tests inject fakes through `SpeechTranscribing`; all fakes are `@MainActor`:
  - `FakeSpeechTranscriber.requestAuthorization()` — counter + stored status (`SingleThreadTests/ReminderDictationTests.swift:36-39`); `transcribe` delivers preset/partial text or throws (`:41-63`).
  - `MicToggleFakeTranscriber` (`SingleThreadTests/MicrophoneToggleTests.swift:11-26`); `ActionButtonFakeTranscriber` (`SingleThreadTests/ActionButtonTests.swift:14-27`).
- Authorization unit tests: `fakeRecordsAuthorizationCall` only calls `fake.requestAuthorization()` (`ReminderDictationTests.swift:74-80`); `DictationErrorTests.errorDescription` checks `.alreadyRecording`/`.recognizerUnavailable`/`.microphoneDenied`/`.noSpeechDetected` (`:151-169`). None drive the real continuation path.
- Mic gating covered only indirectly: `micButtonHiddenWhenSpeechDenied` asserts body description excludes the `mic.fill` icon (`MicrophoneToggleTests.swift:49-66`, body-string match). `canDictate` is a private computed property, not asserted directly.
- `startDictation()` branches (`ContentView.swift:501-538`): `.notDetermined → requestAuthorization` and `.authorized` deny branches (`:502-511`) are **uncovered**; `startDictation` is `private`. **No Swift unit or UI test invokes the real `ReminderDictation` continuation path.**
- UI tests (`SingleThreadUITests/ActionButtonsUITests.swift:21,25`) only carry "Complete/Skip button should be present beside the mic" strings; no UI test taps the mic or drives `startDictation`. The `--seed` launch seam (`SingleThreadCore/UITestingSeed.swift`) seeds `ReminderStore`s for write flows only; it does not surface `ReminderDictation` or the speech authorization callback.

## Cross-Cutting Observations
- Two continuation/bridge styles coexist: (1) inline resume inside the framework completion handler with **no** hop (`ReminderDictation.swift:41`, `ReminderStore.swift:373`); (2) extract-Sendable-then-`Task { @MainActor in }`-then-resume (`ReminderDictation.swift:152-158`, `:178`). The dictation authorization path uses the former; the transcript path uses the latter.
- The same bridge-seam name recurs across domains: `SpeechTranscribing` (caller fakes in three test files), `EventKitStoring` (`EventKitStoring.swift:7-40`, fake `InMemoryEventStore`), `SkippedReminderSyncService` hooks — each abstracts a framework callback behind a fakeable protocol.
- Isolation config is two-tier: project-level `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (`project.pbxproj:596,651`); target-level `SWIFT_VERSION`/`SWIFT_APPROACHABLE_CONCURRENCY` everywhere; target-level `SWIFT_DEFAULT_ACTOR_ISOLATION` only on iOS/watch app targets.
- `@Sendable` appears in two directions: `@retroactive @unchecked Sendable` to allow non-isolated values across continuation boundaries (`ReminderDateFilter.swift:18`), and explicit `@Sendable` on callback closures that execute off-isolation (`ReminderDictation.swift:151`, `NextThingWidget.swift:36`).

## Open Areas
- Neither Apple docs nor the repo specify the exact dispatch queue/thread of the `SFSpeechRecognizer.requestAuthorization` completion; TCC-queue attribution is inferred from the crash stack + missing hop at `ReminderDictation.swift:41`. Ideally confirm from a device/sim crash log (no `.ips`/crash file is present in this repo).
- Swift runtime internals (`swift_task_isCurrentExecutorWithFlagsImpl`, `dispatch_assert_queue`) are not referenced in the codebase; the explanation is external (web/forum) only.