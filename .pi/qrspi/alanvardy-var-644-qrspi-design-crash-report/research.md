# Research Findings

Branch: `alanvardy-var-644-qrspi-design-crash-report` — iOS/watchOS Swift 6 app "SingleThread". Scope: concurrency in the dictation feature (`SingleThread/ReminderDictation.swift`) and the `_dispatch_assert_queue_fail` crash in `requestAuthorization()`.

## Q1: How `requestAuthorization()` transfers control from the callback API to its `async` caller

### Findings
- `ReminderDictation.requestAuthorization()` — `SingleThread/ReminderDictation.swift:38-46`:
  ```swift
  func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
      let status = await withCheckedContinuation { continuation in
          SFSpeechRecognizer.requestAuthorization { status in
              continuation.resume(returning: status)
          }
      }
      authorizationStatus = status   // :44
      return status                  // :45
  }
  ```
- `withCheckedContinuation` at `ReminderDictation.swift:39` (inferred `CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>`); SDK call at `:40`; `continuation.resume(returning:)` at `:41` is called **directly inside the framework completion handler** — there is no `Task { @MainActor in }` hop and no dispatch-queue hop between the callback firing and the resume.
- The single call site is `ContentView.swift:503` inside `startDictation()` (`ContentView.swift:501`), itself launched from the mic button via `Task { await startDictation() }` (`ContentView.swift:467`).
- Control transfer mechanics: the `@MainActor` async function suspends at the `await`; the SDK completion closure resumes the continuation on whatever thread/queue the framework uses. Apple does not document the queue for `SFSpeechRecognizer.requestAuthorization` (no statement exists in the repo either). The post-await statements (`authorizationStatus = status`, `return status`, `:44-45`) re-enter on the MainActor executor because the enclosing function is `@MainActor`-isolated (`:22`) and `authorizationStatus` is a MainActor-stored `private(set)` property (`:34`).
- **Comparison — `transcribe`/`awaitFinalResult` path:** `transcribe` at `ReminderDictation.swift:51-75` (guards `:53-56`, `ensureMicrophoneAccess()` `:57`, `prepareRecording()` in do/catch `:64-70`, `isRecording = true` `:71`, `defer tearDown` `:72`, then `return try await awaitFinalResult(...)` `:74`). `awaitFinalResult` at `:137-187` uses `withCheckedThrowingContinuation` (`:150`), marks the recognition callback `@Sendable` (`:151`), extracts Sendable values first (`:152-157`), and **hops** with `Task { @MainActor in }` (`:158`) before touching `self`/`onPartialResult`/`continuation`; resume points `:162` (throw), `:172` (return). A second hop for the 5-second timeout at `:178` (`Task { @MainActor [weak self] in`), resumes at `:184`/`:186`.
- Key asymmetry: `requestAuthorization` resumes inline from a non-`@Sendable`, non-hopped SDK callback (`:41`); `awaitFinalResult` always resumes from inside `Task { @MainActor in }` (`:158`, `:178`).
- `ResumptionGate` (`:144-147`): local `final class ResumptionGate: @unchecked Sendable { var hasResumed = false }` guards double-resume across the recognition path (`:159`) and timeout path (`:181`), set to `true` before each resume (`:161`, `:171`, `:182`). All gate access happens inside the MainActor-hoisted tasks.
- Class/protocol isolation: `@MainActor` on protocol `SpeechTranscribing` (`:9`), `@MainActor @Observable` on `final class ReminderDictation` (`:22-24`); `onPartialResult` is `@escaping @MainActor (String) -> Void` (`:15`, repeated at `:52`, `:139`).
- `@preconcurrency import AVFoundation` (`:1`) and `@preconcurrency import Speech` (`:3`) — the only `@preconcurrency` imports in the repo (verified repo-wide). They suppress strict `@Sendable`/isolation diagnostics for these framework APIs, which is what lets `:41` compile without a sendability error.

## Q2: What the crash's top frames mean under this concurrency configuration

