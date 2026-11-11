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

    // MARK: Private

    private static let key = "test-excluded-cloud"

    private func makeStore(
        _ backing: InMemoryUbiquitousStore = InMemoryUbiquitousStore()) -> ExcludedListCloudStore {
        ExcludedListCloudStore(store: backing, key: Self.key)
    }
}
