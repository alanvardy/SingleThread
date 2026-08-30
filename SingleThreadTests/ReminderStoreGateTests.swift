import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

@MainActor
@Suite(.serialized)
struct ReminderStoreGateTests {
    // MARK: Internal

    // MARK: - canMutate transitions

    @Test
    func canMutateTrueWhenCountBelow100AndNotEntitled() {
        let store = makeStore(count: 50, entitled: false)
        #expect(store.canMutate)
    }

    @Test
    func canMutateFalseWhenCountAt100AndNotEntitled() {
        let store = makeStore(count: 100, entitled: false)
        #expect(!store.canMutate)
    }

    @Test
    func canMutateTrueWhenCountAt100AndEntitled() {
        let store = makeStore(count: 100, entitled: true)
        #expect(store.canMutate)
    }

    @Test
    func canMutateTrueWhenCountBelow100AndEntitled() {
        let store = makeStore(count: 50, entitled: true)
        #expect(store.canMutate)
    }

    // MARK: - completeReminder gating

    @Test
    func completeReminderReturnsFalseWhenGated() async {
        let counter = seededCounter(100)
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: .init(testingWithEntitled: false))
        let result = await store.completeReminder(
            identifier: rem.calendarItemIdentifier)
        #expect(!result)
        #expect(counter.count == 100) // unchanged
    }

    @Test
    func completeReminderIncrementsCounterOnSuccess() async {
        let counter = seededCounter(50)
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: .init(testingWithEntitled: false))
        let result = await store.completeReminder(
            identifier: rem.calendarItemIdentifier)
        #expect(result)
        #expect(counter.count == 51)
    }

    // MARK: - skipCurrentReminder gating

    @Test
    func skipCurrentReminderNoOpsWhenGated() {
        let counter = seededCounter(100)
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            skipStore: SkippedReminderStore(
                defaults: .standard,
                key: UUID().uuidString),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: .init(testingWithEntitled: false))
        store.skipCurrentReminder()
        // The skip should be a no-op: the reminder is still visible.
        #expect(!store.visibleReminders.isEmpty)
        #expect(store.skippedIDs.isEmpty)
    }

    @Test
    func skipCurrentReminderWorksWhenNotGated() async {
        let counter = seededCounter(50)
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            skipStore: SkippedReminderStore(
                defaults: .standard,
                key: UUID().uuidString),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: .init(testingWithEntitled: false))
        store.skipCurrentReminder()
        // `skipCurrentReminder` applies the skip inside a `Task` after the
        // 200ms settle sleep — wait for it before asserting.
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(store.skippedIDs.contains(rem.calendarItemIdentifier))
    }

    // MARK: - deleteReminder gating

    @Test
    func deleteReminderNoOpsWhenGated() async {
        let counter = seededCounter(100)
        let rem = makeReminder(title: "A")
        let eventStore = InMemoryEventStore(reminders: [rem])
        let store = ReminderStore(
            eventStore: eventStore,
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            completionCounter: counter,
            entitlementStore: .init(testingWithEntitled: false))
        await store.deleteReminder(
            identifier: rem.calendarItemIdentifier)
        // Reminder still present in the in-memory store.
        #expect(!eventStore.allReminders.isEmpty)
    }

    // MARK: Private

    // MARK: - Helpers

    /// Builds a `ReminderStore` with a seeded counter and the entitlement seam.
    private func makeStore(count: Int, entitled: Bool) -> ReminderStore {
        ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            completionCounter: seededCounter(count),
            entitlementStore: .init(testingWithEntitled: entitled))
    }

    /// Creates a seeded counter that reads from a specific value.
    private func seededCounter(_ value: Int) -> CompletionCounterStore {
        let key = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return CompletionCounterStore(defaults: .standard, key: key)
    }

    private func makeReminder(title: String, priority: Int = 5) -> EKReminder {
        let reminder = EKReminder(eventStore: sharedTestEventStore)
        reminder.title = title
        reminder.priority = priority
        return reminder
    }
}

@MainActor private let sharedTestEventStore = EKEventStore()
