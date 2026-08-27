import Foundation

/// Persists the user's "show guide" preference in UserDefaults.
///
/// An absent key resolves to `true` (first-launch semantic) —
/// `bool(forKey:)` would suppress the guide on first launch.
/// `nil` (missing key) therefore maps to `true`.
public struct ShowGuidePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showGuide") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether the guide should be shown. `nil` (missing key) → `true`.
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
