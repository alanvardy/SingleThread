@testable import SingleThread
import SwiftUI
import Testing

// MARK: - Settings Subscreen Layout Tests

@MainActor
struct SettingsSubscreenLayoutTests {
    // SwiftUI does not inline a `ViewModifier`'s body into the host view's
    // reflected description (see `CardPlateModifierTests`), so reflection can
    // only pin that the modifier is present — which, on macOS, *is* the
    // fill-and-top-align behavior.
    #if os(macOS)
        @Test
        func settingsSubscreenLayoutTopAlignedOnMacOS() {
            let view = Text("hi").settingsSubscreenLayout()
            #expect(
                String(describing: view).contains("SettingsSubscreenLayout"),
                "macOS branch should wrap content in the top-anchoring modifier")
        }
    #endif

    // Negative/sad path: on iOS the helper must be a true no-op — the wrapped
    // view equals the unwrapped view and carries no `SettingsSubscreenLayout`.
    #if os(iOS)
        @Test
        func settingsSubscreenLayoutIsNoopOnIOS() {
            let content = Text("hi")
            let wrapped = content.settingsSubscreenLayout()
            let wrappedDescription = String(describing: wrapped)
            #expect(wrappedDescription == String(describing: content))
            #expect(!wrappedDescription.contains("SettingsSubscreenLayout"))
        }
    #endif
}
