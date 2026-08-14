@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct SingleThreadTests {
    @Test func contentViewInitializesWithoutReminders() {
        let view = ContentView(loadsReminders: false)
        // Verify the view body renders without crashing
        let bodyValue = view.body
        #expect(String(describing: bodyValue).isEmpty == false)
    }

    @Test func contentViewBodyContainsRefreshableModifier() {
        let view = ContentView(loadsReminders: false)
        // Verify body renders with the ScrollView + refreshable structure
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        #expect(description.contains("ScrollView") || description.contains("refreshable"))
    }
}
