import Foundation

/// Decides whether Digital Crown rotation warrants a refresh.
///
/// `digitalCrownRotation(onChange:onIdle:)` reports incremental crown
/// movement through `DigitalCrownEvent.offset` as the crown turns, then
/// fires `onIdle` once it settles. Feed each `offset` into `record(offset:)`
/// and, on settle, call `settle()` — it returns `true` (and resets) only
/// when the total accumulated rotation crosses the threshold, so accidental
/// nudges don't trigger a refresh.
public struct CrownRefreshDetector {
    // MARK: Lifecycle

    /// - Parameter threshold: minimum total |offset| needed to trigger a refresh.
    public init(threshold: Double = 0.5) {
        self.threshold = threshold
    }

    // MARK: Public

    /// Records an incremental crown offset. Sign is ignored via `abs`.
    public mutating func record(offset: Double) {
        accumulatedRotation += abs(offset)
    }

    /// Called when the crown settles. Returns `true` if the accumulated
    /// rotation warrants a refresh; resets the accumulator either way.
    public mutating func settle() -> Bool {
        let shouldRefresh = accumulatedRotation >= threshold
        accumulatedRotation = 0
        return shouldRefresh
    }

    // MARK: Internal

    /// Exposed for testing.
    private(set) var accumulatedRotation: Double = 0

    // MARK: Private

    private let threshold: Double
}
