import Foundation
import os

/// Persists the excluded-list titles in the iCloud key-value store.
///
/// Mirrors `ExcludedListStore` (whole-array replace) but is a *transport*: the
/// App Group store remains the local truth. `nil` from ``load()`` means the key
/// was never written (seed it once from the App Group); `[]` means an
/// intentional clear and must be adopted, never reseeded.
///
/// Best effort and silent: when iCloud is unavailable (signed out, restricted,
/// quota) a write does not propagate and `load` reports the key as absent, so
/// the app behaves exactly as before — App Group and WatchConnectivity are
/// never affected. The test seam models an unavailable store as a dropped
/// write.
public struct ExcludedListCloudStore {
    // MARK: Lifecycle

    public init(
        store: any UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
        key: String = defaultsKey) {
        self.store = store
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the cloud store and the App Group store — the
    /// same text as `ExcludedListStore.defaultsKey` on purpose.
    public static let defaultsKey = "excludedListTitles"

    /// The set to adopt, or `nil` when the cloud value is absent or already
    /// equals the local set (echo suppression — a local write never loops back).
    public static func titlesToAdopt(cloud: [String]?, local: Set<String>) -> Set<String>? {
        guard let cloud else { return nil }
        let cloudSet = Set(cloud)
        return cloudSet == local ? nil : cloudSet
    }

    /// The stored titles, or `nil` when the key has never been written.
    public func load() -> [String]? {
        guard let value = store.object(forKey: key) else { return nil }
        guard let titles = value as? [String] else {
            Self.logger.debug("Unexpected iCloud payload type; treating as absent")
            return nil
        }
        return titles
    }

    /// Whole-set replace — last writer wins. An empty array is written verbatim
    /// (never `removeObject`, which would resurrect the "never written" seed
    /// path); clearing is a real value that propagates. Best effort and silent:
    /// returns `false` when the store reports the write as unsynchronized (an
    /// unavailable device), in which case it does not propagate — the App Group
    /// and WatchConnectivity paths are unaffected.
    @discardableResult
    public func save(_ titles: [String]) -> Bool {
        store.set(titles, forKey: key)
        let synced = store.synchronize()
        if !synced {
            Self.logger.debug("iCloud key-value store unavailable; excluded lists stay local")
        }
        return synced
    }

    /// Writes `titles` only when the key was never written (`nil`). A stored
    /// empty array (`[]`, an intentional clear) is NOT reseeded, and an empty
    /// `titles` is never written — seeding `[]` would fabricate a clear that
    /// erases another device's exclusions. Returns whether a write was accepted
    /// (`false` for "already present", "clear present", an empty seed, or an
    /// unavailable store).
    @discardableResult
    public func seedIfAbsent(from titles: [String]) -> Bool {
        guard !titles.isEmpty, load() == nil else { return false }
        return save(titles)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "ExcludedListCloudStore")

    private let store: any UbiquitousKeyValueStoring
    private let key: String
}
