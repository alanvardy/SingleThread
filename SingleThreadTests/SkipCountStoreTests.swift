import Foundation
import SingleThreadCore
import Testing

struct SkipCountStoreTests {
    // MARK: Internal

    // MARK: Store round-trips

    @Test
    func roundTripsSaveAndLoad() {
        let store = SkipCountStore(defaults: Self.freshUserDefaults())
        store.save(["a": 3, "b": 1])
        #expect(store.load() == ["a": 3, "b": 1], "save/load round-trips the dict")
    }

    @Test
    func loadsEmptyByDefault() {
        let store = SkipCountStore(defaults: Self.freshUserDefaults())
        #expect(store.load().isEmpty, "fresh store over an isolated suite is empty")
    }

    @Test
    func isolatesByUUIDKey() {
        let storeA = SkipCountStore(defaults: Self.freshUserDefaults())
        let storeB = SkipCountStore(defaults: Self.freshUserDefaults())
        storeA.save(["a": 5])
        #expect(storeB.load().isEmpty, "separate UUID suites don't share counts")
        #expect(storeA.load() == ["a": 5], "the writing suite still sees its own counts")
    }

    // MARK: shouldNudge

    @Test(arguments: [
        (0, false),
        (1, false),
        (4, false),
        (5, false),
        (6, true),
        (7, true),
        (20, true)
    ])
    func shouldNudgeFiresOnlyAtOrPastThreshold(_ pair: (count: Int, expected: Bool)) {
        #expect(
            SkipCountLogic.shouldNudge(pair.count) == pair.expected,
            "count \(pair.count) → \(pair.expected)")
    }

    // MARK: crossedThreshold

    @Test(arguments: [
        ((5, 6), true),
        ((6, 7), false),
        ((4, 5), false),
        ((0, 6), true),
        ((5, 7), true)
    ])
    func crossedThresholdFiresOnlyOnce(_ item: (fromTo: (Int, Int), expected: Bool)) {
        #expect(
            SkipCountLogic.crossedThreshold(from: item.fromTo.0, to: item.fromTo.1) == item.expected,
            "(\(item.fromTo.0) → \(item.fromTo.1)) → \(item.expected)")
    }

    // MARK: Private

    /// Returns a throwaway `UserDefaults` instance so tests don't race on the
    /// shared `standard`/App Group suites (Swift Testing runs a suite's tests in
    /// parallel). Each test gets its own suite instead.
    private static func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SkipCountStoreTests-\(UUID().uuidString)")!
    }
}
