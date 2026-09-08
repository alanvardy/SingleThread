# Structure Outline

## Approach

Three bottom-up fixes for the mic-button visibility bug (VAR-747):
register the `showMicrophoneButton` default, refresh stale speech-authorization
state on foreground, and surface an explanatory label when the mic is hidden
by speech denial. Each layer is fully tested before the next begins.

---

## Stage 1: Data & Protocol Layer

Extend the `SpeechTranscribing` protocol with a foreground refresh method,
implement it in `ReminderDictation`, expose the raw `authorizationStatus`
through `DictationViewModel`, and register the `showMicrophoneButton` default.
The fake transcriber is updated to match the new protocol surface. No
behavior change at this stage — the new methods exist but aren't called from
any production path yet.

**Files**:
- `SingleThread/ReminderDictation.swift`
- `SingleThread/DictationViewModel.swift`
- `SingleThread/AppViewModel.swift`
- `SingleThreadTests/MicrophoneToggleTests.swift`

**Key changes**:
- `protocol SpeechTranscribing` — add:
  ```swift
  func refreshAuthorizationStatus()
  ```
  (Already exposes `var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }`)

- `final class ReminderDictation` — implement:
  ```swift
  func refreshAuthorizationStatus() {
      authorizationStatus = SFSpeechRecognizer.authorizationStatus()
  }
  ```

- `final class DictationViewModel` — add passthroughs:
  ```swift
  var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
      speechTranscriber.authorizationStatus
  }

  func refreshAuthorizationStatus() {
      speechTranscriber.refreshAuthorizationStatus()
  }
  ```

- `final class AppViewModel` — in `init(arguments:)`, after `store.sortOption = …`:
  ```swift
  UserDefaults.standard.register(defaults: ["showMicrophoneButton": true])
  ```
  (A dedicated `static func registerDefaults()` helper called from `init` is
  preferred if the init body grows beyond a one-liner.)

- `private final class MicToggleFakeTranscriber` — add stub:
  ```swift
  func refreshAuthorizationStatus() { /* no-op */ }
  ```

**Tests**:
- `showMicrophoneButtonDefaultIsRegistered` — remove the key from
  `UserDefaults.standard`, call `AppViewModel(arguments: [])`, assert
  `UserDefaults.standard.bool(forKey: "showMicrophoneButton") == true`.
- `authorizationStatusPassthroughMatchesTranscriber` — create `DictationViewModel`
  with a `.denied` fake, assert `viewModel.authorizationStatus == .denied`.
- `refreshAuthorizationStatusCallsThroughToTranscriber` — fake transcriber
  that records a flag when `refreshAuthorizationStatus()` is called; verify
  it's set after `DictationViewModel.refreshAuthorizationStatus()`.
- Existing suite (`MicrophoneToggleTests`) stays green — fake still conforms
  to the extended protocol.

**Verify**:
```bash
xcodebuild -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -configuration Debug build
xcodebuild -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -configuration Debug test \
  -only-testing:SingleThreadTests/MicrophoneToggleTests
```

---

## Stage 2: Scene-Phase Wiring

Call `refreshAuthorizationStatus()` when the app returns to the foreground so
the mic reappears after the user grants speech permission in Settings. Extend
the scene-phase handler to run on macOS as well (the notification scheduling
inside it stays `#if os(iOS)`).

**Files**:
- `SingleThread/ContentView.swift`
- `SingleThreadTests/MicrophoneToggleTests.swift`

**Key changes**:
- Lift `handleScenePhaseChange(_:)` and its `.onChange(of: scenePhase)` call
  site out of `#if os(iOS)` so the method exists on all platforms.

- Inside `handleScenePhaseChange(_:)`, add to the `.active` case:
  ```swift
  case .active:
      #if os(iOS)
          Task { await appViewModel.cancelNotifications() }
      #endif
      dictation.refreshAuthorizationStatus()
  ```
  (Access `dictation` from the already-in-scope `viewModel.dictation` — or
  wire it through `contentViewModel` if the handler lives in a different
  extension scope.)

