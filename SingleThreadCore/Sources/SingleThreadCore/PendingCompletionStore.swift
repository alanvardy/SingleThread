import Foundation

/// Persists pending-completion reminder identifiers in UserDefaults. The watch
/// records a completed identifier here until the phone processes the relay and
/// the reminder stops appearing in incomplete fetches; `reload()` prunes it.
///
/// The set is device-local: only the watchOS `completeReminder` branch writes
/// it (on watchOS the App Group is unavailable, so `AppGroup.defaults` falls
/// back to `.standard`). iOS never writes it, so on iOS `load()` is always
/// empty and the pending filter in `reload()` is a no-op.
///
/// Each entry carries an insertion timestamp and expires after ``expiry``
/// seconds — the safety valve for a relay lost while the phone is unreachable,
/// which would otherwise leave an unprocessed completion hidden indefinitely.
/// `load()` drops expired entries; `record(_:)` and `save(_:)` persist only the
/// live remainder.
public struct PendingCompletionStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = defaultsKey,
        expiry: TimeInterval = 300,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.defaults = defaults
        self.key = key
        self.expiry = expiry
        self.now = now
    }

    // MARK: Public

    /// Single shared key used by the store and sync payload.
    public static let defaultsKey = "pendingCompletionIdentifiers"

    /// Returns only the identifiers that have not exceeded ``expiry``.
    public func load() -> Set<String> {
        Set(liveEntries().keys)
    }

    /// Records `identifier` as just-completed, stamping it now while preserving
    /// the timestamps of every other live entry. Used by the watchOS completion
    /// branch — it replaces the prior `insert` + `save` so a completion can
    /// never overwrite-and-lose earlier persisted entries.
    public func record(_ identifier: String) {
        var entries = liveEntries()
        entries[identifier] = now()
        persist(entries)
    }

    /// Replaces the stored set with `identifiers` — never unions. Existing live
    /// entries keep their timestamps; new identifiers are stamped now; anything
    /// not in `identifiers` is dropped. Used by `reload()` to drain identifiers
    /// the phone has since completed. This invariant (a clear prunes stale IDs)
    /// is what lets `reload()` drain the set.
    public func save(_ identifiers: Set<String>) {
        var entries = liveEntries()
        entries = entries.filter { identifiers.contains($0.key) }
        for identifier in identifiers where entries[identifier] == nil {
            entries[identifier] = now()
        }
        persist(entries)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
    private let expiry: TimeInterval
    private let now: () -> TimeInterval

    private func liveEntries() -> [String: TimeInterval] {
        let stored = defaults.dictionary(forKey: key) ?? [:]
        let cutoff = now() - expiry
        var live: [String: TimeInterval] = [:]
        for (identifier, value) in stored {
            guard let stamp = value as? TimeInterval else { continue }
            if stamp >= cutoff {
                live[identifier] = stamp
            }
        }
        return live
    }

    private func persist(_ entries: [String: TimeInterval]) {
        defaults.set(entries.mapValues { TimeInterval($0) }, forKey: key)
    }
}
