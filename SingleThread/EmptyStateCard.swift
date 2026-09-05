import SwiftUI

// MARK: - Empty State Card

/// Compact content-wrapping plate for the iOS empty states ("No Reminders",
/// "Nothing due", "All Done"), mirroring the reminder card: an opaque
/// off-white/black plate that hugs its own text and is centered on screen by
/// the caller's `.frame(maxWidth: .infinity, minHeight:alignment:)`. Replaces
/// `ContentUnavailableView` here, which expands to fill the proposed frame —
/// its background then stretched across the whole screen.
struct EmptyStateCard: View {
    // MARK: Internal

    let copy: ContentViewModel.EmptyStateCopy

    /// Cap for the description text's wrap width.
    var maxWidth: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: copy.systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(copy.title)
                .font(.title2.bold())
                .accessibilityIdentifier("emptyStateTitle")
            Text(copy.description)
                .font(.callout)
                .accessibilityIdentifier("emptyStateDescription")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxWidth)
        }
        .cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)
    }

    /// Caps the description's width so long copy wraps on a couple of centered
    /// lines instead of stretching the plate edge-to-edge; short copy keeps its
    /// natural size (Text hugs when the proposal exceeds its ideal width) so the
    /// plate always hugs its text. Relative so the card stays proportionate on
    /// iPads, with an absolute ceiling so it never balloons on very wide screens.
    static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        CardWidth.maxContentWidth(viewportWidth: viewportWidth)
    }

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme
}