### Findings
- Crash shape (per the question): `_dispatch_assert_queue_fail` ← `dispatch_assert_queue` ← `swift_task_isCurrentExecutorWithFlagsImpl` ← the `requestAuthorization()` completion closure. This is the runtime MainActor executor check failing: a closure that must run on the MainActor executor is executing on a different queue/thread, and libdispatch aborts the assertion.
- The only direct `SFSpeechRecognizer.requestAuthorization` call in app code is `ReminderDictation.swift:40` (resume inline at `:41`, no hop — see Q1). `requestAuthorization()` is MainActor-isolated twice over: explicit `@MainActor` on class (`:22`) and protocol (`:9`), plus the target-wide default.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the **iOS app target only** (and the watch app): `SingleThread.xcodeproj/project.pbxproj:697` (Debug) and `:747` (Release) for SingleThread; `:873`/`:901` for SingleThreadWatch. Every otherwise-unannotated async/sync function in those modules defaults to MainActor.
- `SWIFT_VERSION = 6.0` on all six targets (app `:700`/`:750`; tests `:774`/`:799`; UI tests `:823`/`:847`; watch `:875`/`:903`; widget `:935`/`:966`; watch UI tests `:986`/`:1009`). No `SWIFT_STRICT_CONCURRENCY` setting exists anywhere — strict concurrency comes from the Swift 6 language mode.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` on all six targets (`:696`/`:746`/`:771`/`:796`/`:820`/`:844`/`:872`/`:900`/`:932`/`:963`/`:984`/`:1007`) — relaxes Swift 6 concurrency diagnostics, so patterns can pass compilation while retaining runtime executor assertions.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` only at **project level** (`:596` Debug, `:651` Release) — it promotes warnings to errors; it does not affect runtime executor checks.
- Effect of `@preconcurrency` on runtime checks: `@preconcurrency import Speech` / `@preconcurrency import AVFoundation` (`ReminderDictation.swift:1`, `:3`) treat those framework APIs as pre-concurrency — the compiler suppresses `@Sendable`/isolation diagnostics for the callback-based API and the closure it forms, but the **runtime** MainActor-executor assertion is unchanged. The code compiles under `SWIFT_VERSION = 6.0`; whether a code path trips the assertion depends on which thread/queue the framework actually calls back on.
- Contrasts inside the repo that *don't* trip the assert: `awaitFinalResult` hops via `Task { @MainActor in }` before resuming (`ReminderDictation.swift:158`, `:178`); the AVAudioEngine tap closure is `@Sendable` and only appends to a local request (`:117`). `ReminderStore.fetchReminders` (`ReminderStore.swift:371-375`) resumes a `CheckedContinuation<[EKReminder], Never>` directly from EventKit's completion callback — but EventKit is imported **without** `@preconcurrency` (`ReminderStore.swift:1`), so its concurrency contract is enforced at compile time rather than deferring to a runtime executor check.
- In-repo documentation of off-main callbacks: EventKit's `fetchReminders(matching:)` "performs its work off the main thread" (`ReminderStore.swift:368`); `ReminderDateFilter.swift:9-16` documents resuming from "EventKit's completion queue"; WCSession hooks run on "WCSession's delegate queue" (`SkippedReminderSyncService.swift:48-55`). No file contains the word "executor" (grep returns nothing).
- Types of paths that trip `swift_task_isCurrentExecutorWithFlagsImpl`: any MainActor-isolated closure/function invoked from a non-main queue/thread without an explicit executor hop — exactly the `requestAuthorization` completion closure shape.

## Q3: How speech-recognition authorization is initiated and consumed across the app

