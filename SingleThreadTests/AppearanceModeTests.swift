@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct AppearanceModeTests {
    @Test
    func systemMapsToNilColorScheme() {
        #expect(AppearanceMode.system.colorScheme == nil)
    }

    @Test
    func lightMapsToLightColorScheme() {
        #expect(AppearanceMode.light.colorScheme == .light)
    }

    @Test
    func darkMapsToDarkColorScheme() {
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test
    func allCasesCoverSystemLightDark() {
        #expect(AppearanceMode.allCases == [.system, .light, .dark])
    }

    @Test
    func titlesAreHumanReadable() {
        #expect(AppearanceMode.system.title == "System")
        #expect(AppearanceMode.light.title == "Light")
        #expect(AppearanceMode.dark.title == "Dark")
    }
}
