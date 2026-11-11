import CoreGraphics

/// Pure layout policy for the checklist/reminder card. `Context.standard`
/// reproduces the pre-Duo layout exactly (see `CardWidth`); the Duo outer
/// portrait variant halves the screen gutter and widens the card cap.
enum ChecklistLayout {
    struct Context: Equatable, Sendable {
        nonisolated static let standard = Self(isDuoOuterPortrait: false)

        let isDuoOuterPortrait: Bool
    }

    /// Screen gutter around the card. Was a hard-coded 40 before the policy.
    nonisolated static let defaultHorizontalInset: CGFloat = 40
    /// Duo outer portrait halves the gutter so the card gets wider.
    nonisolated static let duoOuterHorizontalInset: CGFloat = 20
    /// The Duo outer screen is narrow, so the card may use more of it.
    nonisolated static let duoOuterWidthFraction: CGFloat = 0.8
    nonisolated static let maxWidthCeiling: CGFloat = 340

    nonisolated static func horizontalInset(_ context: Context) -> CGFloat {
        context.isDuoOuterPortrait ? duoOuterHorizontalInset : defaultHorizontalInset
    }

    /// Standard context delegates to `CardWidth`, so the default path cannot
    /// drift from `min(340, viewportWidth * 0.6)`.
    nonisolated static func maxContentWidth(
        viewportWidth: CGFloat,
        context: Context) -> CGFloat {
        guard context.isDuoOuterPortrait else {
            return CardWidth.maxContentWidth(viewportWidth: viewportWidth)
        }
        return min(maxWidthCeiling, viewportWidth * duoOuterWidthFraction)
    }
}
