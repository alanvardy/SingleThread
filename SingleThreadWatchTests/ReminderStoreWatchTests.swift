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

    @Test
    func completeReminderPreservesPriorPendingEntries() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        pendingStore(key: key).record("prior-id")
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)

        #expect(pendingStore(key: key).load().contains(rem.calendarItemIdentifier))
        #expect(pendingStore(key: key).load().contains("prior-id"))
    }

    // MARK: - Reschedule relay

    @Test
    func rescheduleFiresRelayHookAndReturnsTrue() async {
        let key = "watch-resched-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var receivedIdentifier: String?
        var receivedComponents: DateComponents?
        store.onRescheduleReminder = { identifier, components in
            receivedIdentifier = identifier
            receivedComponents = components
        }
        let due = DateComponents(year: 2027, month: 1, day: 2)

        let rescheduled = await store.rescheduleReminder(
            identifier: rem.calendarItemIdentifier,
            to: due)

        // The watch prizes the relay over a local EventKit write: the hook fires
        // with the exact components and the call reports success.
        #expect(rescheduled)
        #expect(receivedIdentifier == rem.calendarItemIdentifier)
        #expect(receivedComponents?.year == 2027)
        #expect(receivedComponents?.month == 1)
        #expect(receivedComponents?.day == 2)
    }

    @Test
    func rescheduleNoOpWhenGated() async {
        let key = "watch-resched-gated-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(EntitlementStore.freemiumCap, forKey: key)
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: CompletionCounterStore(defaults: .standard, key: key),
            entitlementStore: EntitlementStore(testingWithEntitled: false))
        var fired = false
        store.onRescheduleReminder = { _, _ in fired = true }

        let rescheduled = await store.rescheduleReminder(
            identifier: rem.calendarItemIdentifier,
            to: DateComponents(year: 2027, month: 1, day: 2))

        // `canMutate` gates before the relay — same guard as every other write.
        #expect(!rescheduled)
        #expect(!fired)
    }

    // MARK: Private

    private func pendingStore(key: String) -> PendingCompletionStore {
        PendingCompletionStore(defaults: .standard, key: key)
    }
}
