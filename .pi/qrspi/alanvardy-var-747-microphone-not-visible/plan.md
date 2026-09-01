# Implementation Plan

## Overview

Make the mic (dictation) button reliably visible: register the
`showMicrophoneButton = true` default, re-read speech authorization when the
app returns to the foreground, and render an explanatory label when the mic is
hidden because speech recognition is denied or restricted.

> Destination pinning: the name-only `iPhone 17` destination is ambiguous on
> this machine (3 iOS runtimes installed). All stage-level `xcodebuild`
> commands below pin `OS=26.2`. The final gate uses
> `SIM='platform=iOS Simulator,name=iPhone 17,OS=26.2' ./scripts/test.sh`.

---

## Phase 1: Data & Protocol Layer

### Changes

#### 1. `SpeechTranscribing` protocol + default implementation
**File**: `SingleThread/ReminderDictation.swift`
**Action**: modify

Add the refresh method to the protocol:

```swift
@MainActor
protocol SpeechTranscribing: AnyObject {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func refreshAuthorizationStatus()
    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String
}
```

Add a default no-op implementation so the other four test fakes
(`FakeSpeechTranscriber` in `ReminderDictationTests.swift`,
`ActionButtonFakeTranscriber` in `ActionButtonTests.swift`,
`BackgroundCardFakeTranscriber` in `BackgroundCardTests.swift`,
`GlowFakeTranscriber` in `CompletionGlowTests.swift`) keep conforming without
editing those files:

```swift
extension SpeechTranscribing {
    /// Default no-op for test fakes that never hold a stale snapshot.
    /// ``ReminderDictation`` overrides this to refresh its cached value.
    func refreshAuthorizationStatus() {}
}
```

#### 2. `ReminderDictation` implementation
**File**: `SingleThread/ReminderDictation.swift`
**Action**: modify

Add the production override next to `requestAuthorization()`:

```swift
/// Re-reads the speech authorization status from the system so a permission
/// change made in Settings while the app was backgrounded is reflected on
/// foreground without a force-quit.
func refreshAuthorizationStatus() {
    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
}
```

(`authorizationStatus` is `private(set) var`, so this in-class write compiles.)

#### 3. `DictationViewModel` passthroughs
**File**: `SingleThread/DictationViewModel.swift`
**Action**: modify

Add next to `canDictate`:

```swift
/// The transcriber's current authorization status. Exposed so the view can
/// distinguish denied/restricted (show an explanation) from notDetermined
/// (mic still visible — permission is requested lazily on first tap).
var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
    speechTranscriber.authorizationStatus
}

/// Re-reads the speech authorization status from the underlying transcriber.
func refreshAuthorizationStatus() {
    speechTranscriber.refreshAuthorizationStatus()
}
```

#### 4. Register the `showMicrophoneButton` default
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In `init(arguments:)`, after `store.sortOption = SortOptionStore().load()`:

```swift
Self.registerDefaults()
```

Add the helper (internal so tests can also call it directly):

```swift
/// Registers fallback `UserDefaults` values for keys whose offline default is
/// not `false`. `@AppStorage` initializers are invisible to raw
/// `bool(forKey:)` reads, so registration removes the silent divergence.
static func registerDefaults() {
    UserDefaults.standard.register(defaults: ["showMicrophoneButton": true])
}
```

#### 5. Test fake + new tests
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify

Replace `MicToggleFakeTranscriber` with a recording, live-status version:

```swift
@MainActor
private final class MicToggleFakeTranscriber: SpeechTranscribing {
    // MARK: Lifecycle

    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        liveStatus = authorizationStatus
    }

    // MARK: Internal

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    /// The status `refreshAuthorizationStatus()` re-reads — the test mutates
    /// this to simulate a Settings change while the app is backgrounded.
    var liveStatus: SFSpeechRecognizerAuthorizationStatus

    private(set) var refreshCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func refreshAuthorizationStatus() {
        refreshCallCount += 1
        authorizationStatus = liveStatus
    }

    func transcribe(
        onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String {
        ""
    }
}
```

Add three tests to `MicrophoneToggleTests`:

