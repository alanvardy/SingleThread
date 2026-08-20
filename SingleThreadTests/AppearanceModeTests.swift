@testable import SingleThread
import Testing

#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@MainActor
struct AppearanceModeTests {
    // MARK: Internal

    // MARK: windowOverrideStyle (iOS)

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

    // MARK: appKitAppearance (macOS)

    #if os(macOS)
        @Test
        func systemClearsAppKitAppearance() {
            #expect(AppearanceMode.system.appKitAppearance == nil)
        }

        @Test
        func lightMapsToAqua() {
            #expect(AppearanceMode.light.appKitAppearance?.name == .aqua)
        }

        @Test
        func darkMapsToDarkAqua() {
            #expect(AppearanceMode.dark.appKitAppearance?.name == .darkAqua)
        }
    #endif

    // MARK: load(from:)

    @Test
    func loadReadsPersistedValue() {
        let defaults = Self.freshUserDefaults()
        defaults.set("dark", forKey: "appearanceMode")
        #expect(AppearanceMode.load(from: defaults) == .dark)
    }

    @Test
    func loadFallsBackToSystemWhenKeyMissing() {
        let defaults = Self.freshUserDefaults()
        #expect(AppearanceMode.load(from: defaults) == .system)
    }

    @Test
    func loadFallsBackToSystemOnUnknownString() {
        let defaults = Self.freshUserDefaults()
        defaults.set("sepia", forKey: "appearanceMode")
        #expect(AppearanceMode.load(from: defaults) == .system)
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

    // MARK: Private

    /// Returns a throwaway `UserDefaults` instance so tests don't race on the
    /// shared `standard` suite (Swift Testing runs a suite's tests in
    /// parallel). Each test gets its own suite instead.
    private static func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceModeTests-\(UUID().uuidString)")!
    }
}
