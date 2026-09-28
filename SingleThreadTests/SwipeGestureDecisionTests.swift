import SingleThreadCore
import SwiftUI
import Testing

/// Threshold/direction/dominance rule for the reminder-card swipe. Pure logic,
/// so it is pinned independently of any live gesture runtime.
struct SwipeGestureDecisionTests {
    @Test
    func rightPastThresholdCompletes() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 80, height: 0)) == .complete)
    }

    @Test
    func leftPastThresholdSkips() {
        #expect(SwipeGesture.outcome(for: CGSize(width: -80, height: 0)) == .skip)
    }

    @Test
    func underThresholdDoesNothing() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 40, height: 0)) == .none)
        #expect(SwipeGesture.outcome(for: CGSize(width: -40, height: 0)) == .none)
    }

    @Test
    func verticalDominantDragDoesNothing() {
        // Little horizontal travel, lots of vertical: a scroll, not a swipe.
        #expect(SwipeGesture.outcome(for: CGSize(width: 100, height: 130)) == .none)
        #expect(SwipeGesture.outcome(for: CGSize(width: -100, height: -130)) == .none)
    }

    @Test
    func horizontalEqualToVerticalIsNotVerticalDominant() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 100, height: 100)) == .complete)
    }

    @Test
    func exactlyAtThresholdFires() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 72, height: 0)) == .complete)
        #expect(SwipeGesture.outcome(for: CGSize(width: -72, height: 0)) == .skip)
    }

    @Test
    func customThresholdOverrideIsHonoured() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 30, height: 0), threshold: 20) == .complete)
        #expect(SwipeGesture.outcome(for: CGSize(width: 30, height: 0), threshold: 50) == .none)
    }
}
