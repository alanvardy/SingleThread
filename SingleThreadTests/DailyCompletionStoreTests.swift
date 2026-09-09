import Foundation
import SingleThreadCore
import Testing

@Suite(.serialized)
struct DailyCompletionStoreTests {
    // MARK: Internal

    @Test
    func defaultsAreZero() {
        #expect(store.todayCount == 0)
        #expect(store.dayMarker == 0)
    }

    @Test
    func incrementSetsCountToOne() {
        store.increment()
        #expect(store.todayCount == 1)
        #expect(store.dayMarker == Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
    }

    @Test
    func incrementSameDay() {
        store.increment()
        store.increment()
        #expect(store.todayCount == 2)
    }

    @Test
    func dayRolloverResetsCount() throws {
        // Inject yesterday's marker via the shared suite so the next
        // increment triggers a day rollover.
        let yesterday = try Calendar.current.startOfDay(
            for: #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))).timeIntervalSinceReferenceDate
        suite.set(yesterday, forKey: "t_marker")
        store.increment()
        #expect(store.todayCount == 1)
        #expect(store.dayMarker == Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate)
    }

    @Test
    func decrementClamps() {
        store.decrement()
        #expect(store.todayCount == 0)
    }

    @Test
    func decrementAfterIncrement() {
        store.increment()
        store.increment()
        store.decrement()
        #expect(store.todayCount == 1)
    }

    @Test
    func survivesRecreation() {
        store.increment()
        let recreated = DailyCompletionStore(
            defaults: suite,
            markerKey: "t_marker",
            countKey: "t_count")
        #expect(recreated.todayCount == 1)
    }

    @Test
    func perKeyIsolation() {
        store.increment()
        let isolated = DailyCompletionStore(
            defaults: suite,
            markerKey: "b_marker",
            countKey: "b_count")
        #expect(isolated.todayCount == 0)
        #expect(store.todayCount == 1)
    }

    @Test
    func resetForTesting() {
        store.increment()
        store.resetForTesting()
        #expect(store.todayCount == 0)
        #expect(store.dayMarker == 0)
    }

    // MARK: Private

    /// Shared `UserDefaults` suite so tests can write markers directly
    /// without accessing private store properties.
    private let suite = UserDefaults(suiteName: "DailyCompletionStoreTests-\(UUID())")!

    /// A store over `suite` with the suite's fixed keys. Computed (not lazy)
    /// because all state lives in `UserDefaults` — each access returns an
    /// equivalent store, and no `mutating` access to `self` is required.
    private var store: DailyCompletionStore {
        DailyCompletionStore(defaults: suite, markerKey: "t_marker", countKey: "t_count")
    }
}
