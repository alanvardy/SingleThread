import Foundation
import SingleThreadCore
import Testing

struct ExcludedListCloudStoreTests {
    // MARK: Internal

    @Test
    func loadReturnsNilWhenUnwritten() {
        #expect(makeStore().load() == nil)
    }

    @Test
    func saveThenLoadRoundTrips() {
        let store = makeStore()
        store.save(["Work", "Personal"])
        #expect(store.load() == ["Work", "Personal"])
    }

    @Test
    func seedWritesOnlyWhenAbsent() {
        let backing = InMemoryUbiquitousStore()
        let store = makeStore(backing)

        #expect(store.seedIfAbsent(from: ["Work"]))
        #expect(store.load() == ["Work"])
        #expect(!store.seedIfAbsent(from: ["Personal"]))
        #expect(store.load() == ["Work"])
        #expect(backing.values.count == 1)
    }

    @Test
    func emptyClearIsAdoptedNotReseeded() {
        let store = makeStore()
        store.save([])
        #expect(store.load()?.isEmpty == true)
        #expect(!store.seedIfAbsent(from: ["Work"]))
        #expect(store.load()?.isEmpty == true)
    }

    @Test
    func lastWriterWinsReplaceNotUnion() {
        let store = makeStore()
        store.save(["Work"])
        store.save(["Personal"])
        #expect(store.load() == ["Personal"])
    }

    @Test
    func unavailableStoreSaveIsNoOp() {
        let backing = InMemoryUbiquitousStore()
        backing.isAvailable = false
        let store = makeStore(backing)

        store.save(["Work"])

        #expect(backing.values.isEmpty)
        #expect(store.load() == nil)
        #expect(backing.synchronizeCount == 1)
    }

    @Test
    func unavailableStoreLoadReturnsNil() {
        let backing = InMemoryUbiquitousStore()
        let store = makeStore(backing)
        store.save(["Work"])
        backing.isAvailable = false

        #expect(store.load() == nil)
        // An unavailable store reports the key as absent, so the seed is still
        // attempted and returns true — but the write is dropped.
        #expect(store.seedIfAbsent(from: ["Personal"]))
        #expect(backing.values[Self.key] as? [String] == ["Work"])
    }

    // MARK: Private

    private static let key = "test-excluded-cloud"

    private func makeStore(
        _ backing: InMemoryUbiquitousStore = InMemoryUbiquitousStore()) -> ExcludedListCloudStore {
        ExcludedListCloudStore(store: backing, key: Self.key)
    }
}
