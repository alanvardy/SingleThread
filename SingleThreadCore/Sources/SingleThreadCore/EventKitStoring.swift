import EventKit
import Foundation

/// Test seam: abstracts the EventKit surface `ReminderStore` calls so tests can
/// inject a recording fake. Follows the pattern of `SkipSyncSession` and
/// `SpeechTranscribing`.
@MainActor
public protocol EventKitStoring: AnyObject {
    /// Instance-form authorization check wrapping the `EKEventStore` static.
    func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus

    func requestFullAccessToReminders() async throws -> Bool

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]?) -> NSPredicate

    @discardableResult
    func fetchReminders(
        matching predicate: NSPredicate,
        completion: @escaping ([EKReminder]?) -> Void) -> Any

    #if !os(watchOS)
        func refreshSourcesIfNecessary()

        func defaultCalendarForNewReminders() -> EKCalendar?

        func save(_ reminder: EKReminder, commit: Bool) throws

        /// Builds a new `EKReminder` from the given fields (was the static
        /// `ReminderStore.makeReminder` factory).
        func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule?) -> EKReminder
    #endif
}

extension EKEventStore: EventKitStoring {
    public func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: entityType)
    }

    #if !os(watchOS)
        public func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule? = nil) -> EKReminder {
            let reminder = EKReminder(eventStore: self)
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = defaultCalendarForNewReminders()
            return reminder
        }
    #endif
}