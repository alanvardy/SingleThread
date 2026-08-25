import SwiftUI

/// A scheme-adaptive circular plate that ensures controls are legible against
/// any background photo in both light and dark modes.
///
/// Applies a 56×56 frame, a solid fill circle, a contrasting 2pt stroke
/// outline, and a shadow that lifts the control above the background.
///
/// Colours adapt to the current colour scheme unless explicitly overridden:
/// - Dark mode: black plate, white glyph, white stroke
/// - Light mode: off-white plate, dark glyph, dark stroke
struct ControlPlateModifier: ViewModifier {
    // MARK: Internal

    /// Overrides the scheme-adaptive plate fill. Defaults to `nil` (auto).
    var fill: Color?
    /// Overrides the scheme-adaptive glyph colour. Defaults to `nil` (auto).
    var glyph: Color?
    /// Overrides the scheme-adaptive stroke colour. Defaults to `nil` (auto).
    var stroke: Color?

    func body(content: Content) -> some View {
        let resolvedFill = fill ?? (colorScheme == .dark ? .black : Color(white: Self.lightPlateWhite))
        let resolvedGlyph = glyph ?? (colorScheme == .dark ? .white : Color(white: Self.darkGlyphWhite))
        let resolvedStroke = stroke ?? (colorScheme == .dark ? .white : Color(white: Self.darkGlyphWhite))

        content
            .foregroundStyle(resolvedGlyph)
            .frame(width: Self.plateSize, height: Self.plateSize)
            .background(resolvedFill, in: Circle())
            .overlay {
                Circle()
                    .stroke(resolvedStroke, lineWidth: Self.strokeWidth)
            }
            .shadow(radius: Self.shadowRadius)
    }

    // MARK: Private

    private static let plateSize: CGFloat = 56
    private static let lightPlateWhite: Double = 0.92
    private static let darkGlyphWhite: Double = 0.15
    private static let shadowRadius: CGFloat = 4
    private static let strokeWidth: CGFloat = 2

    @Environment(\.colorScheme)
    private var colorScheme
}

extension View {
    /// Wraps the view in a scheme-adaptive circular plate with a contrasting
    /// stroke outline so the control remains visible against any background.
    ///
    /// - Parameters:
    ///   - fill: Plate fill colour override. `nil` picks dark‑mode black
    ///     / light‑mode off‑white.
    ///   - glyph: Glyph colour override. `nil` picks dark‑mode white
    ///     / light‑mode near‑black.
    ///   - stroke: Stroke colour override. `nil` picks the same
    ///     scheme‑adaptive colour as `glyph`.
    func controlPlate(
        fill: Color? = nil,
        glyph: Color? = nil,
        stroke: Color? = nil) -> some View {
        modifier(ControlPlateModifier(fill: fill, glyph: glyph, stroke: stroke))
    }
}
