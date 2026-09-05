import Foundation

/// Persists the user's "show undated reminders" preference, mirroring
/// `SortOptionStore`. An absent key resolves to `false` (today's behavior —
/// undated reminders start hidden).
public struct ShowUndatedRemindersPreference {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store, `@AppStorage`, and sync payload.
    public static let defaultsKey = "showUndatedReminders"

    public func load() -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    public func save(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
