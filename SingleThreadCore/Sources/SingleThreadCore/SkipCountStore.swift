import Foundation

/// Pure logic for the skip-count nudge threshold. No EventKit/UI dependencies.
public nonisolated enum SkipCountLogic {
    /// Default threshold: nudged once skipped more than five times (count ≥ 6).
    public static let defaultThreshold = 6

    /// True when `count` has reached the nudge threshold (count ≥ 6 by default,
    /// i.e. "skipped more than five times").
    public static func shouldNudge(_ count: Int, threshold: Int = defaultThreshold) -> Bool {
        count >= threshold
    }

    /// True when incrementing from `old` to `new` first crosses the threshold.
    /// Fires once on the first crossing so the nudge never re-fires on every
    /// subsequent skip — the count must reset (or be pruned) to re-cross.
    public static func crossedThreshold(from old: Int, to new: Int, threshold: Int = defaultThreshold) -> Bool {
        old < threshold && new >= threshold
    }
}

/// Persists the per-reminder skip counts (`identifier → count`) in UserDefaults.
public struct SkipCountStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store and sync payload.
    public static let defaultsKey = "skipCounts"

    public func load() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    public func save(_ counts: [String: Int]) {
        defaults.set(counts, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
