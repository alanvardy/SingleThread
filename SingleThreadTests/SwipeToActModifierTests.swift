@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

/// Reflection coverage for the swipe reveal panel and modifier: the direction
/// selects the Complete/More label, and the idle modifier wraps its content
/// without revealing a panel behind it.
@MainActor
struct SwipeToActModifierTests {
    // MARK: Internal

    @Test
    func completePanelShowsCompleteLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .complete, progress: 1).body)
        #expect(description.contains("Complete"))
        #expect(description.contains("CardPlateModifier"))
    }

    @Test
    func morePanelShowsMoreLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .more, progress: 1).body)
        #expect(description.contains("More"))
        #expect(description.contains("CardPlateModifier"))
    }

    /// The revealed glyph must be the ellipsis-in-circle SF Symbol, not the
    /// circle-slash used by the skip action.
    @Test
    func morePanelUsesEllipsisGlyph() {
        #expect(SwipeRevealPanel.systemImage(for: .more) == "ellipsis.circle.fill")
    }

    @Test
    func skipPanelShowsSkipLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .skip, progress: 1).body)
        #expect(description.contains("Skip"))
        #expect(description.contains("CardPlateModifier"))
    }

    @Test
    func skipPanelUsesLeftArrowGlyph() {
        #expect(SwipeRevealPanel.systemImage(for: .skip) == "arrow.left.circle.fill")
    }

    /// The reveal plate hugs the edge the card uncovers: completing (rightward
    /// drag) exposes the leading edge, skipping (leftward) the trailing one.
    /// Asserts the extracted placement decision so the plate cannot regress to
    /// a full-frame fill.
    @Test
    func completePanelAnchorsPlateToLeadingEdge() {
        #expect(SwipeRevealPanel.alignment(for: .complete) == .leading)
    }

    @Test
    func skipPanelAnchorsPlateToTrailingEdge() {
        #expect(SwipeRevealPanel.alignment(for: .skip) == .trailing)
    }

    /// The up-swipe reveals the action menu from the bottom edge as the card
    /// is lifted upward.
    @Test
    func morePanelAnchorsPlateToBottomEdge() {
        #expect(SwipeRevealPanel.alignment(for: .more) == .bottom)
    }

    /// Regression guard for the stranded "More" plate: the reveal container
    /// must hug the card vertically. Without a vertical fixed-size constraint
    /// the flexible panel absorbs the row's full-height proposal and `.bottom`
    /// drops the plate at the bottom of the screen instead of under the card.
    @Test
    func revealContainerHugsCardVertically() {
        let container = SwipeRevealContainer(revealedOutcome: .more, progress: 1) { Text("card") }
        let description = String(describing: container.body)
        #expect(
            description.contains("FixedSize"),
            "reveal container must apply a vertical fixed-size constraint; desc: \(description)")
    }

    @Test
    func idleModifierWrapsContentWithoutPanel() {
        let description = String(describing: swipeToActOver(Text("card")))
        #expect(description.contains("card"))
        #expect(description.contains("SwipeToActModifier"))
        #expect(!description.contains("Complete"))
        #expect(!description.contains("More"))
    }

    // MARK: Private

    /// Applies the drag-to-act modifier to `content`. Reflected through a
    /// SwiftUI-composed host because `ViewModifier.body(content:)` takes the
    /// runtime `Content` sample type, which tests cannot construct directly
    /// from a bare view.
    private func swipeToActOver(_ content: some View) -> some View {
        content.modifier(SwipeToActModifier(threshold: 72) { _ in })
    }
}
