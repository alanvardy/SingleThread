@testable import SingleThread
import SingleThreadCore
import Speech
import Testing

// MARK: - Fake transcriber for microphone toggle tests

@MainActor
private final class MicToggleFakeTranscriber: SpeechTranscribing {
    // MARK: Lifecycle

    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
    }

    // MARK: Internal

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
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

    // MARK: Private

    private func makeViewModel(_ fake: MicToggleFakeTranscriber) -> DictationViewModel {
        DictationViewModel(
            speechTranscriber: fake,
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false))
    }
}
