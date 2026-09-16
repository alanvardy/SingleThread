import Foundation

// MARK: - SharedStrings

/// Typed accessors for the shared string catalog (`Localizable.xcstrings`) in
/// this package, so app/watch/widget callers don't repeat the `table:` /
/// `bundle:` arguments and can't drift onto a different catalog.
///
/// Keys shared across ≥2 targets live here — never duplicated in a target's
/// own catalog.
public enum SharedStrings {
    /// Note: "Medium" intentionally stays in two catalogs — App (font-size
    /// picker, es "Mediano") and Core (priority level, es "Media") — same
    /// English word, different UI contexts and translations. Not deduplicated.
    public static var completeAction: LocalizedStringResource {
        LocalizedStringResource("Complete", table: "Localizable", bundle: .module)
    }

    // periphery:ignore
    /// "Complete Reminder" (title case) — used by macOS command menus and menu bar.
    public static var completeReminder: LocalizedStringResource {
        LocalizedStringResource("Complete Reminder", table: "Localizable", bundle: .module)
    }

    /// "Reminder" — used by confirmation dialogs, navigation titles, and macOS command menus.
    public static var reminder: LocalizedStringResource {
        LocalizedStringResource("Reminder", table: "Localizable", bundle: .module)
    }

    public static var skipAction: LocalizedStringResource {
        LocalizedStringResource("Skip", table: "Localizable", bundle: .module)
    }

    // periphery:ignore
    /// "Skip Reminder" (title case) — used by macOS command menus and menu bar.
    public static var skipReminder: LocalizedStringResource {
        LocalizedStringResource("Skip Reminder", table: "Localizable", bundle: .module)
    }

    public static var deleteAction: LocalizedStringResource {
        LocalizedStringResource("Delete", table: "Localizable", bundle: .module)
    }

    /// Nudge banner title: a reminder has been skipped more than five times.
    public static var skipNudgeTitle: LocalizedStringResource {
        LocalizedStringResource("Skipped 6 times", table: "Localizable", bundle: .module)
    }

    public static var completeReminderAccessibility: LocalizedStringResource {
        LocalizedStringResource("Complete reminder", table: "Localizable", bundle: .module)
    }

    public static var skipReminderAccessibility: LocalizedStringResource {
        LocalizedStringResource("Skip reminder", table: "Localizable", bundle: .module)
    }

    public static var deleteReminderAccessibility: LocalizedStringResource {
        LocalizedStringResource("Delete reminder", table: "Localizable", bundle: .module)
    }

    public static var completionGlow: LocalizedStringResource {
        LocalizedStringResource("Completion glow", table: "Localizable", bundle: .module)
    }

    public static var allDone: LocalizedStringResource {
        LocalizedStringResource("All Done", table: "Localizable", bundle: .module)
    }

    public static var noReminders: LocalizedStringResource {
        LocalizedStringResource("No Reminders", table: "Localizable", bundle: .module)
    }

    public static var repeats: LocalizedStringResource {
        LocalizedStringResource("Repeats", table: "Localizable", bundle: .module)
    }

    public static var alert: LocalizedStringResource {
        LocalizedStringResource("Alert", table: "Localizable", bundle: .module)
    }

    public static var remindersAccess: LocalizedStringResource {
        LocalizedStringResource("Reminders Access", table: "Localizable", bundle: .module)
    }

    public static var requestingAccess: LocalizedStringResource {
        LocalizedStringResource("Requesting access…", table: "Localizable", bundle: .module)
    }

    public static var nothingDueRightNow: LocalizedStringResource {
        LocalizedStringResource("Nothing due right now", table: "Localizable", bundle: .module)
    }

    public static var noRemindersYet: LocalizedStringResource {
        LocalizedStringResource("No reminders yet", table: "Localizable", bundle: .module)
    }

    public static func priorityAccessibilityLabel(_ levelName: LocalizedStringResource) -> LocalizedStringResource {
        LocalizedStringResource("\(levelName) priority", table: "Localizable", bundle: .module)
    }
}

// MARK: - Explicit-locale resolution

public extension LocalizedStringResource {
    /// Resolves this resource against an explicit locale. Views get this for
    /// free from `\.locale`; non-View callers use this or
    /// `resolvedInAppLanguage()`.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }

    /// Resolves against the persisted app-language preference.
    func resolvedInAppLanguage() -> String {
        resolved(in: AppLocaleState.storedEffectiveLocale)
    }
}