- If `handleScenePhaseChange` currently lives in the `#if os(iOS)` private
  extension (line 686), move it to a non-`#if`-guarded extension, keep the
  notification calls inside `#if os(iOS)`, and remove the `#if os(iOS)` guard
  from the `.onChange(of: scenePhase)` modifier so macOS also reacts to
  scene-phase changes.

**Tests**:
- `foregroundActiveRefreshesAuthorizationStatus` — create `ContentView` with a
  recording fake transcriber (flags each `refreshAuthorizationStatus()` call);
  call `handleScenePhaseChange(.active)`; assert the fake's flag is `true`.
- `canDictateReflectsStatusAfterForegroundRefresh` — `DictationViewModel` with
  a fake initially `.authorized`; change fake to `.denied`; call
  `.refreshAuthorizationStatus()`; assert `canDictate` is now `false`.
- `foregroundActiveDoesNotAffectBackgroundBehavior` — call
  `handleScenePhaseChange(.background)`; assert the fake's refresh flag is
  **not** set (regression guard: `.background` doesn't trigger a spurious
  re-read).

**Verify**:
```bash
xcodebuild -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -configuration Debug test \
  -only-testing:SingleThreadTests/MicrophoneToggleTests
```

---

## Stage 3: Explanatory Label UI

Add a caption in `bottomBar` when the mic is hidden because speech recognition
is denied or restricted, with a Settings deep-link button on iOS. The label
only appears when the user hasn't explicitly turned the mic off
(`showMicrophoneButton == true`).

**Files**:
- `SingleThread/ContentView.swift`
- `SingleThreadTests/MicrophoneToggleTests.swift`

**Key changes**:
- In `bottomBar`'s `if/else if` chain, after the
  `else if viewModel.dictation.canDictate, showMicrophoneButton { … }` block,
  add:
  ```swift
  } else if !viewModel.dictation.canDictate,
              viewModel.dictation.authorizationStatus != .notDetermined,
              showMicrophoneButton {
      VStack(spacing: 4) {
          Text("Speech recognition is unavailable.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          #if os(iOS)
              Button("Open Settings") {
                  if let url = URL(string: UIApplication.openSettingsURLString) {
                      UIApplication.shared.open(url)
                  }
              }
              .font(.caption)
          #endif
      }
      .padding(.horizontal)
  }
  ```
  (The `authorizationStatus` passthrough was added in Stage 1.)

**Tests**:
- `explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn` — `ContentView` with
  `.denied` fake; set `showMicrophoneButton` to `true`; assert body string
  contains `"Speech recognition is unavailable"`.
- `explanatoryLabelAbsentWhenToggleOff` — `.denied` fake, toggle `false`;
  assert body string does **not** contain the explanation text.
- `explanatoryLabelAbsentWhenNotDetermined` — `.notDetermined` fake, toggle
  `true`; assert body string does **not** contain the explanation text (the
  mic should be visible, so no explanation needed).
- `explanatoryLabelContainsSettingsButtonOnIOS` — `.denied` fake, toggle
  `true`; assert body string contains `"Open Settings"`.
- `explanatoryLabelRendersBelowErrorTextWhenBothPresent` — fake with
  `.denied` and `dictationError = "some error"` set on the ViewModel; assert
  both the error text and the explanation appear in the body string and the
  error renders first.

**Verify**:
```bash
xcodebuild -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -configuration Debug test \
  -only-testing:SingleThreadTests/MicrophoneToggleTests
```

---

## Testing Checkpoints

| After Stage | Gate |
|---|---|
| 1 | `MicrophoneToggleTests` green; protocol-extended fake compiles |
| 2 | `MicrophoneToggleTests` green; foreground-refresh unit tests pass |
| 3 | `MicrophoneToggleTests` green; explanatory-label rendering tests pass |
| Final | `./scripts/test.sh` — full CI pipeline (lint, format, build, unit + UI tests, Periphery) |