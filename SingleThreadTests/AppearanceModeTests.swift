@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct AppearanceModeTests {
    #if os(iOS)
        @Test
        func systemMapsToUnspecifiedWindowStyle() {
            #expect(AppearanceMode.system.windowOverrideStyle == .unspecified)
        }

        @Test
        func lightMapsToLightWindowStyle() {
            #expect(AppearanceMode.light.windowOverrideStyle == .light)
        }

        @Test
        func darkMapsToDarkWindowStyle() {
            #expect(AppearanceMode.dark.windowOverrideStyle == .dark)
        }
    #endif

    @Test
    func loadReadsPersistedValue() {
        UserDefaults.standard.set("dark", forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .dark)
    }

    @Test
    func loadFallsBackToSystemWhenKeyMissing() {
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .system)
    }

    @Test
    func loadFallsBackToSystemOnUnknownString() {
        UserDefaults.standard.set("sepia", forKey: "appearanceMode")
        #expect(AppearanceMode.load() == .system)
    }

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
