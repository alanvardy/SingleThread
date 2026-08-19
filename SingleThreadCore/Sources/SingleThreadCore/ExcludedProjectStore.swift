import Foundation

/// Persists the excluded-project titles in UserDefaults.
public struct ExcludedProjectStore {
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
