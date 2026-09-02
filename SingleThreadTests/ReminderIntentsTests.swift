import AppIntents
import SingleThreadCore
import Testing

// MARK: - ReminderIntents

struct ReminderIntentsTests {
    // MARK: CompleteReminderIntent

    @Test
    func completeIntentIsConfigured() {
        _ = CompleteReminderIntent()
        #expect(!CompleteReminderIntent.isDiscoverable, "complete intent is not discoverable")
        // The intent titles resolve through `.main` (the widget/app bundle's
        // catalog); the Core catalog doesn't hold the AppIntent keys.
        #expect(
            String(localized: CompleteReminderIntent.title)
                == String.en("Complete Reminder", bundle: .main),
            "complete intent title resolves from the app catalog")
    }

    // MARK: SkipReminderIntent

    @Test
    func skipIntentIsConfigured() {
        _ = SkipReminderIntent()
        #expect(!SkipReminderIntent.isDiscoverable, "skip intent is not discoverable")
        #expect(
            String(localized: SkipReminderIntent.title)
                == String.en("Skip Reminder", bundle: .main),
            "skip intent title resolves from the app catalog")
    }
}
