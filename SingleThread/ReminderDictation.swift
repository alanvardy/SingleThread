@preconcurrency import AVFoundation
import SingleThreadCore
@preconcurrency import Speech

// MARK: - SpeechTranscribing protocol

/// Test seam: abstracts speech recognition so tests and previews can inject
/// a fake. Follows the same pattern as ``SkipSyncSession``.
@MainActor
protocol SpeechTranscribing: AnyObject {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func refreshAuthorizationStatus()
    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String
}

extension SpeechTranscribing {
    /// Default no-op for test fakes that never hold a stale snapshot.
    /// ``ReminderDictation`` overrides this to refresh its cached value.
    func refreshAuthorizationStatus() {}
}

// MARK: - ReminderDictation

/// On-device speech recognition for the "tap mic → speak → create reminder" flow.
/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` and bridges callbacks to `async throws`.
@MainActor
@Observable
final class ReminderDictation: SpeechTranscribing {
    // MARK: Lifecycle

    init(
        locale: Locale = .current,
        authorizationSource: any AuthorizationRequiring = SpeechAuthorizationRequiring()) {
        self.locale = locale
        self.authorizationSource = authorizationSource
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: Internal

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    /// Requests speech recognition authorization and updates `authorizationStatus`.
    /// Returns the resulting status.
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let gate = ResumptionGate()

        let status = await withCheckedContinuation { continuation in
            authorizationSource.requestAuthorization { @Sendable receivedStatus in
                resumeOnMainActor(gate) {
                    continuation.resume(returning: receivedStatus)
                }
            }
        }
        authorizationStatus = status
        return status
    }

    /// Re-reads the speech authorization status from the system so a permission
    /// change made in Settings while the app was backgrounded is reflected on
    /// foreground without a force-quit.
    func refreshAuthorizationStatus() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    /// Starts recording, listens for speech, and returns the final transcription.
    /// Streams live partial results to `onPartialResult` for UI feedback.
    /// Throws if the recognizer is unavailable or the audio session cannot be configured.
    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String {
        guard !isRecording else { throw DictationError.alreadyRecording }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw DictationError.recognizerUnavailable
        }
        try await ensureMicrophoneAccess()

        partialText = ""

        // Establish `isRecording` (and the `defer` teardown) only after setup
        // succeeds. If `prepareRecording()` throws midway, tearing down here
        // releases a partially-installed tap / audio session and leaves the
        // recorder usable for the next attempt — otherwise `isRecording == true`
        // would remain and every later call would fail with `.alreadyRecording`.
        do {
            try prepareRecording()
        } catch {
            tearDownRecording()
            throw error
        }
        isRecording = true
        defer { tearDownRecording() }

        return try await awaitFinalResult(recognizer: recognizer, onPartialResult: onPartialResult)
    }

    // MARK: Private

    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let authorizationSource: any AuthorizationRequiring
    @ObservationIgnored private lazy var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: locale)
    @ObservationIgnored private lazy var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRecording = false
    private var partialText = ""
    @ObservationIgnored private var transcriptionAccumulator = TranscriptionAccumulator()

    private func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw DictationError.microphoneDenied
            }
        case .denied, .restricted:
            throw DictationError.microphoneDenied
        default:
            break
        }
    }

    private func prepareRecording() throws {
        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func tearDownRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func awaitFinalResult(
        recognizer: SFSpeechRecognizer,
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let request = recognitionRequest else {
            throw DictationError.recognizerUnavailable
        }

        let gate = ResumptionGate()
        transcriptionAccumulator = TranscriptionAccumulator()

        return try await withCheckedThrowingContinuation { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { @Sendable outcome, error in
                // Extract Sendable values before hopping to the main actor.
                let text = outcome?.bestTranscription.formattedString
                let isFinal = outcome?.isFinal ?? false
                // On-device recognition commits an utterance after a pause and
                // starts a new one; committed segments have confidence > 0.
                let isCommitted = (outcome?.bestTranscription.segments.first?.confidence ?? 0) > 0
                Task { @MainActor in
                    guard !gate.hasResumed else { return }
                    if let error {
                        guard gate.tryResume() else { return }
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let text else { return }
                    let combined = self.transcriptionAccumulator.append(
                        TranscriptionAccumulator.Chunk(text: text, isCommitted: isCommitted))
                    self.partialText = combined
                    onPartialResult(combined)
                    if isFinal {
                        // Already on the main actor; resume inline. Claim the
                        // gate only here so the 5s timeout / error branch and
                        // this final resume stay mutually exclusive.
                        guard gate.tryResume() else { return }
                        continuation.resume(returning: combined)
                    }
                }
            }

            // Timeout: auto-stop after 5 seconds of no final result.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, isRecording else { return }
                guard gate.tryResume() else { return }
                if transcriptionAccumulator.isEmpty {
                    continuation.resume(throwing: DictationError.noSpeechDetected)
                } else {
                    continuation.resume(returning: transcriptionAccumulator.combined)
                }
            }
        }
    }
}

// MARK: - DictationError

enum DictationError: Error, LocalizedError, Sendable {
    case alreadyRecording
    case recognizerUnavailable
    case microphoneDenied
    case noSpeechDetected

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            String(localized: "Already recording.", table: "Localizable", bundle: .main)
        case .recognizerUnavailable:
            String(
                localized: "Speech recognition is not available.",
                table: "Localizable",
                bundle: .main)
        case .microphoneDenied:
            String(
                localized: "Microphone access was denied.",
                table: "Localizable",
                bundle: .main)
        case .noSpeechDetected:
            String(localized: "No speech was detected.", table: "Localizable", bundle: .main)
        }
    }
}
