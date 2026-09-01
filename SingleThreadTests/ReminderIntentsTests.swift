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
        // The intent titles resolve through `.main` (the widget/app bundle's
        // catalog); the Core catalog doesn't hold the AppIntent keys.
        #expect(String(localized: CompleteReminderIntent.title)
            == String.en("Complete Reminder", bundle: .main))
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
        #expect(String(localized: SkipReminderIntent.title)
            == String.en("Skip Reminder", bundle: .main))
    }
}
