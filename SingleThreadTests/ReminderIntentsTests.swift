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

    // MARK: WhatsNextIntent

    @Test
    func whatsNextIntentIsDiscoverable() {
        _ = WhatsNextIntent()
        #expect(WhatsNextIntent.isDiscoverable, "whats-next intent is discoverable")
    }

    @Test
    func whatsNextIntentTitleResolves() {
        #expect(
            String(localized: WhatsNextIntent.title)
                == String.en("What's Next", bundle: .main),
            "whats-next intent title resolves from the app catalog")
    }

    // MARK: CompleteCurrentTaskIntent

    @Test
    func completeCurrentTaskIntentIsDiscoverable() {
        _ = CompleteCurrentTaskIntent()
        #expect(CompleteCurrentTaskIntent.isDiscoverable, "complete task intent is discoverable")
    }

    @Test
    func completeCurrentTaskIntentTitleResolves() {
        #expect(
            String(localized: CompleteCurrentTaskIntent.title)
                == String.en("Complete Current Task", bundle: .main),
            "complete task intent title resolves from the app catalog")
    }

    // MARK: SkipCurrentTaskIntent

    @Test
    func skipCurrentTaskIntentIsDiscoverable() {
        _ = SkipCurrentTaskIntent()
        #expect(SkipCurrentTaskIntent.isDiscoverable, "skip task intent is discoverable")
    }

    @Test
    func skipCurrentTaskIntentTitleResolves() {
        #expect(
            String(localized: SkipCurrentTaskIntent.title)
                == String.en("Skip Current Task", bundle: .main),
            "skip task intent title resolves from the app catalog")
    }

    // MARK: Title collisions (design Risk 6)

    @Test
    func intentTitlesDoNotCollideWithWidgetIntentTitles() {
        #expect(CompleteCurrentTaskIntent.title.key != CompleteReminderIntent.title.key)
        #expect(SkipCurrentTaskIntent.title.key != SkipReminderIntent.title.key)
    }
}
