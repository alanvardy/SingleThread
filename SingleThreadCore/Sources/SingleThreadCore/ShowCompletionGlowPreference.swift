import Foundation

/// Persists the user's "show completion glow" preference in UserDefaults.
///
/// Like `ShowDatePreference`, an absent key resolves to `true` (today's
/// always-on behavior) — `bool(forKey:)` would suppress the glow on first
/// launch. `nil` (missing key) therefore maps to `true`.
public struct ShowCompletionGlowPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showCompletionGlow") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether the completion glow is shown. `nil` (missing key) → `true`.
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
