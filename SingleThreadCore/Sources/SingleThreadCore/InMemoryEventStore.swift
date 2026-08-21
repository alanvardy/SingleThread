import EventKit
import Foundation

/// Test seam: an in-memory `EventKitStoring` implementation backed by an array
/// of `EKReminder`.
///
/// UI tests seed it from launch arguments (via ``UITestingSeed``) so they can
/// drive deterministic reminder mutations — complete, delete, add — without
/// touching a real `EKEventStore`. It reports `.fullAccess` and returns its
/// seeded reminder list from every fetch (filtering out completed reminders to
/// mirror `predicateForIncompleteReminders`).
@MainActor
public final class InMemoryEventStore: EventKitStoring {
    // MARK: Lifecycle

    public init(
        reminders: [EKReminder] = [],
        calendars: [EKCalendar] = [],
        deliverCompletionOffMain: Bool = false) {
        allReminders = reminders
        self.calendars = calendars
        self.deliverCompletionOffMain = deliverCompletionOffMain
    }

    // MARK: Public

    /// The complete set of reminders held in memory, including any completed ones
    /// so a caller can observe them via `allReminders` if desired.
    public private(set) var allReminders: [EKReminder]

    // MARK: EventKitStoring

    public func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus {
        .fullAccess
    }

    public func calendars(for _: EKEntityType) -> [EKCalendar] {
        calendars
    }

    public func requestFullAccessToReminders() async throws -> Bool {
        true
    }

    public func predicateForIncompleteReminders(
        withDueDateStarting _: Date?,
        ending _: Date?,
        calendars _: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
    }

    @discardableResult
    public func fetchReminders(
        matching _: NSPredicate,
        completion: @escaping ([EKReminder]?) -> Void) -> Any {
        let result = allReminders.filter { !$0.isCompleted }
        if deliverCompletionOffMain {
            // Test-only: deliver the completion from an off-main queue so
            // ReminderStoreTests can reproduce the framework's real off-main
            // delivery. SAFETY INVARIANT: `completion` is not `@Sendable`, so
            // `nonisolated(unsafe)` is the only way to hand it into a detached
            // task; this is sound because the completion only receives a freshly
            // built `result` array and never re-reads/mutates store state, and
            // the values are hoisted back to the main actor in the caller's hop.
            // REMOVAL PLAN: once `EventKitStoring.fetchReminders` takes a
            // `@Sendable` completion (or the real store is driven off-main in an
            // integration test), drop this branch and the init flag.
            nonisolated(unsafe) let delivery: () async -> Void = {
                completion(result)
            }
            Task.detached {
                await delivery()
            }
        } else {
            completion(result)
        }
        return ()
    }

    #if !os(watchOS)
        public func refreshSourcesIfNecessary() {}

        public func save(_ reminder: EKReminder, commit _: Bool) throws {
            allReminders.append(reminder)
        }

        public func remove(_ reminder: EKReminder, commit _: Bool) throws {
            allReminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
        }

        public func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule?) -> EKReminder {
            let reminder = EKReminder(eventStore: EKEventStore())
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = calendars.first
            return reminder
        }
    #endif

    // MARK: Private

    private let calendars: [EKCalendar]
    private let deliverCompletionOffMain: Bool
}
