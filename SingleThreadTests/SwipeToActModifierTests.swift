@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

/// Reflection coverage for the swipe reveal panel and modifier: the direction
/// selects the Complete/Skip label, and the idle modifier wraps its content
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
    func skipPanelShowsSkipLabel() {
        let description = String(describing: SwipeRevealPanel(outcome: .skip, progress: 1).body)
        #expect(description.contains("Skip"))
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

    @Test
    func idleModifierWrapsContentWithoutPanel() {
        let description = String(describing: swipeToActOver(Text("card")))
        #expect(description.contains("card"))
        #expect(description.contains("SwipeToActModifier"))
        #expect(!description.contains("Complete"))
        #expect(!description.contains("Skip"))
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
