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
            let viewModel = makeViewModel(store: storeWithReminder())
            viewModel.enableActionButtons = true
            #expect(viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenToggleOff() {
            let viewModel = makeViewModel(store: storeWithReminder())
            viewModel.enableActionButtons = false
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenNoVisibleReminder() {
            // Toggle on, but an empty store -> no visible reminder -> plain mic.
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let viewModel = makeViewModel(store: store)
            viewModel.enableActionButtons = true
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenAllSkipped() {
            // Toggle on, but every reminder skipped -> visibleReminders empty.
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
            viewModel.enableActionButtons = true
            #expect(!viewModel.showsActionButtons)
        }

        // MARK: Private

        // MARK: Helpers

        private func makeViewModel(store: ReminderStore) -> ContentViewModel {
            ContentViewModel(
                store: store,
                backgroundImage: BackgroundImageStore(),
                speechTranscriber: TestFakeTranscriber())
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
#endif
