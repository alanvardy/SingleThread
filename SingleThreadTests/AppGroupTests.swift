import Foundation
import SingleThreadCore
import Testing

// MARK: - AppGroup

struct AppGroupTests {
    @Test
    func suiteNameIsConfigured() {
        #expect(AppGroup.suiteName == "group.app.alanvardy.SingleThread")
    }

    @Test
    func defaultsRoundTripsValues() {
        let key = "appgroup-test-\(UUID().uuidString)"
        defer { AppGroup.defaults.removeObject(forKey: key) }
        AppGroup.defaults.set("test-value", forKey: key)
        #expect(AppGroup.defaults.string(forKey: key) == "test-value")
    }
}
