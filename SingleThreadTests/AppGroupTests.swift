import Foundation
import SingleThreadCore
import Testing

// MARK: - AppGroup

/// Thread-safe counter for the notification closure. A `@Sendable` closure
/// cannot mutate a captured `var`, so the test counts through a locked box.
private final class NotificationCounter: @unchecked Sendable {
    // MARK: Internal

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

struct AppGroupTests {
    @Test
    func suiteNameIsConfigured() {
        #expect(AppGroup.suiteName == "group.app.alanvardy.SingleThread")
    }

    /// The `UserDefaults.didChangeNotification` observers (`PreferenceHolder`,
    /// `AppViewModel`'s AI-rules and watch-sync observers) filter on
    /// `object: AppGroup.defaults`. The notification's object is the instance
    /// that changed, so those observers only fire when every access returns the
    /// same instance. A computed `AppGroup.defaults` breaks that silently.
    @Test
    func defaultsIsAStableInstance() {
        #expect(
            AppGroup.defaults === AppGroup.defaults,
            "observers filter on this instance; a fresh instance per access never matches a write")
    }

    @Test
    func objectFilteredObserverSeesAppGroupWrites() async {
        // Mirrors every app observer (`PreferenceHolder`, `AppViewModel`'s
        // AI-rules and watch-sync observers): registered with `object:` and
        // fired by a write through `AppGroup.defaults`. With a per-access
        // instance the write carried a different object and never arrived.
        let fired = NotificationCounter()
        let observedDefaults = AppGroup.defaults
        let key = "appgroup-probe-\(UUID().uuidString)"
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: observedDefaults,
            queue: .main) { _ in fired.increment() }
        defer {
            NotificationCenter.default.removeObserver(token)
            AppGroup.defaults.removeObject(forKey: key)
        }
        AppGroup.defaults.set(true, forKey: key)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(fired.count >= 1, "an object-filtered observer must see AppGroup.defaults writes")
    }

    @Test
    func defaultsRoundTripsValues() {
        let key = "appgroup-test-\(UUID().uuidString)"
        defer { AppGroup.defaults.removeObject(forKey: key) }
        AppGroup.defaults.set("test-value", forKey: key)
        #expect(AppGroup.defaults.string(forKey: key) == "test-value")
    }
}