### Findings
- **Protocol (test seam):** `@MainActor protocol SpeechTranscribing: AnyObject` — `ReminderDictation.swift:9-16`: `var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }` (`:11`), `func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus` (`:13`), `func transcribe(onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String` (`:14-15`). Doc: "Test seam … Follows the same pattern as `SkipSyncSession`" (`:6-8`).
- **Real implementation:** `@MainActor @Observable final class ReminderDictation: SpeechTranscribing` (`:22-24`). `init(locale:)` seeds `authorizationStatus = SFSpeechRecognizer.authorizationStatus()` (`:26-30`, seed at `:29`; stored at `:34` as `private(set)`).
- **`requestAuthorization()`** (`:38-46`) updates the stored status (`:44`) and returns it (`:45`) — see Q1 for mechanics.
- **Initiation:** `ContentView.startDictation()` (`ContentView.swift:501-538`):
  - `:502-506` — if `authorizationStatus == .notDetermined`, `await speechTranscriber.requestAuthorization()` and require `.authorized` (else `dictationError = "Speech recognition access is required."`).
  - `:509-512` — guard re-checks `authorizationStatus == .authorized` (else "Speech recognition access was denied.").
  - `:513-515` — `isDictating = true`, clears `dictationText`/`dictationError`; `:517-519` `try await speechTranscriber.transcribe { text in dictationText = text }`; `:520` `ReminderDictationParser.parse(result)`; `:522-527` `store.addReminder(...)`; `:528-534` success/failure feedback + 1 s sleep; `:535-536` catch → `dictationError`; `:538` `isDictating = false`.
- **Mic visibility gating:**
  - `canDictate = authorizationStatus == .authorized || == .notDetermined` — `ContentView.swift:233-236`.
  - `bottomBar` (`:385-421`): error text `:392-399`; `isDictating` branch shows partial `dictationText` + red pulsing `recordingIndicator` (`:401-409`); mic only when `canDictate` **and** `@AppStorage("showMicrophoneButton")` (`:410-418`); on iOS, `showsActionButtons ? actionCluster : micButton` (`:412-415`), where `showsActionButtons = enableActionButtons && store.visibleReminders.first != nil` (`:56-58`, toggle `:199-200`).
  - `micButton` (`:465-477`) runs `Task { await startDictation() }` (`:467`); `actionCluster` = Complete + mic + Skip (`:454-459`); `recordingIndicator` (`:480-489`).
  - `.denied`/`.restricted` hide the mic entirely via `canDictate`.
- **How `authorizationStatus` is stored/observed:** it is an observable property on the concrete `@Observable` class (`:23`, `:34`, mutated at `:44`), but `ContentView` stores the transcriber as an **existential** `private let speechTranscriber: any SpeechTranscribing` (`:221`) injected via three inits (`:11-13`, `:16-18`, `:29-37`, all defaulting to `ReminderDictation()`). The protocol carries no `@Observable` requirement; there is no `@Bindable`, no `.onChange(of: speechTranscriber.authorizationStatus)`, and no `withObservationTracking` anywhere. Views read the status synchronously during `body` (`canDictate`, `:233-236`); post-auth UI updates are driven by `@State` mutations (`isDictating` `:211`/`:513`/`:538`, `dictationError` `:213`/`:505`/`:510`/`:536`), not by observation of `authorizationStatus`.
- **All `SpeechTranscribing` conformances (repo-wide):** production `ReminderDictation` (`ReminderDictation.swift:24`); test fakes `FakeSpeechTranscriber` (`ReminderDictationTests.swift:9`), `MicToggleFakeTranscriber` (`MicrophoneToggleTests.swift:8`), `ActionButtonFakeTranscriber` (`ActionButtonTests.swift:15`). None in watch/widget/core targets (watch has zero `SpeechTranscribing`/`SFSpeechRecognizer` matches).

## Q4: Existing patterns for hopping callback results onto the main actor

### Findings

**Pattern A — continuation resumed inline from a documented off-main callback:**
- `ReminderStore.fetchReminders(matching:)` — `SingleThreadCore/.../ReminderStore.swift:366-375`:
  ```swift
  await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
      eventStore.fetchReminders(matching: predicate) { reminders in
          continuation.resume(returning: reminders ?? [])
      }
  }
  ```
  Doc: "`fetchReminders(matching:)` performs its work off the main thread" (`:368`). Callers: `reload()` awaits it at `:269` and `:283` (same `@MainActor` class, `:5-7`). No `Task { @MainActor in }` hop — the `@MainActor` method's continuation is resumed from EventKit's completion queue.
