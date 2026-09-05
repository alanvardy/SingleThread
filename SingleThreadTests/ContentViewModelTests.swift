import EventKit
@testable import SingleThread
import SingleThreadCore
import Testing

@MainActor
struct ContentViewModelTests {
    // MARK: Internal

    @Test
    func openInRemindersOpensCorrectURL() {
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Test"
        // EKReminder(eventStore:) assigns a UUID to calendarItemIdentifier
        // immediately, even before a save. Capture it for the assertion.
        let identifier = reminder.calendarItemIdentifier
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(reminder)

        let expected = "x-apple-reminderkit://REMCDReminder/\(identifier)"
        #expect(spy.lastOpenedURL?.absoluteString == expected)
    }

    @Test
    func openInRemindersWithValidReminderRecordsURL() throws {
        // Sanity: a real freshly-created EKReminder has a UUID identifier,
        // and openInReminders passes it to the spy.
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Buy milk"
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(reminder)

        #expect(spy.openedURLs.count == 1)
        let urlString = try #require(spy.lastOpenedURL?.absoluteString)
        #expect(urlString.hasPrefix("x-apple-reminderkit://REMCDReminder/"))
        // UUID portion should be 36 chars (dashed UUID format)
        let uuidPortion = String(urlString.dropFirst("x-apple-reminderkit://REMCDReminder/".count))
        #expect(uuidPortion.count == 36)
    }

    @Test
    func openInRemindersIdentifierOpensCorrectURL() {
        let identifier = "E0B6FFFB-1234-5678-9ABC-DEF012345678"
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(identifier: identifier)

        #expect(spy.lastOpenedURL?.absoluteString == "x-apple-reminderkit://REMCDReminder/\(identifier)")
    }

    @Test
    func openInRemindersWithEmptyIdentifierIsNoOp() {
        // The nudge sheet passes the nudged identifier; an empty one (a
        // reminder with no identifier) must not open anything.
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(identifier: "")

        #expect(spy.openedURLs.isEmpty)
    }

    @Test
    func lastOpenedURLAccessorIsNilWithoutSpy() {
        // A model built with the default (system) opener exposes no UI-test URL:
        // the seam is inert for production. This guards against a future path
        // that accidentally leaks the injected spy into the accessor.
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Test"
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        viewModel.openInReminders(reminder)

        #expect(viewModel.lastOpenedURLForUITesting == nil)
    }

    // MARK: - refreshManual

    @Test
    func refreshManualTogglesIsRefreshing() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        #expect(viewModel.isRefreshing == false)

        await viewModel.refreshManual()

        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualGateBlocksReentrantCall() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        // Fire two concurrent refreshManual calls; the second must be
        // dropped by the re-entrancy guard.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await viewModel.refreshManual() }
            group.addTask { await viewModel.refreshManual() }
            await group.waitForAll()
        }

        // After both complete, the flag must be false (defer reset).
        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualMinimumDisplayDuration() async {
        // With loadsReminders: false, reload() is a no-op (nearly instant).
        // The minimum-display hold keeps isRefreshing true for ≥1 s.
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        let startedAt = Date()
        await viewModel.refreshManual()
        let elapsed = Date().timeIntervalSince(startedAt)

        // Must have waited at least 1 s (allow 0.1 s slop for timing).
        #expect(elapsed >= 0.9)
        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualClearsSkippedWhenAllSkipped() async {
        // Seed one already-skipped reminder via the ReminderStore init so
        // allSkipped is deterministically true (no async skip call needed).
        let calendar = EKCalendar(for: .reminder, eventStore: Self.store)
        calendar.title = "Work"
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Skipped"
        reminder.calendar = calendar
        let inMemory = InMemoryEventStore(reminders: [reminder], calendars: [calendar])

        let store = ReminderStore(
            eventStore: inMemory,
            loadsReminders: true,
            reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.allSkipped == true)

        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        await viewModel.refreshManual()

        // refreshManual passes clearSkipped: store.allSkipped (== true here),
        // so the skipped set is cleared.
        #expect(store.skippedIDs.isEmpty)
    }

    @Test
    func refreshManualPreservesSkippedWhenVisible() async {
        // One visible, non-skipped reminder → allSkipped is false.
        let calendar = EKCalendar(for: .reminder, eventStore: Self.store)
        calendar.title = "Personal"
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Buy milk"
        reminder.calendar = calendar
        let inMemory = InMemoryEventStore(reminders: [reminder], calendars: [calendar])

        let store = ReminderStore(
            eventStore: inMemory,
            loadsReminders: true,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.allSkipped == false)

        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        await viewModel.refreshManual()

        // clearSkipped: false → skippedIDs stays as resolved (empty here).
        #expect(store.skippedIDs.isEmpty)
    }

    // MARK: Private

    private static let store = EKEventStore()
}
