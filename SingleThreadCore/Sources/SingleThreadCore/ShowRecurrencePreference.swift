import Foundation

/// Persists the user's "show recurrence" preference in UserDefaults.
///
/// Unlike `ShowListPreference`, an absent key resolves to `true`: the feature
/// defaults to showing recurrence indicators. `nil` (missing key) maps to
/// `true` rather than `bool(forKey:)`'s `false`.
public struct ShowRecurrencePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showRecurrence") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether recurrence indicators are shown. `nil` (missing key) → `true`.
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