- Why this compiles: `@MainActor protocol EventKitStoring` (`EventKitStoring.swift:7-8`; `fetchReminders(matching:completion:)` at `:22-24`) + `extension EKReminder: @retroactive @unchecked Sendable {}` (`ReminderDateFilter.swift:29`), documented at `:9-23`: "`ReminderStore.fetchReminders` resumes a `CheckedContinuation<[EKReminder], Never>` from EventKit's completion queue — `CheckedContinuation` requires its value to be `Sendable`"; safety invariant: every `EKReminder` is created/mutated/read only on the `@MainActor` (`:20-23`).

**Pattern B — callback → `nonisolated(unsafe)` hook → app-layer `Task { await … }` (WatchConnectivity):**
- `SkippedReminderSyncService` — `SkippedReminderSyncService.swift:23` is `public final class SkippedReminderSyncService: NSObject, WCSessionDelegate` (not `@MainActor`). Hooks are `public nonisolated(unsafe) var` at `:56` (`onCompleteReminderReceived`), `:61` (`onDeleteReminderReceived`), `:67` (`onShowUndatedRemindersReceived`), `:72` (`onSortOptionReceived`). Rationale at `:48-55`: "written once from the main actor *before* `activate()` is called and only read afterwards on WCSession's delegate queue, giving a happens-before edge between the two threads. It is `nonisolated(unsafe)` because the closure captures the `@MainActor` `ReminderStore` and is therefore not `Sendable`."
- Delegate callbacks fire the hooks: `session(_:didReceiveApplicationContext:)` (`:164-200`) fires `onShowUndatedRemindersReceived` (`:180`) and `onSortOptionReceived` (`:185`); `session(_:didReceiveMessage:)` (`:195-206`) fires `onCompleteReminderReceived` (`:197`) and `onDeleteReminderReceived` (`:199`).
- Main-actor hopping happens at the app layer: phone `SingleThreadApp.swift:37-39` `service.onCompleteReminderReceived = { [weak store] identifier in Task { await store?.completeReminder(identifier: identifier) } }`; `:41-43` same for delete. The `Task { await … }` carries **no** explicit `@MainActor` (redundant in the MainActor-default app target). Blocked-nil/retain-cycle rationale at `:32-36` ("`[weak store]` breaks the retain cycle").
- Watch side: `SingleThreadWatch/SingleThreadWatchApp.swift:26-31` `onShowUndatedRemindersReceived = { [weak store] value in Task { store?.showsUndatedReminders = value; await store?.reload() } }`; but `onSortOptionReceived` calls the `@MainActor` `setSortOption` **directly with no Task hop** (`:34-36`).
- Outbound (main-actor → service): store hooks wired to `service.push(...)`/`requestCompleteReminder`/`requestDeleteReminder`/`pushSortOption` at `SingleThreadApp.swift:45-58`; watch `SingleThreadWatchApp.swift:37-46`.

**Pattern C — `@Sendable` callback + explicit `Task { @MainActor in }` hoist (the transcription path):**
- `ReminderDictation.awaitFinalResult` — `ReminderDictation.swift:150-186`: `@Sendable` recognition callback (`:151`), extract Sendable values (`:152-157`), then `Task { @MainActor in }` (`:158`) before touching state/resuming (`:162`, `:172`); timeout variant `Task { @MainActor [weak self] in` (`:178`). Includes the `ResumptionGate` (`:144-147`) single-resume guard. This is the only in-repo convention where the continuation is resumed from the main actor explicitly.
- View-layer hops: `ContentView.swift:91` (`Task { await store.reload() }`), `:350`/`:359`/`:428`/`:242` (`Task { await store.completeCurrentReminder() }` / delete); `WatchReminderView.swift:88`, `:152`, `:166-178`.

**Pattern D — synchronous continuation bridges (tests and in-memory store):**
- `ReminderStoreTests.swift:268-273` and `:283-287`: `await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in store.onSkipSetChanged = { _ in continuation.resume() }; store.skipCurrentReminder() }` — resumed synchronously from a store hook on the main actor (`@MainActor` file at `:5`).
- `InMemoryEventStore.fetchReminders` (`InMemoryEventStore.swift:49-55`, class `@MainActor` at `:12-13`) and `FakeEventStore` (`EventKitStoringTests.swift:87-94`, class `@MainActor` at `:9`) call `completion(...)` synchronously with no queue/actor hop.
- `SkippedReminderSyncServiceTests.swift` `FakeSession: SkipSyncSession` (`:7-28`) with `@MainActor struct SkippedReminderSyncServiceTests` (`:32`) invokes delegate methods directly on the main actor.

