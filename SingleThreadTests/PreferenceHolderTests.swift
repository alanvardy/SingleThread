import Foundation
import SingleThreadCore
import Testing

@MainActor
struct PreferenceHolderTests {
    /// Uses real AppGroup.defaults; restores original values in defer.
    @Test
    func initializesFromStores() {
        let original = ShowDatePreference().isEnabled
        defer { ShowDatePreference().set(original) }

        ShowDatePreference().set(false)
        let holder = PreferenceHolder()
        #expect(!holder.showDate, "reads false from store")
    }

    @Test
    func refreshesOnNotification() async {
        let original = ShowDatePreference().isEnabled
        defer { ShowDatePreference().set(original) }

        ShowDatePreference().set(true)
        let holder = PreferenceHolder()
        #expect(holder.showDate, "initially true")

        ShowDatePreference().set(false)
        // Give the notification a cycle to deliver
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        #expect(!holder.showDate, "refreshed to false after store write")
    }
}
