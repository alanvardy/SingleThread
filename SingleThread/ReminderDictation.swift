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
    func transcribe(
        onPartialResult: @escaping @MainActor (String) -> Void) async throws -> String
}

// MARK: - ReminderDictation

/// On-device speech recognition for the "tap mic → speak → create reminder" flow.
/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` and bridges callbacks to `async throws`.
@MainActor
@Observable
final class ReminderDictation: SpeechTranscribing {
    // MARK: Lifecycle

    init(locale: Locale = .current) {
        self.locale = locale
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: Internal

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    /// Requests speech recognition authorization and updates `authorizationStatus`.
    /// Returns the resulting status.
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        return status
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

        isRecording = true
        partialText = ""

        try prepareRecording()
        defer { tearDownRecording() }

        return try await awaitFinalResult(recognizer: recognizer, onPartialResult: onPartialResult)
    }

    // MARK: Private

    @ObservationIgnored private let locale: Locale
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

        final class ResumptionGate: @unchecked Sendable {
            var hasResumed = false
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
                        gate.hasResumed = true
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let text else { return }
                    let combined = self.transcriptionAccumulator.append(
                        TranscriptionAccumulator.Chunk(text: text, isCommitted: isCommitted))
                    self.partialText = combined
                    onPartialResult(combined)
                    if isFinal {
                        gate.hasResumed = true
                        continuation.resume(returning: combined)
                    }
                }
            }

            // Timeout: auto-stop after 5 seconds of no final result.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, isRecording else { return }
                guard !gate.hasResumed else { return }
                gate.hasResumed = true
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

enum DictationError: Error, LocalizedError {
    case alreadyRecording
    case recognizerUnavailable
    case microphoneDenied
    case noSpeechDetected

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: "Already recording."
        case .recognizerUnavailable: "Speech recognition is not available."
        case .microphoneDenied: "Microphone access was denied."
        case .noSpeechDetected: "No speech was detected."
        }
    }
}
