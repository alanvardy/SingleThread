import Foundation

/// Persists the user's "show due date" preference in UserDefaults.
///
/// Unlike `SkippedReminderStore`, an absent key resolves to `true` (today's
/// behavior) rather than `false` — `bool(forKey:)` would hide dates on first
/// launch. `nil` (missing key) therefore maps to `true`.
public struct ShowDatePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store, `@AppStorage`, and sync payload.
    public static let defaultsKey = "showDate"

    /// Whether the due date is shown. `nil` (missing key) → `true`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
