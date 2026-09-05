import EventKit
import SingleThreadCore
import Testing

@MainActor
struct ReminderWidgetStateTests {
    // MARK: Internal

    @Test
    func makeWidgetStateReturnsReminderForSeededStore() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .reminder(ReminderDisplay(reminder: reminder)))
    }

    @Test
    func makeWidgetStateReturnsEmptyWhenNoReminders() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .fullAccess) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .empty(hasHidden: false))
    }

    @Test
    func makeWidgetStateReturnsEmptyWithHiddenWhenSeeded() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .fullAccess, hasHidden: true) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .empty(hasHidden: true))
    }

    @Test
    func makeWidgetStateReturnsAllDoneWhenEverythingSkipped() async {
        let reminder = makeReminder(title: "Next thing")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [reminder]),
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier],
            authorizationStatus: .fullAccess) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .fullAccess)
        #expect(state == .allDone)
    }

    @Test
    func makeWidgetStateReturnsNoAccessWhenDenied() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .denied) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .denied)
        #expect(state == .noAccess)
    }

    @Test
    func makeWidgetStateReturnsNoAccessWhenNotDetermined() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(), loadsReminders: false,
            reminders: [], authorizationStatus: .notDetermined) {}
        let state = await ReminderWidgetState.makeWidgetState(store: store, authorization: .notDetermined)
        #expect(state == .noAccess)
    }

    // MARK: Private

    /// Reuse the process-wide shared EKEventStore so EKReminder creation never
    /// exceeds EventKit's per-process connection cap (see ReminderStoreTests).
    private static let scratchStore = EKEventStore()

    private func makeReminder(title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: Self.scratchStore)
        reminder.title = title
        return reminder
    }
}
