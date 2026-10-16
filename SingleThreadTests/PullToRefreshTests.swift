import CoreGraphics
@testable import SingleThread
import SingleThreadCore
import Testing

/// Pure arming and intensity rule for the hand-rolled pull-to-refresh that
/// replaced `.refreshable` on the reminder list (the stock control never arms
/// on a single full-height row). `@MainActor` because the app target defaults
/// to main-actor isolation.
@MainActor
struct PullToRefreshTests {
    @Test
    func pullBelowThresholdIsNotArmed() {
        #expect(!PullToRefresh.isArmed(pull: 80))
    }

    @Test
    func pullAtThresholdIsArmed() {
        #expect(PullToRefresh.isArmed(pull: 96))
    }

    @Test
    func pullPastThresholdIsArmed() {
        #expect(PullToRefresh.isArmed(pull: 160))
    }

    /// An upward drag (negative `dy`) must never arm the refresh.
    @Test
    func upwardDragIsNeverArmed() {
        #expect(!PullToRefresh.isArmed(pull: -100))
    }

    @Test
    func customThresholdOverrideIsHonoured() {
        #expect(PullToRefresh.isArmed(pull: 30, threshold: 20))
        #expect(!PullToRefresh.isArmed(pull: 30, threshold: 50))
    }

    @Test
    func progressIsClampedToUnitRange() {
        #expect(PullToRefresh.progress(pull: -40) == 0)
        #expect(PullToRefresh.progress(pull: 0) == 0)
        #expect(PullToRefresh.progress(pull: 48) == 0.5)
        #expect(PullToRefresh.progress(pull: 96) == 1)
        #expect(PullToRefresh.progress(pull: 500) == 1)
    }

    /// Sad path: a zero threshold must not divide by zero.
    @Test
    func zeroThresholdDoesNotDivideByZero() {
        #expect(PullToRefresh.progress(pull: 10, threshold: 0) == 1)
    }

    @Test
    func verticalRailReportsDownwardTravel() {
        #expect(PullToRefresh.pull(for: CGSize(width: 0, height: 140), on: .vertical) == 140)
    }

    /// An upward drag under the vertical rail must never report a pull.
    @Test
    func verticalRailIgnoresUpwardTravel() {
        #expect(PullToRefresh.pull(for: CGSize(width: 0, height: -140), on: .vertical) == 0)
    }

    /// The reported symptom: a left/right swipe with some downward drift must
    /// contribute no vertical travel, or the card drifts up/down mid-swipe.
    @Test
    func horizontalRailReportsNoPull() {
        #expect(PullToRefresh.pull(for: CGSize(width: 160, height: 80), on: .horizontal) == 0)
        #expect(PullToRefresh.pull(for: CGSize(width: -160, height: 80), on: .horizontal) == 0)
        #expect(PullToRefresh.pull(for: CGSize(width: 160, height: 300), on: .horizontal) == 0)
    }
}
