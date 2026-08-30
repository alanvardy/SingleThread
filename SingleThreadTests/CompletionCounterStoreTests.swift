import Foundation
import SingleThreadCore
import Testing

@Suite(.serialized)
struct CompletionCounterStoreTests {
    // UUID-backed stores so tests never share state with each other or production.

    @Test
    func countStartsAtZeroOnFreshKey() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        #expect(store.count == 0) // swiftlint:disable:this empty_count
    }

    @Test
    func incrementAdvancesCount() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        #expect(store.count == 0) // swiftlint:disable:this empty_count
        store.increment()
        #expect(store.count == 1)
        store.increment()
        #expect(store.count == 2)
    }

    @Test
    func countSurvivesStoreRecreation() {
        let key = UUID().uuidString
        let defaults = UserDefaults.standard
        let first = CompletionCounterStore(defaults: defaults, key: key)
        first.increment()
        first.increment()
        let second = CompletionCounterStore(defaults: defaults, key: key)
        #expect(second.count == 2)
    }

    @Test
    func storesAreIsolatedByKey() {
        let storeA = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        let storeB = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        storeA.increment()
        storeA.increment()
        storeB.increment()
        #expect(storeA.count == 2)
        #expect(storeB.count == 1)
    }

    @Test
    func resetForTestingZeroesCounter() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        store.increment()
        store.increment()
        store.resetForTesting()
        #expect(store.count == 0) // swiftlint:disable:this empty_count
    }

    @Test
    func decrementReducesCount() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        store.increment()
        store.increment()
        store.increment()
        #expect(store.count == 3)
        store.decrement()
        #expect(store.count == 2)
    }

    @Test
    func decrementDoesNotGoBelowZero() {
        let store = CompletionCounterStore(
            defaults: .standard,
            key: UUID().uuidString)
        #expect(store.count == 0) // swiftlint:disable:this empty_count
        store.decrement()
        #expect(store.count == 0) // swiftlint:disable:this empty_count
    }

    @Test
    func countOnSeededKeyReads100() {
        let key = UUID().uuidString
        UserDefaults.standard.set(100, forKey: key)
        let store = CompletionCounterStore(defaults: .standard, key: key)
        #expect(store.count == 100)
    }
}
