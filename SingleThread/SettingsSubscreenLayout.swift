import SwiftUI

/// Frames a pushed Settings sub-view's content to fill the available height
/// and top-align, fixing the macOS sheet's vertical-centering bug. Applied
/// only on macOS: on iOS `settingsSubscreenLayout()` returns the receiver
/// unchanged, so the iOS Settings surface is untouched.
struct SettingsSubscreenLayout: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Fills and top-aligns the receiving view on macOS; a no-op on iOS.
    func settingsSubscreenLayout() -> some View {
        #if os(macOS)
            modifier(SettingsSubscreenLayout())
        #else
            self
        #endif
    }
}