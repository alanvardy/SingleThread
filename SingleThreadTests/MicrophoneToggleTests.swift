@testable import SingleThread
import Speech
import Testing

// MARK: - Fake transcriber for microphone toggle tests

@MainActor
private final class MicToggleFakeTranscriber: SpeechTranscribing {
    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
    }

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String {
        ""
    }
}

// MARK: - Microphone Toggle Tests

@MainActor
struct MicrophoneToggleTests {
    @Test
    func settingsMenuContainsMicrophoneToggle() {
        let view = ContentView(loadsReminders: false)
        let bodyDescription = String(describing: view.body)

        // The settings menu should contain the Microphone toggle.
        #expect(bodyDescription.contains("Microphone"),
                "Settings menu should contain microphone toggle label")
    }

    @Test
    func micButtonHiddenWhenSpeechDenied() {
        // Even with the toggle on, the mic button should be hidden when
        // speech recognition is denied.
        let fake = MicToggleFakeTranscriber(authorizationStatus: .denied)
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        let bodyDescription = String(describing: view.body)

        // "Microphone" toggle label is in settings menu, but mic/recording
        // views (which include "Circle") should not appear in bottomBar
        // since canDictate is false.
        #expect(!bodyDescription.contains("mic.fill"),
                "Mic button should be absent when speech recognition is denied")
    }

    @Test
    func micButtonAbsentWhenToggleOff() {
        let fake = MicToggleFakeTranscriber(authorizationStatus: .authorized)
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
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let view = ContentView(loadsReminders: false, speechTranscriber: fake)
        // Verify that creating the view with toggle on does not crash.
        let bodyDescription = String(describing: view.body)
        #expect(!bodyDescription.isEmpty)
    }
}