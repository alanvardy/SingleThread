import Foundation

/// Tracks the lifetime completion count in App Group UserDefaults.
///
/// The counter starts at 0 and increments by exactly 1 per successful EventKit
/// save inside `ReminderStore.completeReminder`. It is never decremented or
/// reset in production. Tests inject UUID-keyed stores for isolation.
public struct CompletionCounterStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "completionCount") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// The current completion count. Reads `UserDefaults.integer(forKey:)`,
    /// which returns 0 when the key is absent — safe, 0-defaulted.
    public var count: Int {
        defaults.integer(forKey: key)
    }

    /// Increments the counter by 1.
    public func increment() {
        defaults.set(count + 1, forKey: key)
    }

    /// Resets the counter to 0. Test-only; not called in production.
    public func resetForTesting() {
        defaults.set(0, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
