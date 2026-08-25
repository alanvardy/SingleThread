import EventKit
import Foundation

/// Produces short human-readable recurrence summaries (e.g. "Daily",
/// "Every 2 weeks") from an `EKRecurrenceRule` array.
///
/// Only the **first** rule's frequency + interval is formatted. Rules that
/// have no recognizable frequency return `nil`. Empty/nil input also returns
/// `nil`.
public nonisolated enum ReminderRecurrenceFormatter {
    public static func format(_ rules: [EKRecurrenceRule]?) -> String? {
        guard let first = rules?.first else { return nil }
        let interval = first.interval
        switch first.frequency {
        case .daily:
            return interval > 1 ? "Every \(interval) days" : "Daily"
        case .weekly:
            return interval > 1 ? "Every \(interval) weeks" : "Weekly"
        case .monthly:
            return interval > 1 ? "Every \(interval) months" : "Monthly"
        case .yearly:
            return interval > 1 ? "Every \(interval) years" : "Yearly"
        @unknown default:
            return nil
        }
    }
}