```swift
@Test
func showMicrophoneButtonDefaultIsRegistered() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.removeObject(forKey: defaultsKey)

    _ = AppViewModel(arguments: [])

    #expect(UserDefaults.standard.bool(forKey: defaultsKey))
    UserDefaults.standard.removeObject(forKey: defaultsKey)
}

@Test
func authorizationStatusPassthroughMatchesTranscriber() {
    let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
    let viewModel = makeViewModel(fake)

    #expect(viewModel.authorizationStatus == .denied)
}

@Test
func refreshAuthorizationStatusCallsThroughToTranscriber() {
    let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
    let viewModel = makeViewModel(fake)

    #expect(fake.refreshCallCount == 0)
    viewModel.refreshAuthorizationStatus()

    #expect(fake.refreshCallCount == 1)
}
```

(`makeViewModel` already exists in the file.)

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug build` passes
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug test -only-testing:SingleThreadTests/MicrophoneToggleTests` passes (existing + 3 new tests)
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug test -only-testing:SingleThreadTests/ReminderDictationTests` passes (other fakes compile against the protocol extension default)

#### Manual
- [ ] `make lint` and `make format` report clean (no new SwiftLint/SwiftFormat violations)

---

## Phase 2: Scene-Phase Wiring

### Changes

#### 1. Move `handleScenePhaseChange` out of `#if os(iOS)`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete `handleScenePhaseChange(_:)` from the `#if os(iOS) private extension`
(leave `isNotificationsUITesting`, `notificationStatusOverlay`, and
`handleNotificationsEnabledChange` there).

Add a new internal extension (not `private`, so tests can call it) after the
Notifications extension:

```swift
// MARK: - Scene Phase (all platforms)

extension ContentView {
    /// Routes scene-phase transitions: schedule notifications on background
    /// (iOS only), cancel on foreground (iOS only), and re-read speech
    /// authorization on foreground so a permission change in Settings takes
    /// effect without a force-quit.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            #if os(iOS)
                if let appViewModel {
                    Task { await appViewModel.scheduleNotificationIfNeeded() }
                }
            #endif
        case .active:
            #if os(iOS)
                if let appViewModel {
                    Task { await appViewModel.cancelNotifications() }
                }
            #endif
            viewModel.dictation.refreshAuthorizationStatus()
        default:
            break
        }
    }
}
```

Key points:
- The old top-level `guard let appViewModel else { return }` is replaced by
  per-case `if let appViewModel` inside `#if os(iOS)`, so the dictation refresh
  still runs when `appViewModel` is nil (macOS, previews, unit tests).
- On macOS `appViewModel` does not exist (it is `#if os(iOS)`), so both
  notification cases are `#if os(iOS)`-guarded.
- The method is now `internal`, so `@testable import SingleThread` can call it.

#### 2. Un-guard the `.onChange(of: scenePhase)` modifier
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Change:

```swift
#if os(iOS)
    .onChange(of: scenePhase) { _, phase in
        handleScenePhaseChange(phase)
    }
#endif
```

to:

```swift
.onChange(of: scenePhase) { _, phase in
    handleScenePhaseChange(phase)
}
```

#### 3. New tests
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify

Add `import SwiftUI` to the imports (for `ScenePhase`).

Add three tests:

```swift
@Test
func foregroundActiveRefreshesAuthorizationStatus() {
    let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    view.handleScenePhaseChange(.active)

    #expect(fake.refreshCallCount == 1)
}

@Test
func canDictateReflectsStatusAfterForegroundRefresh() {
    let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
    let viewModel = makeViewModel(fake)
    #expect(viewModel.canDictate)

    // Simulate the user denying speech access in Settings while backgrounded.
    fake.liveStatus = .denied
    viewModel.refreshAuthorizationStatus()

    #expect(!viewModel.canDictate)
}

@Test
func foregroundActiveDoesNotAffectBackgroundBehavior() {
    let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    view.handleScenePhaseChange(.background)

    #expect(fake.refreshCallCount == 0)
}
```

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug test -only-testing:SingleThreadTests/MicrophoneToggleTests` passes (6 tests now)
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug build` passes (macOS compile path: method is no longer `#if os(iOS)`)

#### Manual
- [ ] macOS target still compiles: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build` passes

---

## Phase 3: Explanatory Label UI

### Changes

#### 1. iOS UIKit import
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add after `import SwiftUI`:

```swift
#if os(iOS)
    import UIKit
