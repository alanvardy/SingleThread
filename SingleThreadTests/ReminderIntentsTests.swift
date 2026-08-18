import AppIntents
import SingleThreadCore
import Testing

// MARK: - ReminderIntents

struct ReminderIntentsTests {
    // MARK: CompleteReminderIntent

    @Test
    func completeIntentInitializes() {
        _ = CompleteReminderIntent()
        #expect(Bool(true))
    }

    @Test
    func completeIntentIsNotDiscoverable() {
        #expect(CompleteReminderIntent.isDiscoverable == false)
    }

    @Test
    func completeIntentHasTitle() {
        #expect(String(localized: CompleteReminderIntent.title) == "Complete Reminder")
    }

    // MARK: SkipReminderIntent

    @Test
    func skipIntentInitializes() {
        _ = SkipReminderIntent()
        #expect(Bool(true))
    }

    @Test
    func skipIntentIsNotDiscoverable() {
        #expect(SkipReminderIntent.isDiscoverable == false)
    }

    @Test
    func skipIntentHasTitle() {
        #expect(String(localized: SkipReminderIntent.title) == "Skip Reminder")
    }
}
