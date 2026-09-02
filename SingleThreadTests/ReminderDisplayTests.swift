import EventKit
import Foundation
import SingleThreadCore
import Testing

@MainActor private let sharedTestEventStore = EKEventStore()

@MainActor
struct ReminderDisplayTests {
    // MARK: Internal

    @Test
    func titleAndNotesMap() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        #expect(display.title == "Buy milk", "title maps through")
        #expect(display.notes == nil, "nil notes stay nil")
        let reminder = makeReminder(title: "Buy milk")
        reminder.notes = "tTwo percent"
        #expect(
            ReminderDisplay(reminder: reminder).notes == "Two percent",
            "notes run through the notes formatter")
    }

    @Test
    func mapsDueDate() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        #expect(display.dueDate == nil, "nil due date stays nil")
        let reminder = makeReminder(title: "Buy milk")
        let components = DateComponents(year: 2025, month: 2, day: 3)
        reminder.dueDateComponents = components
        let dated = ReminderDisplay(reminder: reminder)
        guard let date = dated.dueDate else {
            Issue.record("expected a due date")
            return
        }
        let calendar = Calendar.current
        let displayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(displayComponents.year == components.year, "year maps")
        #expect(displayComponents.month == components.month, "month maps")
        #expect(displayComponents.day == components.day, "day maps")
    }

    @Test(arguments: [
        (0, ""),
        (1, "!!!"),
        (2, "!!!"),
        (4, "!!!"),
        (6, "!"),
        (8, "!")
    ])
    func priorityMarkerMaps(_ spec: (priority: Int, expected: String)) {
        let reminder = makeReminder(title: "P\(spec.priority)")
        reminder.priority = spec.priority
        #expect(
            ReminderDisplay(reminder: reminder).priorityMarker == spec.expected,
            "priority \(spec.priority) → \(spec.expected)")
    }

    @Test
    func listNameFollowsCalendar() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Buy milk"
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Groceries"
        reminder.calendar = calendar
        #expect(
            ReminderDisplay(reminder: reminder).listName == "Groceries",
            "calendar title becomes list name")
        #expect(
            ReminderDisplay(reminder: makeReminder(title: "Buy milk")).listName == nil,
            "missing calendar → nil list name")
    }

    @Test(arguments: [true, false])
    func alarmsFlagFollowsReminderAlarms(_ hasAlarm: Bool) {
        let reminder = makeReminder(title: "Milk")
        if hasAlarm {
            reminder.addAlarm(EKAlarm(absoluteDate: Date()))
        }
        #expect(
            ReminderDisplay(reminder: reminder).hasAlarms == hasAlarm,
            "has alarms: \(hasAlarm)")
    }

    @Test
    func directConstructorCreatesFields() {
        let due = Date()
        let display = ReminderDisplay(
            title: "Next thing",
            notes: "Notes",
            dueDate: due,
            priorityMarker: "!",
            listName: "Errands")
        #expect(display.title == "Next thing", "title")
        #expect(display.notes == "Notes", "notes")
        #expect(display.dueDate == due, "due date")
        #expect(display.priorityMarker == "!", "priority marker")
        #expect(display.listName == "Errands", "list name")
    }

    @Test(arguments: [
        ("Buy milk", "Buy milk"),
        ("Use `map` now", "Use map now")
    ])
    func titleAttributedStripsCodeSpans(_ pair: (title: String, expected: String)) {
        let display = ReminderDisplay(reminder: makeReminder(title: pair.title))
        #expect(
            String(display.titleAttributed.characters[...]) == pair.expected,
            "\(pair.title) → \(pair.expected)")
    }

    @Test
    func notesAttributedStripsBackticksAfterNotesFormatter() throws {
        #expect(
            ReminderDisplay(reminder: makeReminder(title: "Test")).notesAttributed == nil,
            "nil notes → nil attributed")
        let backticks = makeReminder(title: "Use `map`")
        backticks.notes = "See `filter` docs"
        let attributed = ReminderDisplay(reminder: backticks).notesAttributed
        #expect(attributed != nil, "non-nil notes → non-nil attributed")
        #expect(
            try String(#require(attributed?.characters[...])) == "See filter docs",
            "backticks stripped from notes")

        let artifacted = makeReminder(title: "Test")
        artifacted.notes = "tUse `map`" // t-artifact + code span
        let pipeline = ReminderDisplay(reminder: artifacted).notesAttributed
        #expect(pipeline != nil, "artifacted notes → non-nil attributed")
        let text = try String(#require(pipeline?.characters[...]))
        #expect(text == "Use map", "t stripped by notes formatter, backticks by code-span formatter")
    }

    // MARK: Private

    private struct RecurrenceCase: Sendable {
        let addsRule: Bool
        let expectedHasRecurrence: Bool
        let expectedSummary: String?
    }

    @Test(arguments: [
        RecurrenceCase(addsRule: false, expectedHasRecurrence: false, expectedSummary: nil),
        RecurrenceCase(addsRule: true, expectedHasRecurrence: true, expectedSummary: "Daily")
    ])
    private func recurrenceFlagsAndSummary(_ spec: RecurrenceCase) {
        let reminder = makeReminder(title: "Milk")
        if spec.addsRule {
            reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        }
        let display = ReminderDisplay(reminder: reminder)
        #expect(display.hasRecurrence == spec.expectedHasRecurrence, "has-recurrence for rule added: \(spec.addsRule)")
        #expect(
            display.recurrenceSummary == spec.expectedSummary,
            "summary for rule added: \(spec.addsRule)")
    }
}

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    return reminder
}
