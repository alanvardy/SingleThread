import AppIntents
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

    #if os(watchOS)
        /// The Smart Stack button opens the watch app, whose `.task` drains the
        /// mailbox and relays through the already-wired `onCompleteReminder` hook.
        public static var openAppWhenRun: Bool {
            true
        }
    #endif

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if os(watchOS)
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            guard let identifier = store.visibleReminders.first?.calendarItemIdentifier else {
                return .result()
            }
            PendingReminderActionStore().save(
                PendingReminderAction(kind: .complete, identifier: identifier))
            return .result()
        #else
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            await store.completeCurrentReminder()
            return .result()
        #endif
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

    #if os(watchOS)
        /// The Smart Stack button opens the watch app, whose `.task` drains the
        /// mailbox and relays through the already-wired `onSkipSetChanged` hook.
        public static var openAppWhenRun: Bool {
            true
        }
    #endif

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if os(watchOS)
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            guard let identifier = store.visibleReminders.first?.calendarItemIdentifier else {
                return .result()
            }
            PendingReminderActionStore().save(
                PendingReminderAction(kind: .skip, identifier: identifier))
            return .result()
        #else
            let store = ReminderStore(loadsReminders: true)
            store.setSortOption(SortOptionStore().load())
            await store.reload()
            // Route the skip through the store like `CompleteReminderIntent` so the
            // write goes through the same code path (persistence plus the
            // onSkipSetChanged / onRemindersChanged hooks) instead of duplicating the
            // skip logic and writing UserDefaults directly.
            store.skipCurrentReminderImmediately()
            return .result()
        #endif
    }
}
