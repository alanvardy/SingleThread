import SwiftUI

@main
struct SingleThreadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                loadsReminders: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        }
    }
}