#endif
```

(Needed for `UIApplication` in the Settings deep-link; guard it for the macOS build.)

#### 2. Add the explanatory label branch
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In `bottomBar`, the current chain ends with:

```swift
} else if viewModel.dictation.canDictate, showMicrophoneButton {
    #if os(iOS)
        ...
    #else
        micButton
    #endif
}
```

Append a new `else if` branch after it:

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

Notes:
- `authorizationStatus` passthrough comes from Phase 1.
- `.notDetermined` is intentionally excluded (mic stays visible; permission is
  requested lazily on first tap).
- The branch renders on macOS too (without the Settings button), matching the
  existing macOS mic path.

#### 3. New tests
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify

Add a helper next to `makeViewModel`:

```swift
private func makeContentViewModel(_ fake: MicToggleFakeTranscriber) -> ContentViewModel {
    ContentViewModel(
        store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
        backgroundImage: BackgroundImageStore(),
        speechTranscriber: fake)
}
```

Add five tests (plus one `.restricted` case to honor design point 4):

```swift
@Test
func explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(true, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    #expect(String(describing: view.body).contains("Speech recognition is unavailable."))
}

@Test
func explanatoryLabelAppearsWhenSpeechRestrictedAndToggleOn() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(true, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .restricted)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    #expect(String(describing: view.body).contains("Speech recognition is unavailable."))
}

@Test
func explanatoryLabelAbsentWhenToggleOff() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(false, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    #expect(!String(describing: view.body).contains("Speech recognition is unavailable."))
}

@Test
func explanatoryLabelAbsentWhenNotDetermined() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(true, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .notDetermined)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    #expect(!String(describing: view.body).contains("Speech recognition is unavailable."))
}

@Test
func explanatoryLabelContainsSettingsButtonOnIOS() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(true, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
    let view = ContentView(loadsReminders: false, speechTranscriber: fake)

    #expect(String(describing: view.body).contains("Open Settings"))
}

@Test
func explanatoryLabelRendersBelowErrorTextWhenBothPresent() {
    let defaultsKey = "showMicrophoneButton"
    UserDefaults.standard.set(true, forKey: defaultsKey)
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
    let contentViewModel = makeContentViewModel(fake)
    contentViewModel.dictation.dictationError = "some error"
    let view = ContentView(viewModel: contentViewModel)

    let bodyDescription = String(describing: view.body)
    #expect(bodyDescription.contains("some error"))
    #expect(bodyDescription.contains("Speech recognition is unavailable."))

    let errorRange = bodyDescription.range(of: "some error")
    let explanationRange = bodyDescription.range(of: "Speech recognition is unavailable.")
    #expect(errorRange != nil)
    #expect(explanationRange != nil)
    if let errorRange, let explanationRange {
        #expect(errorRange.lowerBound < explanationRange.lowerBound)
    }
}
```

(`ContentView(viewModel:)` is the primary internal init; `dictationError` is a
settable `var` on `DictationViewModel`. Both are reachable via
`@testable import SingleThread`.)

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug test -only-testing:SingleThreadTests/MicrophoneToggleTests` passes (12 tests total)
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug build` passes

#### Manual
- [ ] `make format` applies clean (no phantom diffs on a second run)
- [ ] `make lint` passes with `--strict`

---

## Testing Checkpoints

| After Phase | Gate |
|---|---|
| 1 | `MicrophoneToggleTests` green (existing + 3 new); other test fakes still compile |
| 2 | `MicrophoneToggleTests` green (6 tests); macOS build compiles |
| 3 | `MicrophoneToggleTests` green (12 tests); label rendering assertions pass |
| Final | Full CI pipeline below |

## Final Gate

- [ ] `SIM='platform=iOS Simulator,name=iPhone 17,OS=26.2' ./scripts/test.sh` passes (format, lint, build, Periphery, unit + UI tests, watch UI tests, macOS build + unit tests)
- [ ] Confirm the branch has both unit coverage (Phase 1–3 tests) and that no UI-test seam is required — speech authorization has no production launch-arg seam, so dictation is unit-tested only, as designed (explicitly noted in the PR)
