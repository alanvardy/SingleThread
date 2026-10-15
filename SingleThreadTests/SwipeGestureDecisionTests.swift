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
    func downwardDragNeverOpensMore() {
        // Downward travel belongs to the pull-to-refresh surface; the card's
        // swipe must never misread it as the up-rail's `.more`.
        #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: 130)) == .none)
        #expect(SwipeGesture.outcome(for: CGSize(width: 60, height: 100)) == .none)
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

    @Test
    func upPastThresholdOpensMore() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -100)) == .more)
    }

    @Test
    func upBelowThresholdDoesNothing() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -80)) == .none)
    }

    @Test
    func shallowUpIsIgnored() {
        // Past the up threshold but not steep enough (|dy| <= 2·|dx|) — a scroll,
        // not a command.
        #expect(SwipeGesture.outcome(for: CGSize(width: 60, height: -100)) == .none)
    }

    @Test
    func upExactlyAtThresholdFires() {
        #expect(SwipeGesture.outcome(for: CGSize(width: 0, height: -96)) == .more)
    }

    @Test
    func positiveDragOffsetRevealsComplete() {
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 12, height: 0)) == .complete)
    }

    @Test
    func negativeDragOffsetRevealsSkip() {
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: -12, height: 0)) == .skip)
    }

    @Test
    func upwardDragOffsetRevealsMore() {
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 0, height: -60)) == .more)
    }

    /// A downward offset reveals nothing on the card — the pull-to-refresh
    /// surface owns it, so the card must not advertise a competing action.
    @Test
    func downwardDragOffsetRevealsNothing() {
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 0, height: 60)) == .none)
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 60, height: 100)) == .none)
    }

    @Test
    func shallowUpRevealsNothing() {
        // A vertical-dominant drag that is not steep enough to fire `.more` on
        // release must not preview a horizontal action either; the reveal and
        // the release outcome must agree.
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: 60, height: -100)) == .none)
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize(width: -60, height: -100)) == .none)
    }

    @Test
    func zeroDragOffsetRevealsNothing() {
        #expect(SwipeGesture.revealedOutcome(forOffset: CGSize.zero) == .none)
    }

    // MARK: On-rails axis lock

    @Test
    func horizontalDominantDragLocksHorizontal() {
        #expect(SwipeGesture.axis(for: CGSize(width: 40, height: 3)) == .horizontal)
        #expect(SwipeGesture.axis(for: CGSize(width: -40, height: 3)) == .horizontal)
    }

    @Test
    func verticalDominantDragLocksVertical() {
        #expect(SwipeGesture.axis(for: CGSize(width: 3, height: -40)) == .vertical)
        #expect(SwipeGesture.axis(for: CGSize(width: 3, height: 40)) == .vertical)
    }

    @Test
    func diagonalTieLocksHorizontal() {
        #expect(SwipeGesture.axis(for: CGSize(width: 40, height: -40)) == .horizontal)
    }

    @Test
    func zeroTranslationLocksHorizontal() {
        #expect(SwipeGesture.axis(for: .zero) == .horizontal)
    }

    @Test
    func horizontalRailZeroesVerticalTravel() {
        #expect(SwipeGesture.railed(CGSize(width: 60, height: -90), on: .horizontal)
            == CGSize(width: 60, height: 0))
    }

    @Test
    func verticalRailZeroesHorizontalTravel() {
        #expect(SwipeGesture.railed(CGSize(width: 60, height: -90), on: .vertical)
            == CGSize(width: 0, height: -90))
    }

    /// A diagonal drag that would be `none` raw must resolve cleanly once railed
    /// onto its dominant axis — the release rule sees a single-axis translation.
    @Test
    func railedDiagonalResolvesOnItsDominantAxis() {
        let rightward = CGSize(width: 100, height: -30)
        #expect(SwipeGesture.outcome(for: SwipeGesture.railed(rightward, on: .horizontal)) == .complete)

        let upward = CGSize(width: 30, height: -100)
        #expect(SwipeGesture.outcome(for: SwipeGesture.railed(upward, on: .vertical)) == .more)
    }
}
