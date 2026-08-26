import EventKit
import SingleThreadCore
import Testing

// MARK: - Canvas/render regression

/// A single `EKEventStore` kept alive to back the preview reminders. The
/// backing store must outlive the reminders — `EKReminder` holds a weak
/// reference to it, so a deallocated store crashes (SIGTRAP) when any property
/// is read. `WatchReminderView.swift` holds a file-level store for the same
/// reason; this regression asserts the render path (every `ReminderDisplay`
/// field) is readable when the store survives, which is precisely what the
/// canvas evaluates when it renders the preview.
@MainActor
private let sharedWatchEventStore = EKEventStore()

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
