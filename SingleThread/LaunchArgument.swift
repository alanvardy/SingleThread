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

    // MARK: Internal

    /// Whether `argument` was passed to this process.
    static func isPresent(
        _ argument: Self,
        in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(argument.rawValue)
    }
}
