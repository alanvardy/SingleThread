import EventKit
import Foundation

/// Display-ready fields for a single reminder, decoupled from `EKReminder`.
/// Used by the widget timeline entry and unit tests.
public struct ReminderDisplay: Equatable, Sendable {
    // MARK: Lifecycle

    /// Maps an `EKReminder` to its display fields, applying the same note and
    /// priority formatting as the app and watch views.
    public init(reminder: EKReminder) {
        title = reminder.title
        notes = ReminderNotesFormatter.format(reminder.notes)
        dueDate = reminder.dueDateComponents?.date
        priorityMarker = ReminderPriority.marker(for: reminder.priority)
        listName = reminder.calendar?.title
        hasRecurrence = reminder.hasRecurrenceRules
        recurrenceSummary = ReminderRecurrenceFormatter.format(reminder.recurrenceRules)
        hasAlarms = reminder.hasAlarms
    }

    /// Full constructor for tests and previews that need the new fields.
    public init(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priorityMarker: String = "",
        listName: String? = nil,
        hasRecurrence: Bool = false,
        recurrenceSummary: String? = nil,
        hasAlarms: Bool = false) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priorityMarker = priorityMarker
        self.listName = listName
        self.hasRecurrence = hasRecurrence
        self.recurrenceSummary = recurrenceSummary
        self.hasAlarms = hasAlarms
    }

    /// Direct constructor for previews, placeholder entries, and tests.
    public init(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priorityMarker: String = "",
        listName: String? = nil) {
        self.init(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priorityMarker: priorityMarker,
            listName: listName,
            hasRecurrence: false,
            recurrenceSummary: nil,
            hasAlarms: false)
    }

    // MARK: Public

    public let title: String
    public let notes: String?
    public let dueDate: Date?
    public let priorityMarker: String
    public let listName: String?
    public let hasRecurrence: Bool
    public let recurrenceSummary: String?
    public let hasAlarms: Bool
}
