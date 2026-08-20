import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

#if os(iOS)

    // MARK: - Fake transcriber for action-button tests

    /// Pattern copied from `MicrophoneToggleTests`; that file's fake transcriber is
    /// private to its own source file, so it is not reusable here.
    @MainActor
    private final class ActionButtonFakeTranscriber: SpeechTranscribing {
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

    // MARK: - Action Button Tests

    /// The cluster is a runtime `_ConditionalContent` branch, so `String(describing:
    /// view.body)` cannot distinguish it (both branches appear in the reflected type
    /// names and SwiftUI never reflects accessibility labels). These tests therefore
    /// verify the gate decision (`ContentView.showsActionButtons`) directly — the
    /// seam exists exactly for this — while the rendered cluster is exercised by the
    /// UI tests (`ActionButtonsUITests` in Phase 3).
    @MainActor
    struct ActionButtonTests {
        // MARK: Internal

        // MARK: Tests

        @Test
        func buttonsShowWhenToggleOnAndReminderVisible() {
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let store = storeWithReminder()
            let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
            #expect(view.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenToggleOff() {
            let key = "enableActionButtons"
            UserDefaults.standard.set(false, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let store = storeWithReminder()
            let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
            #expect(!view.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenNoVisibleReminder() {
            // Toggle on, but an empty store -> no visible reminder -> plain mic.
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let store = ReminderStore(
                loadsReminders: false,
                reminders: [],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
            #expect(!view.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenAllSkipped() {
            // Toggle on, but every reminder skipped -> visibleReminders empty.
            let key = "enableActionButtons"
            UserDefaults.standard.set(true, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            let store = ReminderStore(
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [reminder.calendarItemIdentifier],
                authorizationStatus: .fullAccess)
            let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
            #expect(!view.showsActionButtons)
        }

        // MARK: Private

        // MARK: Helpers

        /// A prepopulated store with one visible reminder; never touches EventKit.
        private func storeWithReminder() -> ReminderStore {
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            reminder.priority = 5
            return ReminderStore(
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
        }
    }
#endif