**Pattern E — `@MainActor` annotation instead of default (non-app targets):**
- `ReminderIntents.swift:17`/`:40` `@MainActor public func perform() async throws` (widget flows `reload()`/`completeCurrentReminder()` without callbacks).
- `UITestingSeed.swift` `fromLaunchArguments` (`:27-39`) / `materialize()` (`:88-109`) — no concurrency annotations, no continuations.
- `extension EKEventStore: EventKitStoring` passthrough — `EventKitStoring.swift:30-45`.

## Q5: How `ReminderDictation` is covered by tests

### Findings
- **The seam:** `SpeechTranscribing` protocol (`ReminderDictation.swift:9-16`) is implemented by three test fakes, all `@MainActor`:
  - `FakeSpeechTranscriber` — `ReminderDictationTests.swift:8-64`: preset `authorizationStatus` (+ `requestAuthorizationCallCount` `:33`); `requestAuthorization()` `:36-39` increments the counter and **returns the stored status unchanged**; `transcribe()` `:41-63` sets `isRecording`, delivers `partialUpdates` (50 ms sleeps) or `"Listening…"`, then throws `transcriptionError` or returns `transcriptionResult ?? ""`.
  - `MicToggleFakeTranscriber` — `MicrophoneToggleTests.swift:7-27`: `requestAuthorization()` returns stored status (`:19-21`), `transcribe()` returns `""` (`:23-26`).
  - `ActionButtonFakeTranscriber` — `ActionButtonTests.swift:14-33` (inside `#if os(iOS)` `:8`): same shape as the above; comment at `:12-13` notes it is copied because `MicToggleFakeTranscriber` is `private` to its file.
- **What the unit tests exercise:**
  - `ReminderDictationTests` (`@MainActor` struct `:69`) — `fakeRecordsAuthorizationCall` `:74-79` (`.notDetermined`, call count == 1); `fakeAuthorizationIsPreset` `:82-84`; `fakeTranscribeReturnsPresetResult` `:90-95`; `fakeTranscribeThrowsPresetError` `:98-109` (`DictationError.noSpeechDetected`); `fakeTranscribeSetsRecordingFlag` `:113-118`; `fakeTranscribeDeliversPartialResults` `:121-129` (partial arrays + `partialText`); `contentViewCanInitWithFakeTranscriber` `:134-138` and `contentViewCanInitWithReminderStoreAndFakeTranscriber` `:141-146` (body string non-empty).
  - `DictationErrorTests` (`ReminderDictationTests.swift:151`, **not** `@MainActor`) — `:153-154`, `:158-159`, `:163-164`, `:168-169` assert `errorDescription != nil` for each case.
  - `MicrophoneToggleTests` (`@MainActor` struct `:31`) — `settingsGearButtonIsPresent` `:34-47`; `micButtonHiddenWhenSpeechDenied` `:49-67` (`.denied` fake + `showMicrophoneButton = true`; asserts body has **no** `"mic.fill"`); `micButtonAbsentWhenToggleOff` `:69-79` and `micButtonWithToggleEnabledDoesNotCrash` `:82-92` (assert body non-empty only).
  - `ActionButtonTests` (`@MainActor` struct `:44`) — `buttonsShowWhenToggleOnAndReminderVisible` `:51-59` (`view.showsActionButtons`), `buttonsHiddenWhenToggleOff` `:62-70`, `buttonsHiddenWhenNoVisibleReminder` `:73-86`, `buttonsHiddenWhenAllSkipped` `:89-105`; helper `storeWithReminder()` `:112-120` (prepopulated store, no EventKit).
