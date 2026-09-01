import EventKit
import SingleThreadCore
import Testing

// MARK: - Fixture

/// A single `EKEventStore` kept alive to back the test reminders. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor private let sharedWatchEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

/// Covers the watch-side pending-completion insertion: `completeReminder` on
/// watchOS records the completed identifier so a `reload()` before the phone
/// processes the relay cannot resurrect (or double-complete) the reminder.
/// Serialized because every test uses an isolated custom-key `.standard` store;
/// the defer cleanup plus unique keys prevent cross-test leakage regardless.
@MainActor
@Suite(.serialized)
struct ReminderStoreWatchTests {
    // MARK: Internal

    @Test
    func completeReminderInsertsAndPersistsPendingCompletion() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        let completed = await store.completeReminder(identifier: rem.calendarItemIdentifier)

        #expect(completed)
        #expect(pendingStore(key: key).load().contains(rem.calendarItemIdentifier))
    }

    @Test
    func reloadHidesPendingCompletion() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
        #expect(pendingStore(key: key).load().contains(rem.calendarItemIdentifier))

        await store.reload() // simulated pull-refresh before phone processes relay

        #expect(store.reminders.isEmpty) // pending-filtered — NOT resurrected
    }

    @Test
    func completeReminderNoOpWhenIdentifierMissing() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        let completed = await store.completeReminder(identifier: "nonexistent")

        #expect(!completed)
        #expect(pendingStore(key: key).load().isEmpty)
    }

    // MARK: Private

    private func pendingStore(key: String) -> PendingCompletionStore {
        PendingCompletionStore(defaults: .standard, key: key)
    }
}
