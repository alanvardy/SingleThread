import EventKit
import SingleThreadCore
import Testing

// MARK: - Canvas/render regression

/// Construction only — never saved through EventKit.
@MainActor
private func canvasReminder() -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 18, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    return reminder
}

@MainActor
struct WatchReminderViewRegressionTests {
    @Test
    func rendersEveryReminderDisplayFieldWithoutCrashing() {
        let reminder = canvasReminder()
        let display = ReminderDisplay(reminder: reminder)

        // Every property the canvas renders must be readable; reading one from
        // a deallocated backing store crashes with SIGTRAP.
        #expect(display.title == "Buy groceries")
        #expect(display.notes == "Don't forget the milk")
        let components = reminder.dueDateComponents
        #expect(components?.month == 8)
        #expect(display.priorityMarker != "")
        #expect(display.listName == nil)
        #expect(!display.hasRecurrence)
        #expect(!display.hasAlarms)
    }
}
