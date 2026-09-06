import Foundation
import SingleThreadCore
import Testing

@MainActor
@Suite(.serialized)
struct AppGroupRegistrationTests {
    /// Probes registration took effect: the suite initializer returns a
    /// non-nil UserDefaults instance when the host app is entitled.
    @Test
    func suiteResolvesOnWatch() {
        let defaults = UserDefaults(suiteName: AppGroup.suiteName)
        #expect(defaults != nil,
            """
            App Group suite must resolve on a registered watch build. \
            If this fails, registration does not take effect on the \
            watchOS simulator — record the negative finding and stop.
            """)
    }
}