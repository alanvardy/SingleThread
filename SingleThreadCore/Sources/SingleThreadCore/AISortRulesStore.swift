import Foundation

/// Persists the user's freeform AI-sort rules in the App Group, mirroring
/// ``SortOptionStore``. The text is opaque: it is handed to the ranking
/// implementation as-is and never parsed here.
public struct AISortRulesStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = Self.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key, also wiped by `UITestingSeed.resetPersistedState`.
    public static let defaultsKey = "aiSortRules"

    /// The stored rules, or `""` when nothing has been saved yet.
    public func load() -> String {
        defaults.string(forKey: key) ?? ""
    }

    public func save(_ rules: String) {
        defaults.set(rules, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
