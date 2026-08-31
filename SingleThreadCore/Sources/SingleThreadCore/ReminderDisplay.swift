import EventKit
import Foundation
import os

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
        if ![0, 1, 5, 9].contains(reminder.priority) {
            os_log(
                .debug,
                "ReminderDisplay: non-standard priority %d for reminder %{public}@",
                reminder.priority,
                reminder.calendarItemIdentifier)
        }
        listName = reminder.calendar?.title
        hasRecurrence = reminder.hasRecurrenceRules
        recurrenceSummary = ReminderRecurrenceFormatter.format(reminder.recurrenceRules)
        hasAlarms = reminder.hasAlarms
    }

    /// Constructor for tests, previews, and placeholder entries.
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

    // MARK: Public

    public let title: String
    public let notes: String?
    public let dueDate: Date?
    public let priorityMarker: String
    public let listName: String?
    public let hasRecurrence: Bool
    public let recurrenceSummary: String?
    public let hasAlarms: Bool

    // MARK: Attributed variants

    /// `title` with any backtick-delimited code spans styled as monospaced.
    /// Backtick fences are stripped from the visible string.
    public var titleAttributed: AttributedString {
        CodeSpanFormatter.format(title)
    }

    /// `notes` with any backtick-delimited code spans styled as monospaced,
    /// or `nil` when raw notes is `nil`. Runs after `ReminderNotesFormatter`
    /// (already applied during `init`).
    public var notesAttributed: AttributedString? {
        guard let notes else { return nil }
        return CodeSpanFormatter.format(notes)
    }
}
