import SwiftUI

/// Shared styling decisions for every rounded-rectangle content plate in the
/// app: the card text plate, the empty-state card plate, and the swipe-prompt
/// box. Extracted so the constants are owned by the namespace that names them
/// and the decisions can be asserted headlessly in tests.
///
/// All three plates share the same 10pt corner radius. The card text plate and
/// empty-state plate share an adaptive fill (off-white light / black dark),
/// and the swipe-prompt box has its own adaptive fill (mid-light grey /
/// dark grey) so it always contrasts against the card plate behind it.
enum CardPlate {
    /// Shared corner radius for every content plate — the card text plate, the
    /// empty-state card plate, and the swipe-prompt box. Extracted because the
    /// rendered shape can't be asserted headlessly — tests assert this
    /// decision instead.
    static let cornerRadius: CGFloat = 10

    /// Small content-sized high-contrast plate behind the card text: off-white
    /// in light, black in dark, so the text stays readable over a photo or
    /// wallpaper. Extracted because the rendered paint can't be asserted
    /// headlessly — tests assert this decision instead.
    static func plateFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.95, blue: 0.94)
    }

    /// Plate behind the swipe instructions and Dismiss button so the coloured
    /// hints read as one dismissible prompt on the card. Light mode uses a
    /// mid-light fill (`0.92`, the control-plate light fill) that sits slightly
    /// darker than the card plate; dark mode keeps the original dark grey.
    static func promptBoxFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.18) : Color(white: 0.92)
    }

    /// Adaptive tint for the "Swipe left to skip" hint. Light mode uses a
    /// slightly darkened orange so the caption stays legible on the mid-light
    /// prompt box; dark mode keeps the semantic `.orange` that matches the
    /// swipe action's own tint. Extracted because the rendered paint can't be
    /// asserted headlessly — tests assert this decision instead.
    static func skipHintColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .orange : Color(red: 0.78, green: 0.35, blue: 0.0)
    }

    /// Adaptive tint for the "Swipe right to complete" hint (darkened green in
    /// light mode, semantic `.green` in dark mode — same rationale as
    /// `skipHintColor(for:)`).
    static func completeHintColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .green : Color(red: 0.10, green: 0.58, blue: 0.24)
    }
}
