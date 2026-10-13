import CoreGraphics

/// Which action a released row swipe should fire, if any.
public enum SwipeGestureOutcome: Equatable {
    case complete
    case skip
    case more
    case none
}

/// Pure direction/threshold rule for the reminder-card swipe. Extracted from the
/// row so the trigger distance is unit-testable without a gesture runtime.
public nonisolated enum SwipeGesture {
    /// Horizontal travel (pt) past which a release fires the action — roughly
    /// half the stock `.swipeActions` full-swipe distance it replaces.
    public static let releaseDistance: CGFloat = 72

    /// Upward travel (pt) past which a steep release opens the action menu.
    /// Longer than `releaseDistance` because a vertical drag is attached
    /// simultaneously with `List` scrolling/rubber-banding, so an incidental
    /// scroll must not trip it.
    public static let upReleaseDistance: CGFloat = 96

    /// Classifies a released drag translation. Horizontal-dominant drags map
    /// right → complete, left → skip. A steep upward drag (`dy` past
    /// `upThreshold` and more than twice the horizontal travel) → more.
    /// Downward and shallow vertical drags are ignored so `List` scrolling and
    /// pull-to-refresh win.
    public static func outcome(
        for translation: CGSize,
        threshold: CGFloat = releaseDistance,
        upThreshold: CGFloat = upReleaseDistance) -> SwipeGestureOutcome {
        let horizontal = translation.width
        let vertical = translation.height
        if vertical <= -upThreshold, abs(vertical) > 2 * abs(horizontal) {
            return .more
        }
        guard abs(vertical) <= abs(horizontal) else { return .none }
        if horizontal >= threshold {
            return .complete
        }
        if horizontal <= -threshold {
            return .skip
        }
        return .none
    }

    /// Which reveal direction a live drag offset maps to: right → complete,
    /// left → skip, a steep upward drag → more, zero → nothing.
    public static func revealedOutcome(forOffset offset: CGSize) -> SwipeGestureOutcome {
        let horizontal = offset.width
        let vertical = offset.height
        if vertical < 0, abs(vertical) > 2 * abs(horizontal) {
            return .more
        }
        if horizontal > 0 {
            return .complete
        }
        if horizontal < 0 {
            return .skip
        }
        return .none
    }
}
