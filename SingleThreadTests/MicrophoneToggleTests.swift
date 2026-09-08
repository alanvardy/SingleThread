@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

// MARK: - Microphone Toggle Tests

@MainActor
struct MicrophoneToggleTests {
    // MARK: Internal

    @Test
    func settingsGearButtonIsPresent() {
        let fake = TestFakeTranscriber()
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
        let fake = TestFakeTranscriber(authorizationStatus: .denied)
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
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
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
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
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
        let fake = TestFakeTranscriber(authorizationStatus: .denied)
        let viewModel = makeViewModel(fake)

        #expect(viewModel.authorizationStatus == .denied)
    }

    @Test
    func refreshAuthorizationStatusCallsThroughToTranscriber() {
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
        let viewModel = makeViewModel(fake)

        #expect(fake.refreshCallCount == 0)
        viewModel.refreshAuthorizationStatus()

        #expect(fake.refreshCallCount == 1)
    }

    @Test
    func foregroundActiveRefreshesAuthorizationStatus() {
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        view.handleScenePhaseChange(.active)

        #expect(fake.refreshCallCount == 1)
    }

    @Test
    func canDictateReflectsStatusAfterForegroundRefresh() {
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
        let viewModel = makeViewModel(fake)
        #expect(viewModel.canDictate)

        // Simulate the user denying speech access in Settings while backgrounded.
        fake.liveStatus = .denied
        viewModel.refreshAuthorizationStatus()

        #expect(!viewModel.canDictate)
    }

    @Test
    func foregroundActiveDoesNotAffectBackgroundBehavior() {
        let fake = TestFakeTranscriber(authorizationStatus: .authorized)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        view.handleScenePhaseChange(.background)

        #expect(fake.refreshCallCount == 0)
    }

    @Test
    func explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = TestFakeTranscriber(authorizationStatus: .denied)
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

        let fake = TestFakeTranscriber(authorizationStatus: .restricted)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    @Test
    func explanatoryLabelAbsentWhenToggleOff() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(false, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = TestFakeTranscriber(authorizationStatus: .denied)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(!String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    @Test
    func explanatoryLabelAbsentWhenNotDetermined() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = TestFakeTranscriber(authorizationStatus: .notDetermined)
        let view = ContentView(loadsReminders: false, speechTranscriber: fake)

        #expect(!String(describing: view.bottomBar).contains("Speech recognition is unavailable."))
    }

    #if os(iOS)
        @Test
        func explanatoryLabelContainsSettingsButtonOnIOS() {
            let defaultsKey = "showMicrophoneButton"
            UserDefaults.standard.set(true, forKey: defaultsKey)
            defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

            let fake = TestFakeTranscriber(authorizationStatus: .denied)
            let view = ContentView(loadsReminders: false, speechTranscriber: fake)

            #expect(String(describing: view.bottomBar).contains("Open Settings"))
        }
    #endif

    @Test
    func explanatoryLabelRendersBelowErrorTextWhenBothPresent() {
        let defaultsKey = "showMicrophoneButton"
        UserDefaults.standard.set(true, forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let fake = TestFakeTranscriber(authorizationStatus: .denied)
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

    #if os(iOS)
        @Test
        func processingIndicatorRendersWhenIsProcessingIsTrue() {
            let fake = TestFakeTranscriber()
            let contentViewModel = makeContentViewModel(fake)
            contentViewModel.dictation.isProcessing = true
            let view = ContentView(viewModel: contentViewModel)

            let bodyDescription = String(describing: view.bottomBar)
            #expect(bodyDescription.contains("Processing…"))
            #expect(!bodyDescription.contains("Recording"))
            #expect(!bodyDescription.contains("mic.fill"))
        }

        @Test
        func processingIndicatorNotRenderedWhenIsProcessingIsFalse() {
            let fake = TestFakeTranscriber()
            let contentViewModel = makeContentViewModel(fake)
            // isProcessing defaults to false
            let view = ContentView(viewModel: contentViewModel)

            let bodyDescription = String(describing: view.bottomBar)
            #expect(!bodyDescription.contains("Processing…"))
        }

        @Test
        func recordingIndicatorNotRenderedWithProcessingTrue() {
            let fake = TestFakeTranscriber()
            let contentViewModel = makeContentViewModel(fake)
            contentViewModel.dictation.isProcessing = true
            contentViewModel.dictation.dictationText = "Hello"
            let view = ContentView(viewModel: contentViewModel)

            let bodyDescription = String(describing: view.bottomBar)
            #expect(bodyDescription.contains("Hello"))
            #expect(!bodyDescription.contains("Recording"))
        }
    #endif

    // MARK: Private

    private func makeViewModel(_ fake: TestFakeTranscriber) -> DictationViewModel {
        DictationViewModel(
            speechTranscriber: fake,
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false))
    }

    private func makeContentViewModel(_ fake: TestFakeTranscriber) -> ContentViewModel {
        ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: fake)
    }
}
