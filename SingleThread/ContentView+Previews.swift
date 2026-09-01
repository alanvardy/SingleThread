import EventKit
import SingleThreadCore
import SwiftUI

// MARK: - Preview Helpers

/// A single `EKEventStore` kept alive to back the preview reminders. The
/// backing store must outlive the reminders — `EKReminder` holds a weak
/// reference to it, so a deallocated store crashes canvas with SIGTRAP.
private let mockPreviewEventStore = EKEventStore()

private let mockReminder: EKReminder = {
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    reminder.url = URL(string: "https://example.com/shopping-list")
    reminder.addRecurrenceRule(EKRecurrenceRule(
        recurrenceWith: .weekly, interval: 1, end: nil))
    return reminder
}()

private let mockReminderInList: EKReminder = {
    let calendar = EKCalendar(for: .reminder, eventStore: mockPreviewEventStore)
    calendar.title = "Groceries"
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy milk"
    reminder.calendar = calendar
    return reminder
}()

// MARK: - Previews

#Preview("Empty") {
    ContentView(
        loadsReminders: false,
        eventStore: InMemoryEventStore())
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("Nothing Due") {
    ContentView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        hasHidden: true)
}

#Preview("With Reminder") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("All Skipped") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [mockReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("All Excluded") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminderInList],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        excludedListTitles: ["Groceries"])
}

#Preview("No Access") {
    ContentView(
        loadsReminders: true,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}
