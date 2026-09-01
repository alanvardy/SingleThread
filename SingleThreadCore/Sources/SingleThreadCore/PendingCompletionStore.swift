import Foundation

/// Persists pending-completion reminder identifiers in UserDefaults. The watch
/// records a completed identifier here until the phone processes the relay and
/// the reminder stops appearing in incomplete fetches; `reload()` prunes it.
public struct PendingCompletionStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "pendingCompletionIdentifiers") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Replaces the stored set — never unions. This invariant (a clear prunes
    /// stale IDs) is what lets `reload()` drain the set when the phone
    /// processes a relay.
    public func save(_ identifiers: Set<String>) {
        defaults.set(Array(identifiers), forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
