import EventKit
import SingleThreadCore
import Testing

struct ReminderDisplayTests {
    @Test
    func mapsTitle() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        #expect(display.title == "Buy milk")
    }

    @Test
    func formatsNotes() {
        let reminder = makeReminder(title: "Buy milk")
        reminder.notes = "tTwo percent"
        let display = ReminderDisplay(reminder: reminder)
        #expect(display.notes == "Two percent")
    }

    @Test
    func mapsNilNotes() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        #expect(display.notes == nil)
    }

    @Test
    func mapsDueDate() {
        let reminder = makeReminder(title: "Buy milk")
        let components = DateComponents(year: 2025, month: 2, day: 3)
        reminder.dueDateComponents = components
        let display = ReminderDisplay(reminder: reminder)
        guard let date = display.dueDate else {
            Issue.record("expected a due date")
            return
        }
        let calendar = Calendar.current
        let displayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(displayComponents.year == components.year)
        #expect(displayComponents.month == components.month)
        #expect(displayComponents.day == components.day)
    }

    @Test
    func mapsNilDueDate() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        #expect(display.dueDate == nil)
    }

    @Test
    func mapsHighPriorityMarker() {
        let reminder = makeReminder(title: "Buy milk")
        reminder.priority = 1
        #expect(ReminderDisplay(reminder: reminder).priorityMarker == "!!!")
    }

    @Test
    func mapsEmptyMarkerForNoPriority() {
        let reminder = makeReminder(title: "Buy milk")
        reminder.priority = 0
        #expect(ReminderDisplay(reminder: reminder).priorityMarker.isEmpty)
    }

    @Test
    func directConstructorStoresFields() {
        let due = Date()
        let display = ReminderDisplay(
            title: "Next thing",
            notes: "Notes",
            dueDate: due,
            priorityMarker: "!")
        #expect(display.title == "Next thing")
        #expect(display.notes == "Notes")
        #expect(display.dueDate == due)
        #expect(display.priorityMarker == "!")
    }
}

private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    return reminder
}
