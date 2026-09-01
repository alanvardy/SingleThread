import Foundation

// MARK: - SharedStrings

/// Typed accessors for the shared string catalog (`Localizable.xcstrings`) in
/// this package, so app/watch/widget callers don't repeat the `table:` /
/// `bundle:` arguments and can't drift onto a different catalog.
///
/// Keys shared across ≥2 targets live here — never duplicated in a target's
/// own catalog.
public enum SharedStrings {
    public static var completeAction: String {
        String(localized: "Complete", table: "Localizable", bundle: .module)
    }

    public static var skipAction: String {
        String(localized: "Skip", table: "Localizable", bundle: .module)
    }

    public static var deleteAction: String {
        String(localized: "Delete", table: "Localizable", bundle: .module)
    }

    public static var completeReminderAccessibility: String {
        String(localized: "Complete reminder", table: "Localizable", bundle: .module)
    }

    public static var skipReminderAccessibility: String {
        String(localized: "Skip reminder", table: "Localizable", bundle: .module)
    }

    public static var deleteReminderAccessibility: String {
        String(localized: "Delete reminder", table: "Localizable", bundle: .module)
    }

    public static var completionGlow: String {
        String(localized: "Completion glow", table: "Localizable", bundle: .module)
    }

    public static var allDone: String {
        String(localized: "All Done", table: "Localizable", bundle: .module)
    }

    public static var noReminders: String {
        String(localized: "No Reminders", table: "Localizable", bundle: .module)
    }

    public static var repeats: String {
        String(localized: "Repeats", table: "Localizable", bundle: .module)
    }

    public static var alert: String {
        String(localized: "Alert", table: "Localizable", bundle: .module)
    }

    public static var remindersAccess: String {
        String(localized: "Reminders Access", table: "Localizable", bundle: .module)
    }

    public static var requestingAccess: String {
        String(localized: "Requesting access…", table: "Localizable", bundle: .module)
    }

    public static var nothingDueRightNow: String {
        String(localized: "Nothing due right now", table: "Localizable", bundle: .module)
    }

    public static var noRemindersYet: String {
        String(localized: "No reminders yet", table: "Localizable", bundle: .module)
    }

    public static func priorityAccessibilityLabel(_ levelName: String) -> String {
        String(localized: "\(levelName) priority", table: "Localizable", bundle: .module)
    }
}