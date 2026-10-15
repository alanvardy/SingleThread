import CoreGraphics
@testable import SingleThread
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
}
