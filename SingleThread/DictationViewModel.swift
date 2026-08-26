import SingleThreadCore
import Speech
import SwiftUI

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
    var dictationText = ""
    var dictationError: String?
    var creationFeedback: CreationFeedback?

    var canDictate: Bool {
        speechTranscriber.authorizationStatus == .authorized
            || speechTranscriber.authorizationStatus == .notDetermined
    }

    func startDictation() async {
        if speechTranscriber.authorizationStatus == .notDetermined {
            let status = await speechTranscriber.requestAuthorization()
            guard status == .authorized else {
                dictationError = "Speech recognition access is required."
                return
            }
        }
        guard speechTranscriber.authorizationStatus == .authorized else {
            dictationError = "Speech recognition access was denied."
            return
        }
        isDictating = true
        dictationText = ""
        dictationError = nil
        do {
            let result = try await speechTranscriber.transcribe { [weak self] text in
                self?.dictationText = text
            }
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
        }
        isDictating = false
    }

    // MARK: Private

    private let speechTranscriber: any SpeechTranscribing
    private let store: ReminderStore
}
