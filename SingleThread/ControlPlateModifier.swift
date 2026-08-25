import SwiftUI

struct ControlPlateModifier: ViewModifier {
    // MARK: Internal

    var fill: Color?
    var glyph: Color?
    var stroke: Color?

    func body(content: Content) -> some View {
        let resolvedFill = fill ?? (colorScheme == .dark ? .black : Color(white: 0.92))
        let resolvedGlyph = glyph ?? (colorScheme == .dark ? .white : Color(white: 0.15))
        let resolvedStroke = stroke ?? (colorScheme == .dark ? .white : Color(white: 0.15))

        content
            .foregroundStyle(resolvedGlyph)
            .frame(width: 56, height: 56)
            .background(resolvedFill, in: Circle())
            .overlay {
                Circle()
                    .stroke(resolvedStroke, lineWidth: 2)
            }
            .shadow(radius: 4)
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme
}

extension View {
    func controlPlate(
        fill: Color? = nil,
        glyph: Color? = nil,
        stroke: Color? = nil) -> some View {
        modifier(ControlPlateModifier(fill: fill, glyph: glyph, stroke: stroke))
    }
}
