import Foundation

/// Tracks the lifetime completion count in App Group UserDefaults.
///
/// The counter starts at 0 and increments by exactly 1 per successful EventKit
/// save inside `ReminderStore.completeReminder`. It is only decremented by
/// undo; it is never reset in production. Tests inject UUID-keyed stores for
/// isolation.
///
/// Production writes stay within `0...100`: `increment()` runs only while
/// `canMutate` is true (count < 100), `decrement()` clamps at 0, and the reset
/// path writes 0. The `--seed` UI-test seam is the deliberate exception — it
/// writes the seed's `completionCount` verbatim, unclamped, so tests can stage
/// free-tier gate scenarios (99 = near-cap, 100 = gated) that production never
/// produces.
public struct CompletionCounterStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the store, `@AppStorage`, and sync payload.
    public static let defaultsKey = "completionCount"

    /// The current completion count. Reads `UserDefaults.integer(forKey:)`,
    /// which returns 0 when the key is absent — safe, 0-defaulted.
    public var count: Int {
        defaults.integer(forKey: key)
    }

    /// Increments the counter by 1.
    public func increment() {
        defaults.set(count + 1, forKey: key)
    }

    /// Decrements the counter by 1, clamping at zero so the count never
    /// goes negative. Only called by undo; not called in normal production.
    public func decrement() {
        let current = count
        defaults.set(max(0, current - 1), forKey: key)
    }

    /// Resets the counter to 0. Test-only; not called in production.
    public func resetForTesting() {
        defaults.set(0, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
