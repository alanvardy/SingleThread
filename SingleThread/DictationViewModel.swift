import SingleThreadCore
import Speech
import SwiftUI

/// Owns speech recognition authorization, transcription, and the
/// parse→create reminder flow. Injected with ``any SpeechTranscribing`` so
/// tests can supply a fake transcriber.
@MainActor
@Observable
final class DictationViewModel {
    // MARK: Lifecycle

    init(
        speechTranscriber: any SpeechTranscribing,
        store: ReminderStore,
        errorDisplayDuration: TimeInterval = DictationViewModel.dictationErrorDisplayDuration) {
        self.speechTranscriber = speechTranscriber
        self.store = store
        self.errorDisplayDuration = errorDisplayDuration
    }

    // MARK: Internal

    /// Seconds a dictation error stays visible before it clears itself.
    static let dictationErrorDisplayDuration: TimeInterval = 2.0

    private(set) var isDictating = false
    var isProcessing = false
    var dictationText = ""
    var dictationError: String?
    var creationFeedback: CreationFeedback?

    var canDictate: Bool {
        speechTranscriber.authorizationStatus == .authorized
            || speechTranscriber.authorizationStatus == .notDetermined
    }

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

    func startDictation() async {
        guard !isDictating else { return }
        if speechTranscriber.authorizationStatus == .notDetermined {
            let status = await speechTranscriber.requestAuthorization()
            guard status == .authorized else {
                showDictationError(String(
                    localized: "Speech recognition access is required.",
                    table: "Localizable",
                    bundle: .main))
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            showDictationError(String(
                localized: "Speech recognition access was denied.",
                table: "Localizable",
                bundle: .main))
            return
        }
        isDictating = true
        dictationText = ""
        clearDictationError()
        do {
            let result = try await speechTranscriber.transcribe { [weak self] text in
                self?.dictationText = text
            }
            isDictating = false
            isProcessing = true
            let parsed = ReminderDictationParser.parse(result)
            if !parsed.title.isEmpty {
                let saved = await store.addReminder(
                    title: parsed.title,
                    notes: nil,
                    dueDate: parsed.dueDateComponents,
                    recurrenceRule: parsed.recurrenceRule)
                if saved {
                    creationFeedback = .success
                } else {
                    creationFeedback = .failure
                }
                try? await Task.sleep(
                    nanoseconds: UInt64(CreationFeedback.displayDuration * 1_000_000_000))
                creationFeedback = nil
            }
        } catch {
            showDictationError(error.localizedDescription)
            isDictating = false
            isProcessing = true
        }
        isProcessing = false
    }

    // MARK: Private

    private let speechTranscriber: any SpeechTranscribing
    private let store: ReminderStore
    private let errorDisplayDuration: TimeInterval
    @ObservationIgnored private var dictationErrorClearTask: Task<Void, Never>?
    @ObservationIgnored private var dictationErrorGeneration = 0

    /// Shows `message` and schedules it to clear after ``errorDisplayDuration``.
    /// A newer error cancels any pending timer; a timer whose generation is stale
    /// is ignored so it cannot clear a newer error.
    private func showDictationError(_ message: String) {
        dictationErrorGeneration &+= 1
        let generation = dictationErrorGeneration
        let duration = errorDisplayDuration
        dictationErrorClearTask?.cancel()
        dictationError = message
        dictationErrorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, dictationErrorGeneration == generation else { return }
            dictationError = nil
        }
    }

    private func clearDictationError() {
        dictationErrorGeneration &+= 1
        dictationErrorClearTask?.cancel()
        dictationErrorClearTask = nil
        dictationError = nil
    }
}
