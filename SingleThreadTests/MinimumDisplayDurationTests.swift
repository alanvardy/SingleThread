@testable import SingleThreadCore
import Testing

// MARK: - MinimumDisplayDuration

struct MinimumDisplayDurationTests {
    // MARK: Behavior

    @Test
    func returnsFullMinimumWhenNothingElapsed() {
        let remaining = MinimumDisplayDuration.remainingSleep(elapsed: 0, minimum: 1)
        #expect(remaining == 1)
    }

    @Test
    func returnsRemainderWhenPartiallyElapsed() {
        let remaining = MinimumDisplayDuration.remainingSleep(elapsed: 0.4, minimum: 1)
        #expect(abs(remaining - 0.6) < 0.000_001)
    }

    @Test
    func returnsZeroWhenMinimumMet() {
        let remaining = MinimumDisplayDuration.remainingSleep(elapsed: 1, minimum: 1)
        #expect(remaining == 0)
    }

    @Test
    func returnsZeroWhenExceedingMinimum() {
        let remaining = MinimumDisplayDuration.remainingSleep(elapsed: 1.5, minimum: 1)
        #expect(remaining == 0)
    }
}
