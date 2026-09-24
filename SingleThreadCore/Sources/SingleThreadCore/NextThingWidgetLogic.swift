import EventKit
import Foundation

/// The four widget display preferences, resolved once from `UserDefaults`.
/// Extracted from `NextThingProvider.makeEntry` so the per-key fallbacks are
/// unit-testable without standing up a widget/app-extension test target.
public struct NextThingDisplayPreferences: Equatable, Sendable {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults) {
        showsDate = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showDate.rawValue,
            fallback: true).isEnabled
        showsList = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showList.rawValue,
            fallback: false).isEnabled
        showsRecurrence = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showRecurrence.rawValue,
            fallback: true).isEnabled
        showsAlarms = BoolPreferenceStore(
            defaults: defaults,
            key: BoolPreferenceKey.showAlarms.rawValue,
            fallback: true).isEnabled
    }

    // MARK: Public

    public let showsDate: Bool
    public let showsList: Bool
    public let showsRecurrence: Bool
    public let showsAlarms: Bool
}

/// Pure widget logic extracted from `NextThingProvider`; the SwiftUI
/// `NextThingWidgetView` stays untested (no app-extension test target).
public enum NextThingWidgetLogic {
    /// How soon to re-ask EventKit for a possibly-changed current reminder.
    /// Was 15 min; shortened so an out-of-band completion/deletion clears the
    /// widget sooner. This is the widget's entire staleness mechanism.
    public static let refreshInterval: TimeInterval = 5 * 60

    /// The timeline's next refresh date — the one piece of date math the widget owns.
    public static func nextRefreshDate(from date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }

    /// Reminders access is only usable at `.fullAccess`; anything else renders
    /// the widget's `.noAccess` state.
    public static func isAccessGranted(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }
}
