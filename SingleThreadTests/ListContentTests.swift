import EventKit
@testable import SingleThreadCore
import Testing

@MainActor private let sharedTestEventStore = EKEventStore()

@MainActor
@Suite(.serialized)
struct ListContentTests {
    // MARK: Internal

    @Test
    func listContentReturnsAllDoneWhenAllSkipped() {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .allDone)
    }

    @Test
    func listContentReturnsReminderWhenVisible() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "A")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        guard case let .reminder(display) = store.listContent else {
            Issue.record("expected .reminder, got \(store.listContent)")
            return
        }
        #expect(display.title == "A")
    }

    @Test
    func listContentReturnsEmptyWithoutHidden() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .empty(hasHidden: false))
    }

    @Test
    func listContentReturnsEmptyWithHidden() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            hasHidden: true)
        #expect(store.listContent == .empty(hasHidden: true))
    }

    @Test
    func emptyStoreNeverReturnsAllDone() {
        // Pin the mutual-exclusivity invariant: `allSkipped` requires a non-empty
        // store (ReminderStore.swift:139), so an empty store must resolve `.empty`.
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.listContent == .empty(hasHidden: false))
        #expect(store.listContent != .allDone)
    }

    @Test
    func emptyHasHiddenPayloadDiffers() {
        #expect(ListContent.empty(hasHidden: false) != ListContent.empty(hasHidden: true))
    }

    // MARK: Private

    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: sharedTestEventStore)
        reminder.title = title
        return reminder
    }
}
