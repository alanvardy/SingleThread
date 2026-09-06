import SwiftUI

/// Suppresses the platform-default button chrome so icon-only controls render
/// as their own drawn plate (`controlPlate`) without macOS's bordered bezel.
///
/// iOS/iPadOS already render icon-only labels chrome-less, so `.borderless` is
/// a no-op there; on macOS it removes the translucent square the default bezel
/// draws around a `.controlPlate()` label. Deliberately no `#if os` inside so
/// the shared (cross-platform) mic button can call the same symbol.
struct SingleThreadButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderless)
    }
}

extension View {
    /// Applies `.buttonStyle(.borderless)` through one shared symbol so the
    /// chrome-suppression decision lives in a single, reflection-assertable
    /// place (mirrors `View.controlPlate(fill:glyph:)`).
    func singleThreadButton() -> some View {
        modifier(SingleThreadButtonModifier())
    }
}
