import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import Testing

// MARK: - Fake transcriber for testing

@MainActor
private final class FakeSpeechTranscriber: SpeechTranscribing {
    // MARK: Lifecycle

    init(
        authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized,
        transcriptionResult: String? = nil,
        transcriptionError: (any Error)? = nil,
        partialUpdates: [String]? = nil) {
        self.authorizationStatus = authorizationStatus
        self.transcriptionResult = transcriptionResult
        self.transcriptionError = transcriptionError
        self.partialUpdates = partialUpdates
    }

    // MARK: Internal

    private(set) var isRecording = false
    private(set) var partialText = ""
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    var transcriptionResult: String?
    var transcriptionError: (any Error)?
    var recordingEndedGate: CheckedContinuation<Void, Never>?
    var partialUpdates: [String]?
    var partialResults: [String] = []
    var requestAuthorizationCallCount = 0
    var transcribeCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        requestAuthorizationCallCount += 1
        return authorizationStatus
    }

    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String {
        transcribeCallCount += 1
        isRecording = true
        partialResults = []
        if let updates = partialUpdates {
            for text in updates {
                partialText = text
                partialResults.append(text)
                onPartialResult(text)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        } else {
            partialText = "Listening…"
            partialResults.append("Listening…")
            onPartialResult("Listening…")
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        isRecording = false
        recordingEndedGate?.resume()
        recordingEndedGate = nil
        if let error = transcriptionError {
            throw error
        }
        return transcriptionResult ?? ""
    }
}

// MARK: - Off-main authorization seam

@MainActor
private final class DetachedAuthorizationRequiring: AuthorizationRequiring {
    // MARK: Lifecycle

    init(status: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.status = status
    }

    // MARK: Internal

    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        // Dispatch the completion from an off-main queue, reproducing the real
        // framework delivery that tripped the MainActor assert.
        Task.detached { completion(self.status) }
    }

    // MARK: Private

    private let status: SFSpeechRecognizerAuthorizationStatus
}

// MARK: - ReminderDictation (Fake) Tests

@MainActor
struct ReminderDictationTests {
    // MARK: - Authorization

    @Test
    func fakeRecordsAuthorizationCall() async {
        let fake = FakeSpeechTranscriber(authorizationStatus: .notDetermined)
        let status = await fake.requestAuthorization()
        #expect(status == .notDetermined)
        #expect(fake.requestAuthorizationCallCount == 1)
    }

    @Test
    func fakeAuthorizationIsPreset() {
        let fake = FakeSpeechTranscriber(authorizationStatus: .denied)
        #expect(fake.authorizationStatus == .denied)
    }

    @Test
    func requestAuthorizationResumesOnMainActorFromOffMainQueue() async {
        let requester = DetachedAuthorizationRequiring(status: .authorized)
        let dictation = ReminderDictation(authorizationSource: requester)
        let status = await dictation.requestAuthorization()
        #expect(status == .authorized)
        #expect(dictation.authorizationStatus == .authorized)
    }

    // MARK: - Transcription

    @Test
    func fakeTranscribeReturnsPresetResult() async throws {
        let fake = FakeSpeechTranscriber(transcriptionResult: "Buy milk")
        let result = try await fake.transcribe { _ in }
        #expect(result == "Buy milk")
        #expect(fake.transcribeCallCount == 1)
    }

    @Test
    func fakeTranscribeThrowsPresetError() async {
        let fake = FakeSpeechTranscriber(
            transcriptionResult: "test",
            transcriptionError: DictationError.noSpeechDetected)
        do {
            _ = try await fake.transcribe { _ in }
            #expect(Bool(false), "Expected error not thrown")
        } catch let error as DictationError {
            #expect(error == .noSpeechDetected)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test
    func fakeTranscribeSetsRecordingFlag() async throws {
        let fake = FakeSpeechTranscriber(transcriptionResult: "Hello")
        #expect(!fake.isRecording)
        _ = try await fake.transcribe { _ in }
        #expect(!fake.isRecording)
    }

    @Test
    func fakeTranscribeDeliversPartialResults() async throws {
        let updates = ["Buy", "Buy milk", "Buy milk today"]
        let fake = FakeSpeechTranscriber(
            transcriptionResult: "Buy milk today",
            partialUpdates: updates)
        _ = try await fake.transcribe { _ in }
        #expect(fake.partialResults == updates)
        #expect(fake.partialText == "Buy milk today")
    }

    @Test
    func gateResumesAfterRecordingEnds() async {
        let fake = FakeSpeechTranscriber(transcriptionResult: "Hello")
        #expect(!fake.isRecording)
        await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
            fake.recordingEndedGate = gate
            Task {
                _ = try? await fake.transcribe { _ in }
            }
        }
        #expect(!fake.isRecording)
    }

    // MARK: - DictationViewModel integration

    @Test
    func dictationViewModelCanInitWithFakeTranscriber() {
        let fake = FakeSpeechTranscriber()
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = DictationViewModel(speechTranscriber: fake, store: store)
        #expect(viewModel.canDictate)
    }

    @Test
    func dictationViewModelCanInitWithStore() {
        let fake = FakeSpeechTranscriber()
        let scratchStore = EKEventStore()
        let reminder = EKReminder(eventStore: scratchStore)
        reminder.title = "Buy milk"
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let viewModel = DictationViewModel(speechTranscriber: fake, store: store)
        #expect(viewModel.canDictate)
    }

    @Test
    func startDictationAddsReminderAndFlowsText() async {
        let fake = FakeSpeechTranscriber(
            transcriptionResult: "Buy milk",
            partialUpdates: ["Buy", "Buy milk"])
        let eventStore = InMemoryEventStore()
        let store = ReminderStore(eventStore: eventStore, loadsReminders: false)
        let viewModel = DictationViewModel(speechTranscriber: fake, store: store)
        #expect(viewModel.canDictate)

        await viewModel.startDictation()

        #expect(!viewModel.isDictating)
        #expect(viewModel.dictationText == "Buy milk")
        #expect(viewModel.dictationError == nil)
        #expect(eventStore.allReminders.contains { $0.title == "Buy milk" })
    }
}

// MARK: - DictationError Tests

struct DictationErrorTests {
    @Test
    func alreadyRecordingHasDescription() {
        #expect(DictationError.alreadyRecording.errorDescription != nil)
    }

    @Test
    func recognizerUnavailableHasDescription() {
        #expect(DictationError.recognizerUnavailable.errorDescription != nil)
    }

    @Test
    func microphoneDeniedHasDescription() {
        #expect(DictationError.microphoneDenied.errorDescription != nil)
    }

    @Test
    func noSpeechDetectedHasDescription() {
        #expect(DictationError.noSpeechDetected.errorDescription != nil)
    }
}
