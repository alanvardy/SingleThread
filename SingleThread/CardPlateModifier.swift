import SwiftUI

/// A rounded-rectangle content plate with a shared 10pt corner radius.
///
/// Applies padding then draws a `RoundedRectangle` fill behind the content.
/// Optionally restores the original outer geometry with a negative-padding
/// undo step so list row metrics are unchanged — only the card text plate
/// uses this; the prompt and empty-state plates occupy genuine layout.
///
/// - Parameters:
///   - fill: The plate background colour. Call sites resolve the adaptive
///     fill — the modifier is a pure shape/padding machine.
///   - padding: Inset applied before the background is drawn. Defaults to 12.
///   - restoresGeometry: When `true`, applies `-padding` after the background
///     so the outer frame is net-zero. Only correct inside a `List` row; misuse
///     outside a list causes frame underflow.
struct CardPlateModifier: ViewModifier {
    var fill: Color
    var padding: CGFloat
    var restoresGeometry: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                    .fill(fill)
            }
            .padding(restoresGeometry ? -padding : 0)
    }
}

extension View {
    /// Wraps the view in a shared rounded-rectangle card plate with
    /// radius-10 corners.
    ///
    /// - Parameters:
    ///   - fill: The plate background colour. Use `CardPlate.plateFill(for:)`
    ///     for the adaptive fill.
    ///   - padding: Inset before the background is drawn (default 12).
    ///   - restoresGeometry: When `true`, applies a negative-padding undo
    ///     after the background so the outer frame is unchanged. Only correct
    ///     inside a `List` row (default `false`).
    func cardPlate(
        fill: Color,
        padding: CGFloat = 12,
        restoresGeometry: Bool = false) -> some View {
        modifier(CardPlateModifier(fill: fill, padding: padding, restoresGeometry: restoresGeometry))
    }
}
