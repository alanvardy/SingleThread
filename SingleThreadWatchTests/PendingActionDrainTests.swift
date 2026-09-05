import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch-app drain of the widget-process mailbox: the recorded
/// action is applied through the store (whose relay hooks were wired exactly as
/// `setupSyncService` does) and the mailbox is cleared afterwards.
@MainActor
struct PendingActionDrainTests {
    // MARK: Internal

    @Test
    func drainAppliesCompletionAndFiresRelay() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess) {}
        var relayed: [String] = []
        store.onCompleteReminder = { relayed.append($0) }
        let actionStore = isolatedActionStore()
        actionStore.save(PendingReminderAction(kind: .complete, identifier: reminder.calendarItemIdentifier))

        await WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: actionStore)

        #expect(relayed == [reminder.calendarItemIdentifier])
        #expect(actionStore.load() == nil)
    }

    @Test
    func drainSkipFiresPushAll() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess) {}
        var pushed: [String] = []
        store.onSkipSetChanged = { pushed = $0 }
        let actionStore = isolatedActionStore()
        actionStore.save(PendingReminderAction(kind: .skip, identifier: reminder.calendarItemIdentifier))

        await WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: actionStore)
        // `skipCurrentReminder()` applies the skip inside an internal task after
        // the injected noop settle — yield until the hook fires (as
        // WatchSyncPipelineTests does for its receive hooks).
        var attempts = 0
        while pushed.isEmpty, attempts < 50 {
            await Task.yield()
            attempts += 1
        }

        #expect(pushed.contains(reminder.calendarItemIdentifier))
        #expect(actionStore.load() == nil)
    }

    @Test
    func drainNoOpsWhenMailboxEmpty() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .fullAccess) {}
        store.onCompleteReminder = { _ in Issue.record("relay fired with empty mailbox") }
        await WatchAppViewModel.drainPendingReminderAction(store: store, actionStore: isolatedActionStore())
        #expect(store.reminders.isEmpty)
    }

    // MARK: Private

    /// Reuse the process-wide shared EKEventStore so EKReminder creation never
    /// exceeds EventKit's per-process connection cap (see ReminderStoreWatchTests).
    private static let scratchStore = EKEventStore()

    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: Self.scratchStore)
        reminder.title = title
        return reminder
    }

    private func isolatedActionStore() -> PendingReminderActionStore {
        let suite = "PendingActionDrainTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PendingReminderActionStore(defaults: defaults)
    }
}
