import Foundation

/// Persists the excluded-list titles in UserDefaults.
public struct ExcludedListStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store and sync payload.
    public static let defaultsKey = "excludedListTitles"

    public func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func save(_ titles: [String]) {
        defaults.set(titles, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
