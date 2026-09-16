import AppIntents
import EventKit
import Foundation

/// Completes the current (first visible) reminder. Invoked from the widget's
/// Complete button; the tapped widget's timeline reloads automatically after
/// `perform()` returns.
public struct CompleteReminderIntent: AppIntent {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let title: LocalizedStringResource = "Complete Reminder"
    public static let isDiscoverable = false

    @MainActor
    public func perform() async throws -> some IntentResult {
        let store = ReminderStore(loadsReminders: true)
        store.setSortOption(SortOptionStore().load())
        await store.reload()
        await store.completeCurrentReminder()
        return .result()
    }
}

/// Skips the current (first visible) reminder by adding its identifier to the
/// shared skip list. Runs from the widget extension, so it writes directly to
/// the App Group-backed store and never prompts for access.
public struct SkipReminderIntent: AppIntent {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let title: LocalizedStringResource = "Skip Reminder"
    public static let isDiscoverable = false

    @MainActor
    public func perform() async throws -> some IntentResult {
        let store = ReminderStore(loadsReminders: true)
        store.setSortOption(SortOptionStore().load())
        await store.reload()
        // Route the skip through the store like `CompleteReminderIntent` so the
        // write goes through the same code path (persistence plus the
        // onSkipSetChanged / onRemindersChanged hooks) instead of duplicating the
        // skip logic and writing UserDefaults directly.
        store.skipCurrentReminderImmediately()
        return .result()
    }
}

/// Returns the current next task's title, spoken and usable as a Shortcuts value.
public struct WhatsNextIntent: AppIntent {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let title: LocalizedStringResource = "What's Next"
    public static let isDiscoverable = true

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let eventStore = EKEventStore()
        let outcome: ReminderIntentOutcome = if let store = await ReminderIntentSupport.makeStore(
            eventStore: eventStore,
            authorizationStatus: EKEventStore.authorizationStatus(for: .reminder)) {
            ReminderIntentSupport.nextOutcome(for: store)
        } else {
            .noAccess
        }
        return .result(
            value: ReminderIntentSupport.value(for: outcome),
            dialog: IntentDialog(ReminderIntentSupport.dialog(for: outcome)))
    }
}
