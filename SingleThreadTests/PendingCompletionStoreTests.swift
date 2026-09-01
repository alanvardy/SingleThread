import Foundation
import SingleThreadCore
import Testing

struct PendingCompletionStoreTests {
    // MARK: Internal

    @Test
    func loadDefaultsToEmptySet() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(store.load().isEmpty)
    }

    @Test
    func saveLoadRoundTrips() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.save(["a", "b"])
        #expect(store.load() == ["a", "b"])
    }

    @Test
    func saveReplacesPreviousValue() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.save(["a", "b"])
        store.save(["c"]) // second save drops prior IDs — no union
        #expect(store.load() == ["c"])
    }

    @Test
    func usesInjectedSuiteNotStandard() {
        let key = "pending-test-\(UUID().uuidString)"
        // Write via one suite, read via another — the injected suite must win.
        let storeA = PendingCompletionStore(defaults: AppGroup.defaults, key: key)
        let storeB = PendingCompletionStore(defaults: .standard, key: key)
        defer {
            AppGroup.defaults.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        storeA.save(["x"])
        #expect(storeB.load().isEmpty) // .standard never saw the write
    }

    @Test
    func recordPreservesPreviousEntries() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.record("a")
        store.record("b")
        #expect(store.load() == ["a", "b"]) // no overwrite-and-lose
    }

    @Test
    func expiryDropsStaleEntriesOnLoad() {
        var clock = TimeInterval(1_000_000)
        let (store, key) = makeStore { clock }
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.record("a")
        clock += 301 // past the 300 s expiry
        store.record("b")
        #expect(store.load() == ["b"]) // stale "a" dropped, fresh "b" kept
    }

    @Test
    func expiryDropsStaleEntriesFromPersistence() {
        var clock = TimeInterval(1_000_000)
        let (store, key) = makeStore { clock }
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.record("a")
        clock += 301
        _ = store.load()
        #expect(store.load().isEmpty) // expired entry does not resurface
    }

    // MARK: Private

    private func makeStore(
        expiry: TimeInterval = 300,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) -> (PendingCompletionStore, String) {
        let key = "pending-test-\(UUID().uuidString)"
        return (PendingCompletionStore(defaults: .standard, key: key, expiry: expiry, now: now), key)
    }
}
