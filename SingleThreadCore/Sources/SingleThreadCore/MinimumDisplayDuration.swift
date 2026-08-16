import Foundation

/// Computes how long a transient indicator must stay on screen to meet a
/// minimum display duration (e.g. keeping a refresh spinner visible long
/// enough for the user to notice, even when the underlying work is instant).
public nonisolated enum MinimumDisplayDuration {
    /// Returns the remaining time (in seconds) to wait so that a UI element
    /// shown for `elapsed` seconds stays visible for at least `minimum`
    /// seconds. Returns `0` once the minimum has already been met.
    public static func remainingSleep(elapsed: TimeInterval, minimum: TimeInterval) -> TimeInterval {
        max(0, minimum - elapsed)
    }
}
