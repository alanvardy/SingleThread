import Foundation

// MARK: - BackgroundFade

/// User-selectable background photo fade, expressed as a percentage of full
/// opacity. Persisted in `UserDefaults` via `@AppStorage` as an `Int` percent
/// so the settings picker can offer fixed 10% increments.
enum BackgroundFade {
    // MARK: Internal

    /// Percentage selected before the user changes anything.
    static let defaultValue = 50

    /// Step between selectable percentages.
    static let step = 10

    /// Every selectable percentage, ascending.
    static let allValues = Array(stride(from: Self.minValue, through: Self.maxValue, by: step))

    /// Converts a stored percentage into the SwiftUI `opacity` fraction,
    /// clamping out-of-range persisted values so a corrupt default can't
    /// produce an invalid opacity.
    static func opacity(for percent: Int) -> Double {
        Double(percent.clamped(to: minValue ... maxValue)) / 100
    }

    // MARK: Private

    private static let minValue = 0
    private static let maxValue = 100
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
