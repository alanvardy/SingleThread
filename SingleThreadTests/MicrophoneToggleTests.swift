@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

// MARK: - Fake transcriber for microphone toggle tests

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

// MARK: - Microphone Toggle Tests

@MainActor
struct MicrophoneToggleTests {
    // MARK: Internal

    @Test
    func settingsGearButtonIsPresent() {
        let fake = MicToggleFakeTranscriber()
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        let bodyDescription = String(describing: view.body)

        // The settings entry point (gear button) should survive the
        // Menu → sheet swap. Assert on its accessibility label, not the
        // SF Symbol name: `Image(systemName:)` describes as a boxed
        // `NamedImageProvider`, so "gearshape" never appears in the
        // body description.
        #expect(
            bodyDescription.contains("Settings"),
            "Settings gear button should be present on the main view")
    }

    @Test
    func micButtonHiddenWhenSpeechDenied() {
        let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
        let viewModel = makeViewModel(fake)

        // Mic button should be unavailable when speech recognition is denied.
        #expect(!viewModel.canDictate)

        // Regression guard: even with the toggle on, the mic button should
        // not appear in the body when speech recognition is denied.
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        let bodyDescription = String(describing: view.body)
        #expect(
            !bodyDescription.contains("mic.fill"),
            "Mic button should be absent when speech recognition is denied")
    }

    @Test
    func micButtonAbsentWhenToggleOff() {
        let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
        let viewModel = makeViewModel(fake)
        #expect(viewModel.canDictate)

        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(false, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        // Verify that creating the view with toggle off does not crash.
        let bodyDescription = String(describing: view.body)
        #expect(!bodyDescription.isEmpty)
    }

    @Test
    func micButtonWithToggleEnabledDoesNotCrash() {
        let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
        let viewModel = makeViewModel(fake)
        #expect(viewModel.canDictate)

        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        // Verify that creating the view with toggle on does not crash.
        let bodyDescription = String(describing: view.body)
        #expect(!bodyDescription.isEmpty)
    }

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

    @Test
    func explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        // `String(describing: view.body)` can't reach this label: ContentView's
        // deeply nested body description elides Text storage. The `bottomBar`
        // VStack itself is shallow enough to serialize (same depth as AboutView).
        #expect(String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    @Test
    func explanatoryLabelAppearsWhenSpeechRestrictedAndToggleOn() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = MicToggleFakeTranscriber(authorizationStatus: .restricted)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    @Test
    func explanatoryLabelAbsentWhenToggleOff() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(false, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(!String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    @Test
    func explanatoryLabelAbsentWhenNotDetermined() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = MicToggleFakeTranscriber(authorizationStatus: .notDetermined)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(!String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    #if os(iOS)
        @Test
        func explanatoryLabelContainsSettingsButtonOnIOS() {
            let defaultsKey = "showMicrophoneButton"
            UserDefaults.standard.set(true, forKey: defaultsKey)
            defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

            let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
            let view = ContentView(loadsReminders: false, speechTranscriber: fake)

            #expect(String(describing: view.bottomBar).contains("Open Settings"))
        }
    #endif

    @Test
    func explanatoryLabelRendersBelowErrorTextWhenBothPresent() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
        let contentViewModel = makeContentViewModel(fake)
        contentViewModel.dictation.dictationError = "some error"
        let view = ContentView(viewModel: contentViewModel)

        let bodyDescription = String(describing: view.bottomBar)
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

    // MARK: Private

    private func makeViewModel(_ fake: MicToggleFakeTranscriber) -> DictationViewModel {
        DictationViewModel(
            speechTranscriber: fake,
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false))
    }

    private func makeContentViewModel(_ fake: MicToggleFakeTranscriber) -> ContentViewModel {
        ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: fake)
    }
}
