import Foundation

/// Launch-argument seams driving app-level presentation for the UI tests and
/// the App Store screenshot harness. Production launches never pass these, so
/// each case defaults to shipping behaviour.
///
/// Deliberately app-target-only: `SingleThreadCore` stays presentation-free,
/// and every seam here exists to stage something the user's own taps normally
/// reach (see ``openSettings``).
enum LaunchArgument: String {
    /// Presents the root Settings sheet on first appearance.
    ///
    /// The sheet is otherwise reachable only from the gear button's action, and
    /// `simctl` has no tap command, so screenshot automation has no other way to
    /// capture the options screen. The view replays that action's exact order —
    /// bag first, then the flag — because `settingsSheetContent` renders nothing
    /// until the bag exists.
    case openSettings = "--ui-testing-open-settings"

    /// Presents the root Settings sheet and pushes the "Reminder" subscreen.
    ///
    /// The subscreen is otherwise reachable only by tapping the Reminder row,
    /// which `simctl` cannot do, so the App Store screenshot harness has no other
    /// route to it. It opens the sheet exactly as ``openSettings`` does — same
    /// bag-then-flag order — and then seeds the navigation path with the row's
    /// destination.
    case openSettingsReminder = "--ui-testing-open-settings-reminder"

    // MARK: Internal

    /// Whether either Settings seam is present — the sheet opener or the
    /// Reminder-subscreen opener (which opens the sheet too).
    static func opensSettings(
        in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        isPresent(.openSettings, in: arguments) || isPresent(.openSettingsReminder, in: arguments)
    }

    /// Whether `argument` was passed to this process.
    static func isPresent(
        _ argument: Self,
        in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(argument.rawValue)
    }
}
