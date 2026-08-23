import Foundation

/// Persists the excluded-list titles in UserDefaults.
public struct ExcludedListStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedProjectTitles") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

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