- **Real-path coverage:** **No test instantiates the real `ReminderDictation` or calls its real `requestAuthorization`** — a repo-wide grep for `ReminderDictation(` matches only the production nil-coalescing defaults (`ContentView.swift:13`, `:18`, `:37`). The only `requestAuthorization` invoked in tests is `fake.requestAuthorization()` (`ReminderDictationTests.swift:76`). The real `withCheckedContinuation` callback path (`ReminderDictation.swift:39-43`), real `transcribe`, `ensureMicrophoneAccess()`, `prepareRecording()`, and `awaitFinalResult()` have zero unit coverage.
- **Isolation difference app vs. test target:** The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`project.pbxproj:697`/`:747`); the **test target does not** — its Debug config (`:755-777`, `BUNDLE_LOADER` `:757`, `TEST_HOST` `:776`) and Release config (`:782-803`) run `SWIFT_VERSION = 6.0` + `SWIFT_APPROACHABLE_CONCURRENCY = YES` only. Hence tests/fakes opt in with explicit `@MainActor` (`ReminderDictationTests.swift:8`/`:69`, `MicrophoneToggleTests.swift:7`/`:31`, `ActionButtonTests.swift:14`/`:44`). Widget (`:910-940+`) and UI-test targets also omit the setting.
- Mic-gating assertions are string-based: `String(describing: view.body)` `.contains("mic.fill")` / `"Settings"` matches (`MicrophoneToggleTests.swift:43-63`), and comment at `ActionButtonTests.swift:36-43` notes `_ConditionalContent` is indistinguishable in `body` descriptions.

## Cross-Cutting Observations
- **Two distinct resume conventions coexist**: inline resume from the framework callback with no hop (`requestAuthorization` `ReminderDictation.swift:41`; EventKit `ReminderStore.swift:373-374`) versus explicit `Task { @MainActor in }` hoist (`awaitFinalResult` `ReminderDictation.swift:158`/`:178`). The inline variant is exactly the crash shape; the hoisted variant is the guarded pattern the same file uses elsewhere.
- **`@preconcurrency` is the compile-time escape hatch only** — `ReminderDictation.swift:1`/`:3` are the sole `@preconcurrency` imports; they suppress diagnostics but leave runtime executor assertions intact (Q2).
- **MainActor default is target-scoped, not project-wide**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` exists only on the iOS app (`pbxproj:697`/`:747`) and watch app (`:873`/`:901`) Debug/Release configs. Core package, widget, and both test targets annotate explicitly (`AGENTS.md` "Concurrency Model", lines 42-52).
- **Sendability is handled at the boundary**: values are converted to Sendable/extracted before crossing (comment `ReminderDictation.swift:152`; `EKReminder: @retroactive @unchecked Sendable` `ReminderDateFilter.swift:29`); continuations are resumed with Sendable payloads; `ResumptionGate` is `@unchecked Sendable` (Q1).
- **Hook-based cross-actor bridging**: WatchConnectivity uses write-once-before-activate `nonisolated(unsafe)` hooks (`SkippedReminderSyncService.swift:48-72`) and the app layer re-roots them with `Task { await store?.… }` (`SingleThreadApp.swift:37-43`; watch `SingleThreadWatchApp.swift:26-31`) — no explicit `@MainActor` annotation on those Tasks because the app target defaults to MainActor.
- **`@Observable` does not flow through the existential**: `ReminderDictation.authorizationStatus` is observable on the concrete type (`:23`, `:34`) but `ContentView` holds `any SpeechTranscribing` (`ContentView.swift:221`), so mic UI reacts via `@State` (`isDictating`/`dictationError`), not observation (Q3).

## Open Areas
- The exact queue `SFSpeechRecognizer.requestAuthorization` invokes its completion handler on is not documented by Apple nor stated anywhere in the repo — hence no in-repo explanation of why the executor assert fires; the finding rests on the absence of a hop at `ReminderDictation.swift:41`.
- Whether WatchConnectivity delivers `onSortOptionReceived` (and the other hooks) on a non-main delegate queue is asserted only by the hook docs (`SkippedReminderSyncService.swift:48-55`); the watch app's direct `setSortOption` call without a `Task` hop (`SingleThreadWatchApp.swift:34-36`) has no documented queue guarantee nearby.
- No unit test drives the real continuation path, so nothing in the test suite would detect a regression of the resume-on-wrong-queue shape described by the crash.