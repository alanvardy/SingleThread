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
}
