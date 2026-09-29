import CoreGraphics

/// Which action a released row swipe should fire, if any.
public enum SwipeGestureOutcome: Equatable {
    case complete
    case skip
    case none
}

/// Pure direction/threshold rule for the reminder-card swipe. Extracted from the
/// row so the trigger distance is unit-testable without a gesture runtime.
public nonisolated enum SwipeGesture {
    /// Horizontal travel (pt) past which a release fires the action — roughly
    /// half the stock `.swipeActions` full-swipe distance it replaces.
    public static let releaseDistance: CGFloat = 72

    /// Classifies a released drag translation. A vertical-dominant drag
    /// (`|dy| > |dx|`) is ignored so `List` scrolling/pull-to-refresh win.
    public static func outcome(
        for translation: CGSize,
        threshold: CGFloat = releaseDistance) -> SwipeGestureOutcome {
        guard abs(translation.height) <= abs(translation.width) else { return .none }
        if translation.width >= threshold {
            return .complete
        }
        if translation.width <= -threshold {
            return .skip
        }
        return .none
    }

    /// Which reveal direction a live drag offset maps to: positive (right) →
    /// complete, negative (left) → skip, zero → nothing.
    public static func revealedOutcome(forOffset offset: CGFloat) -> SwipeGestureOutcome {
        if offset > 0 {
            return .complete
        }
        if offset < 0 {
            return .skip
        }
        return .none
    }
}
