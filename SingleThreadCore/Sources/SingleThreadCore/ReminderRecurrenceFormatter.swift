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
            return interval > 1
                ? String(localized: "Every \(interval) days", table: "Localizable", bundle: .module)
                : String(localized: "Daily", table: "Localizable", bundle: .module)
        case .weekly:
            return interval > 1
                ? String(localized: "Every \(interval) weeks", table: "Localizable", bundle: .module)
                : String(localized: "Weekly", table: "Localizable", bundle: .module)
        case .monthly:
            return interval > 1
                ? String(localized: "Every \(interval) months", table: "Localizable", bundle: .module)
                : String(localized: "Monthly", table: "Localizable", bundle: .module)
        case .yearly:
            return interval > 1
                ? String(localized: "Every \(interval) years", table: "Localizable", bundle: .module)
                : String(localized: "Yearly", table: "Localizable", bundle: .module)
        @unknown default:
            return nil
        }
    }
}
