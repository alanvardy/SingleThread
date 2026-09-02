import Foundation
import SingleThreadCore
import Testing

struct PendingCompletionStoreTests {
    // MARK: Internal

    @Test
    func defaultsAndRoundTrips() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(store.load().isEmpty, "defaults to empty set")
        store.save(["a", "b"])
        #expect(store.load() == ["a", "b"], "save/load round-trips")
        store.save(["c"])
        #expect(store.load() == ["c"], "second save replaces prior ids — no union")
    }

    @Test
    func recordPreservesPreviousEntries() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.record("a")
        store.record("b")
        #expect(store.load() == ["a", "b"], "record appends without overwrite-and-lose")
    }

    @Test
    func expiryDropsStaleEntriesWithoutResurfacing() {
        var clock = TimeInterval(1_000_000)
        let (store, key) = makeStore { clock }
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.record("a")
        clock += 301 // past the 300 s expiry
        store.record("b")
        #expect(store.load() == ["b"], "stale entry dropped, fresh entry kept")
        clock += 301 // "b" is now stale too
        _ = store.load()
        #expect(store.load().isEmpty, "expired entry does not resurface on a later load")
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
        #expect(storeB.load().isEmpty, ".standard never sees the injected-suite write")
    }

    // MARK: Private

    private func makeStore(
        expiry: TimeInterval = 300,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) -> (PendingCompletionStore, String) {
        let key = "pending-test-\(UUID().uuidString)"
        return (PendingCompletionStore(defaults: .standard, key: key, expiry: expiry, now: now), key)
    }
}
