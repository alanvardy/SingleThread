import Foundation
import SingleThreadCore
import Testing

@MainActor
struct PreferenceHolderTests {
    // MARK: Internal

    /// Uses real AppGroup.defaults; restores original values in defer.
    @Test
    func initializesFromStores() {
        let original = dateStore().isEnabled
        defer { dateStore().set(original) }

        dateStore().set(false)
        let holder = PreferenceHolder()
        #expect(!holder.showDate, "reads false from store")
    }

    @Test
    func refreshesOnNotification() async {
        let original = dateStore().isEnabled
        defer { dateStore().set(original) }

        dateStore().set(true)
        let holder = PreferenceHolder()
        #expect(holder.showDate, "initially true")

        dateStore().set(false)
        // Give the notification a cycle to deliver
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        #expect(!holder.showDate, "refreshed to false after store write")
    }

    // MARK: Private

    private func dateStore() -> BoolPreferenceStore {
        BoolPreferenceStore(key: BoolPreferenceKey.showDate.rawValue, fallback: true)
    }
}
