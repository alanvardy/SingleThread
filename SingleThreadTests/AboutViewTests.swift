@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - AboutView Tests

@MainActor
struct AboutViewTests {
    // MARK: Internal

    @Test
    func aboutViewRendersAttributionAndIdentity() {
        let view = AboutView(appInfo: stubAppInfo())
        let bodyDescription = String(describing: view.body)

        for expected in [
            "Copyright 2026 Alan Vardy",
            "Made with ❤️ by a Canadian developer 🇨🇦",
            "Version 1.0 (1)",
            "SingleThread",
            "alan@vardy.cc"
        ] {
            #expect(bodyDescription.contains(expected))
        }
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }

    @Test
    func aboutViewRendersWithoutCrashingWhenVersionIsNil() {
        let view = AboutView(appInfo: AppInfo(bundle: StubBundle(info: [:])))
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Copyright 2026 Alan Vardy"))
        #expect(bodyDescription.contains("Made with ❤️ by a Canadian developer 🇨🇦"))
        // Display name falls back to the "SingleThread" literal.
        #expect(bodyDescription.contains("SingleThread"))
    }

    // MARK: Private

    private func stubAppInfo() -> AppInfo {
        AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "SingleThread"
        ]))
    }
}
