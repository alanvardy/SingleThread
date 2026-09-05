import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

#if os(iOS)

    // MARK: - Action Button Tests

    /// The cluster is a runtime `_ConditionalContent` branch, so `String(describing:
    /// view.body)` cannot distinguish it (both branches appear in the reflected type
    /// names and SwiftUI never reflects accessibility labels). These tests therefore
    /// verify the gate decision (`ContentViewModel.showsActionButtons`) directly — the
    /// seam exists exactly for this — while the rendered cluster is exercised by the
    /// UI tests (`ActionButtonsUITests` in Phase 3).
    @MainActor
    struct ActionButtonTests {
        // MARK: Internal

        // MARK: Tests

        @Test
        func buttonsShowWhenToggleOnAndReminderVisible() {
            let key = "enableActionButtons"
            AppGroup.defaults.set(true, forKey: key)
            defer { AppGroup.defaults.removeObject(forKey: key) }

            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenToggleOff() {
            let key = "enableActionButtons"
            AppGroup.defaults.set(false, forKey: key)
            defer { AppGroup.defaults.removeObject(forKey: key) }

            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenNoVisibleReminder() {
            // Toggle on, but an empty store -> no visible reminder -> plain mic.
            let key = "enableActionButtons"
            AppGroup.defaults.set(true, forKey: key)
            defer { AppGroup.defaults.removeObject(forKey: key) }

            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let viewModel = makeViewModel(store: store)
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenAllSkipped() {
            // Toggle on, but every reminder skipped -> visibleReminders empty.
            let key = "enableActionButtons"
            AppGroup.defaults.set(true, forKey: key)
            defer { AppGroup.defaults.removeObject(forKey: key) }

            // Construction only — never saved through EventKit.
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [reminder.calendarItemIdentifier],
                authorizationStatus: .fullAccess)
            let viewModel = makeViewModel(store: store)
            #expect(!viewModel.showsActionButtons)
        }

        // MARK: Private

        // MARK: Helpers

        private func makeViewModel(store: ReminderStore) -> ContentViewModel {
            ContentViewModel(
                store: store,
                backgroundImage: BackgroundImageStore(),
                speechTranscriber: ActionButtonFakeTranscriber())
        }

        /// A prepopulated store with one visible reminder; never touches EventKit.
        /// Construction only — never saved through EventKit.
        private func storeWithReminder() -> ReminderStore {
            let eventStore = EKEventStore()
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Buy groceries"
            reminder.priority = 5
            return ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
        }
    }

    // MARK: - Fake transcriber

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
#endif
