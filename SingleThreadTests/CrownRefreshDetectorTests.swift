@testable import SingleThreadCore
import Testing

// MARK: - CrownRefreshDetector

struct CrownRefreshDetectorTests {
    // MARK: Behavior

    @Test
    func settleReturnsFalseWhenBelowThreshold() {
        var detector = CrownRefreshDetector(threshold: 0.5)
        detector.record(offset: 0.2)
        detector.record(offset: 0.2)
        let shouldRefresh = detector.settle()
        #expect(!shouldRefresh)
    }

    @Test
    func settleReturnsTrueWhenAtThreshold() {
        var detector = CrownRefreshDetector(threshold: 0.5)
        detector.record(offset: 0.3)
        detector.record(offset: 0.2)
        let shouldRefresh = detector.settle()
        #expect(shouldRefresh)
    }

    @Test
    func settleReturnsTrueWhenAboveThreshold() {
        var detector = CrownRefreshDetector(threshold: 0.5)
        detector.record(offset: 0.9)
        let shouldRefresh = detector.settle()
        #expect(shouldRefresh)
    }

    @Test
    func accumulatorResetsAfterSettle() {
        var detector = CrownRefreshDetector(threshold: 0.5)
        detector.record(offset: 0.6)
        let first = detector.settle()
        #expect(first)
        #expect(detector.accumulatedRotation == 0)
        let second = detector.settle()
        #expect(!second)
    }

    @Test
    func negativeOffsetsAreTreatedAsPositive() {
        var detector = CrownRefreshDetector(threshold: 0.5)
        detector.record(offset: -0.3)
        detector.record(offset: -0.2)
        let shouldRefresh = detector.settle()
        #expect(shouldRefresh)
    }

    @Test
    func defaultThreshold() {
        var detector = CrownRefreshDetector()
        let first = detector.settle()
        #expect(!first)
        detector.record(offset: 0.5)
        let second = detector.settle()
        #expect(second)
    }
}
