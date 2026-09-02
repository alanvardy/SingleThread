import Foundation
@testable import SingleThreadCore
import Testing

// MARK: - MinimumDisplayDuration

struct MinimumDisplayDurationTests {
    // MARK: Behavior

    @Test(arguments: [
        (0.0, 1.0),
        (0.4, 0.6),
        (1.0, 0.0),
        (1.5, 0.0)
    ])
    func remainingSleepScalesWithElapsed(_ spec: (elapsed: TimeInterval, remaining: TimeInterval)) {
        let remaining = MinimumDisplayDuration.remainingSleep(elapsed: spec.elapsed, minimum: 1)
        #expect(
            abs(remaining - spec.remaining) < 0.000_001,
            "elapsed \(spec.elapsed) s → \(spec.remaining) s remaining")
    }
}
