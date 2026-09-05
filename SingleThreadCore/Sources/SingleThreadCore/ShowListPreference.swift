import Foundation

/// Persists the user's "show list" preference in UserDefaults (shared with the
/// widget via the App Group).
///
/// Unlike `ShowDatePreference`, an absent key resolves to `false`: the feature
/// is new, so missing state must preserve today's card look (no list name).
public struct ShowListPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store, `@AppStorage`, and sync payload.
    public static let defaultsKey = "showList"

    /// Whether the list name is shown. `nil` (missing key) → `false`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
