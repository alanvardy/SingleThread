import EventKit
import Foundation
import SingleThreadCore
import Testing

@MainActor private let sharedTestEventStore = EKEventStore()

@MainActor
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
    func mapsListNameFromCalendarTitle() {
        // Construction only — never saved through EventKit.
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Buy milk"
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Groceries"
        reminder.calendar = calendar
        #expect(ReminderDisplay(reminder: reminder).listName == "Groceries")
    }

    @Test
    func mapsNilListNameWhenCalendarMissing() {
        #expect(ReminderDisplay(reminder: makeReminder(title: "Buy milk")).listName == nil)
    }

    @Test
    func mapsHasRecurrenceTrue() {
        let reminder = makeReminder(title: "Milk")
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        #expect(ReminderDisplay(reminder: reminder).hasRecurrence)
    }

    @Test
    func mapsHasRecurrenceFalse() {
        #expect(!ReminderDisplay(reminder: makeReminder(title: "Milk")).hasRecurrence)
    }

    @Test
    func mapsRecurrenceSummary() {
        let reminder = makeReminder(title: "Milk")
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        #expect(ReminderDisplay(reminder: reminder).recurrenceSummary == "Daily")
    }

    @Test
    func nilRecurrenceSummaryWhenNoRules() {
        #expect(ReminderDisplay(reminder: makeReminder(title: "Milk")).recurrenceSummary == nil)
    }

    @Test
    func mapsHasAlarmsTrue() {
        let reminder = makeReminder(title: "Milk")
        reminder.addAlarm(EKAlarm(absoluteDate: Date()))
        #expect(ReminderDisplay(reminder: reminder).hasAlarms)
    }

    @Test
    func mapsHasAlarmsFalse() {
        #expect(!ReminderDisplay(reminder: makeReminder(title: "Milk")).hasAlarms)
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
        #expect(display.title == "Next thing")
        #expect(display.notes == "Notes")
        #expect(display.dueDate == due)
        #expect(display.priorityMarker == "!")
        #expect(display.listName == "Errands")
    }

    @Test
    func titleAttributedReturnsPlainForPlainTitle() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Buy milk"))
        let attributed = display.titleAttributed
        #expect(String(attributed.characters[...]) == "Buy milk")
    }

    @Test
    func titleAttributedStripsBackticks() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Use `map` now"))
        let attributed = display.titleAttributed
        #expect(String(attributed.characters[...]) == "Use map now")
    }

    @Test
    func notesAttributedReturnsNilForNilNotes() {
        let display = ReminderDisplay(reminder: makeReminder(title: "Test"))
        #expect(display.notesAttributed == nil)
    }

    @Test
    func notesAttributedStripsBackticks() throws {
        let reminder = makeReminder(title: "Use `map`")
        reminder.notes = "See `filter` docs"
        let display = ReminderDisplay(reminder: reminder)
        let attributed = display.notesAttributed
        #expect(attributed != nil)
        #expect(try String(#require(attributed?.characters[...])) == "See filter docs")
    }

    @Test
    func notesAttributedRunsAfterNotesFormatter() throws {
        // Verifies the pipeline: EKReminder.notes → ReminderNotesFormatter → CodeSpanFormatter
        let reminder = makeReminder(title: "Test")
        reminder.notes = "tUse `map`" // t-artifact + code span
        let display = ReminderDisplay(reminder: reminder)
        let attributed = display.notesAttributed
        #expect(attributed != nil)
        let text = try String(#require(attributed?.characters[...]))
        #expect(text == "Use map") // t stripped, backticks stripped
    }
}

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    return reminder
}
