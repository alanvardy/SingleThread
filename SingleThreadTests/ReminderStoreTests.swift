import EventKit
@testable import SingleThreadCore
import Testing

// MARK: - ReminderStore.addReminder

@MainActor
struct ReminderStoreTests {
    @Test
    func addReminderDoesNotCrashWithoutAccess() async {
        let store = ReminderStore(loadsReminders: false)
        // Without EventKit authorization the save fails and is logged internally;
        // the important assertion is that this completes without crashing.
        await store.addReminder(
            title: "Buy milk",
            notes: "Two percent",
            dueDate: DateComponents(year: 2025, month: 1, day: 2))
    }

    @Test
    func addReminderKeepsExistingRemindersUntouched() async {
        let store = ReminderStore(
            loadsReminders: false,
            reminders: [makeReminder(title: "Existing")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await store.addReminder(title: "New", notes: nil, dueDate: nil)
        #expect(store.reminders.count == 1)
        #expect(store.reminders.first?.title == "Existing")
    }
}

// MARK: - makeReminder test seam

#if !os(watchOS)
    @MainActor
    struct MakeReminderTests {
        @Test
        func makeReminderSetsTitle() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.title == "Buy milk")
        }

        @Test
        func makeReminderSetsNotes() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: "Two percent",
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.notes == "Two percent")
        }

        @Test
        func makeReminderSetsDueDate() {
            let dueDate = DateComponents(year: 2025, month: 1, day: 2)
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: dueDate,
                eventStore: EKEventStore())
            #expect(reminder.dueDateComponents?.year == dueDate.year)
            #expect(reminder.dueDateComponents?.month == dueDate.month)
            #expect(reminder.dueDateComponents?.day == dueDate.day)
        }

        @Test
        func makeReminderLeavesUnsetFieldsNil() {
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore())
            #expect(reminder.notes == nil)
            #expect(reminder.dueDateComponents == nil)
            #expect(reminder.hasRecurrenceRules == false)
        }

        @Test
        func makeReminderSetsRecurrenceRule() {
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: EKEventStore(),
                recurrenceRule: rule)
            #expect(reminder.recurrenceRules?.count == 1)
            #expect(reminder.recurrenceRules?.first?.frequency == .weekly)
            #expect(reminder.recurrenceRules?.first?.interval == 1)
        }

        @Test
        func makeReminderSetsDefaultCalendar() {
            let eventStore = EKEventStore()
            let reminder = ReminderStore.makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                eventStore: eventStore)
            #expect(reminder.calendar == eventStore.defaultCalendarForNewReminders())
        }
    }
#endif

// MARK: - Fixtures

private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    return reminder
}
