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
        store: ReminderStore) {
        self.speechTranscriber = speechTranscriber
        self.store = store
    }

    // MARK: Internal

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
                dictationError = String(
                    localized: "Speech recognition access is required.",
                    table: "Localizable",
                    bundle: .main)
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            dictationError = String(
                localized: "Speech recognition access was denied.",
                table: "Localizable",
                bundle: .main)
            return
        }
        isDictating = true
        dictationText = ""
        dictationError = nil
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
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                creationFeedback = nil
            }
        } catch {
            dictationError = error.localizedDescription
            isDictating = false
            isProcessing = true
        }
        isProcessing = false
    }

    // MARK: Private

    private let speechTranscriber: any SpeechTranscribing
    private let store: ReminderStore
}
