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

    // MARK: Private

    private static let store = EKEventStore()
}
