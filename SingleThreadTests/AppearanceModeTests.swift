@testable import SingleThread
import SwiftUI
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
        @Test(arguments: [
            (AppearanceMode.system, UIUserInterfaceStyle.unspecified),
            (AppearanceMode.light, .light),
            (AppearanceMode.dark, .dark)
        ])
        func windowOverrideStyleMaps(_ pair: (AppearanceMode, UIUserInterfaceStyle)) {
            #expect(pair.0.windowOverrideStyle == pair.1, "\(pair.0) → \(pair.1)")
        }
    #endif

    // MARK: appKitAppearance (macOS)

    #if os(macOS)
        @Test(arguments: [
            (AppearanceMode.system, nil),
            (AppearanceMode.light, NSAppearance.Name.aqua),
            (AppearanceMode.dark, NSAppearance.Name.darkAqua)
        ] as [(AppearanceMode, NSAppearance.Name?)])
        func appKitAppearanceMaps(_ pair: (AppearanceMode, NSAppearance.Name?)) {
            #expect(pair.0.appKitAppearance?.name == pair.1, "\(pair.0) → \(pair.1)")
        }
    #endif

    // MARK: colorScheme (previews)

    @Test(arguments: [
        (AppearanceMode.system, nil),
        (AppearanceMode.light, ColorScheme.light),
        (AppearanceMode.dark, ColorScheme.dark)
    ] as [(AppearanceMode, ColorScheme?)])
    func colorSchemeMaps(_ pair: (AppearanceMode, ColorScheme?)) {
        #expect(pair.0.colorScheme == pair.1, "\(pair.0) → \(pair.1)")
    }

    // MARK: load(from:)

    @Test
    func loadReadsPersistedValue() {
        let defaults = Self.freshUserDefaults()
        defaults.set("dark", forKey: "appearanceMode")
        #expect(AppearanceMode.load(from: defaults) == .dark)
    }

    @Test(arguments: [nil, "sepia"])
    func loadFallsBackToSystemOnMissingOrUnknown(_ raw: String?) {
        let defaults = Self.freshUserDefaults()
        if let raw {
            defaults.set(raw, forKey: "appearanceMode")
        }
        #expect(
            AppearanceMode.load(from: defaults) == .system,
            "\(raw.map { "\"\($0)\"" } ?? "missing") → .system")
    }

    @Test
    func allCasesAndTitlesAreHumanReadable() {
        #expect(AppearanceMode.allCases == [.system, .light, .dark])
        #expect(AppearanceMode.system.title == String.en("System", bundle: .main))
        #expect(AppearanceMode.light.title == String.en("Light", bundle: .main))
        #expect(AppearanceMode.dark.title == String.en("Dark", bundle: .main))
    }

    // MARK: Private

    /// Returns a throwaway `UserDefaults` instance so tests don't race on the
    /// shared `standard` suite (Swift Testing runs a suite's tests in
    /// parallel). Each test gets its own suite instead.
    private static func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceModeTests-\(UUID().uuidString)")!
    }
}
