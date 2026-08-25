import Foundation

/// Persists the user's "show alarms" preference in UserDefaults.
///
/// An absent key resolves to `true`: the feature defaults to showing alarm
/// indicators. `nil` (missing key) maps to `true` rather than
/// `bool(forKey:)`'s `false`.
public struct ShowAlarmsPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showAlarms") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether alarm indicators are shown. `nil` (missing key) → `true`.
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
