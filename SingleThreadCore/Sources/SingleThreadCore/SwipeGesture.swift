import CoreGraphics

/// The single rail a live drag locks to once it starts moving. "On rails":
/// the card travels along one axis only, never diagonally.
public enum SwipeAxis: Equatable {
    case horizontal
    case vertical
}

/// Which action a released row swipe should fire, if any.
public enum SwipeGestureOutcome: Equatable {
    case complete
    case skip
    case more
    case refresh
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

    /// Downward travel (pt) past which a steep pull-down release refreshes.
    /// Matches `upReleaseDistance` for the same reason: the drag is attached
    /// simultaneously with `List` rubber-banding, so an incidental bounce must
    /// not trip it.
    public static let downReleaseDistance: CGFloat = 96

    /// Classifies a released drag translation. Horizontal-dominant drags map
    /// right → complete, left → skip. A steep upward drag (`dy` past
    /// `upThreshold` and more than twice the horizontal travel) → more; a steep
    /// downward drag past `downThreshold` → refresh. Shallow vertical drags are
    /// ignored so a diagonal `List` bounce neither swipes nor refreshes.
    public static func outcome(
        for translation: CGSize,
        threshold: CGFloat = releaseDistance,
        upThreshold: CGFloat = upReleaseDistance,
        downThreshold: CGFloat = downReleaseDistance) -> SwipeGestureOutcome {
        let horizontal = translation.width
        let vertical = translation.height
        if vertical <= -upThreshold, abs(vertical) > 2 * abs(horizontal) {
            return .more
        }
        if vertical >= downThreshold, abs(vertical) > 2 * abs(horizontal) {
            return .refresh
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
    /// left → skip, a steep upward drag → more, a steep downward drag →
    /// refresh. Non-steep vertical-dominant drags and zero reveal nothing,
    /// mirroring `outcome(for:)` so the preview cannot advertise an action the
    /// release would discard.
    public static func revealedOutcome(forOffset offset: CGSize) -> SwipeGestureOutcome {
        let horizontal = offset.width
        let vertical = offset.height
        if vertical < 0, abs(vertical) > 2 * abs(horizontal) {
            return .more
        }
        if vertical > 0, abs(vertical) > 2 * abs(horizontal) {
            return .refresh
        }
        guard abs(vertical) <= abs(horizontal) else { return .none }
        if horizontal > 0 {
            return .complete
        }
        if horizontal < 0 {
            return .skip
        }
        return .none
    }

    /// Locks a started drag to one rail. Whichever component leads decides the
    /// axis; a tie goes horizontal, mirroring `outcome(for:)`'s "vertical
    /// dominant" guard so a symmetric drag still resolves to a swipe rather
    /// than a scroll. Called once per gesture — the caller persists the result
    /// so the rail cannot flip mid-drag.
    public static func axis(for translation: CGSize) -> SwipeAxis {
        abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
    }

    /// Projects `translation` onto `axis`, zeroing the other component so the
    /// card can never travel diagonally.
    public static func railed(_ translation: CGSize, on axis: SwipeAxis) -> CGSize {
        switch axis {
        case .horizontal: CGSize(width: translation.width, height: 0)
        case .vertical: CGSize(width: 0, height: translation.height)
        }
    }
}
