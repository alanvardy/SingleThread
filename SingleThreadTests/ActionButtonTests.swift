import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech
import SwiftUI
import Testing

#if os(iOS) || os(macOS)

    // MARK: - Action Button Tests

    /// The cluster is a runtime `_ConditionalContent` branch, so `String(describing:
    /// view.body)` cannot distinguish it (both branches appear in the reflected type
    /// names and SwiftUI never reflects accessibility labels). These tests therefore
    /// verify the gate decision (`ContentViewModel.showsActionButtons`) directly — the
    /// seam exists exactly for this. The rendered cluster is exercised by
    /// `SingleThreadUITests.testLaunchAndRenderSmoke` (the successor of the former
    /// `ActionButtonsUITests` suite, whose a11y audit uses only the cheap categories
    /// and never runs the local-only `.hitRegion` check).
    @MainActor
    struct ActionButtonTests {
        // MARK: Internal

        // MARK: Tests

        @Test
        func buttonsShowWhenToggleOnAndReminderVisible() {
            let viewModel = makeViewModel(store: storeWithReminder())
            viewModel.enableActionButtons = true
            viewModel.hasLoadedReminders = true
            #expect(viewModel.showsActionButtons)
        }

        /// Reproduces the cold-open ordering: on app open, the view injects
        /// ``enableActionButtons`` before ``task()`` has settled the reminders, so the
        /// gate is dead (hidden) even though a visible reminder exists. Once
        /// ``task()`` flips ``hasLoadedReminders`` after ``store.start()`` returns, the
        /// gate comes alive and the action-button cluster appears without needing a
        /// swipe re-render. (The first assertion dead-checks the flag ordering; a
        /// pre-fix gate that only required `enableActionButtons` + a visible reminder
        /// would fail it, reproducing the reported bug.)
        @Test
        func buttonsAppearAfterRemindersSettleOnStartupPath() {
            let viewModel = makeViewModel(store: storeWithReminder())
            viewModel.enableActionButtons = true
            // Gate dead right after flag injection — pre-settle, even with a visible
            // reminder.
            #expect(!viewModel.showsActionButtons)
            // Reminders settle (`task()` flipping `hasLoadedReminders` after
            // `await store.start()` returns) → gate comes alive.
            viewModel.hasLoadedReminders = true
            #expect(viewModel.showsActionButtons)
        }

        @Test
        func buttonsHiddenWhenToggleOff() {
            let viewModel = makeViewModel(store: storeWithReminder())
            viewModel.enableActionButtons = false
            viewModel.hasLoadedReminders = true
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
            viewModel.hasLoadedReminders = true
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
            viewModel.hasLoadedReminders = true
            #expect(!viewModel.showsActionButtons)
        }

        @Test
        func freshViewModelDefaultsToActionButtonsOn() {
            let viewModel = makeViewModel(store: storeWithReminder())
            #expect(
                viewModel.enableActionButtons,
                "the ContentViewModel mirror tracks ContentView's new @AppStorage default")
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
