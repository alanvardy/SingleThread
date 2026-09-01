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

    // MARK: Private

    private func makeStore() -> (PendingCompletionStore, String) {
        let key = "pending-test-\(UUID().uuidString)"
        return (PendingCompletionStore(defaults: .standard, key: key), key)
    }
}
