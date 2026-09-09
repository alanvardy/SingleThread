import Foundation

/// Tracks today's completion count in App Group UserDefaults, resetting at
/// midnight (device-local `Calendar.current`). A lazy day-rollover on
/// `increment()` compares the stored start-of-day marker against today's
/// start-of-day — if they differ, the count resets to 1 and the marker is
/// updated. Day boundaries follow `ReminderDateFilter` semantics: device-local
/// only, no UTC, no timezone-agnostic tracking.
///
/// Production writes stay within `0...100` because `increment()` runs only
/// while `canMutate` is true (count < 100), `decrement()` clamps at 0, and
/// `resetForTesting()` writes 0. The `--seed` UI-test seam is the deliberate
/// exception — it writes `completionTodayCount` verbatim, unclamped.
public struct DailyCompletionStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        markerKey: String = Self.defaultsMarkerKey,
        countKey: String = Self.defaultsCountKey) {
        self.defaults = defaults
        self.markerKey = markerKey
        self.countKey = countKey
    }

    // MARK: Public

    /// Key for the start-of-day `TimeInterval` marker.
    public static let defaultsMarkerKey = "completionDayMarker"

    /// Key for today's completion count.
    public static let defaultsCountKey = "completionTodayCount"

    /// Today's completion count. Reads `UserDefaults.integer(forKey:)`,
    /// which returns 0 when the key is absent.
    public var todayCount: Int {
        defaults.integer(forKey: countKey)
    }

    /// The stored start-of-day `TimeInterval`. Returns 0 when absent.
    public var dayMarker: TimeInterval {
        defaults.double(forKey: markerKey)
    }

    /// Increments today's count by 1. On first call (or after midnight),
    /// resets the count to 1 and writes the new start-of-day marker.
    /// Otherwise increments normally.
    public func increment() {
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        if dayMarker != todayStart {
            defaults.set(1, forKey: countKey)
            defaults.set(todayStart, forKey: markerKey)
        } else {
            defaults.set(todayCount + 1, forKey: countKey)
        }
    }

    /// Decrements today's count by 1, clamping at zero.
    public func decrement() {
        let current = todayCount
        defaults.set(max(0, current - 1), forKey: countKey)
    }

    /// Resets both keys to 0. Test-only; not called in production.
    public func resetForTesting() {
        defaults.set(0, forKey: countKey)
        defaults.set(0, forKey: markerKey)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let markerKey: String
    private let countKey: String
}
