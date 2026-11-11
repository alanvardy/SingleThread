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

    // MARK: Private

    @Environment(\.colorScheme)
    private var colorScheme
}
