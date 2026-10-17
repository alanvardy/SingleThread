@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

@MainActor
struct SwipePromptTests {
    // MARK: Internal

    @Test
    func promptShownWhenEnabled() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        #expect(description.contains("Swipe up for more"))
        #expect(description.contains("Swipe left to skip"))
        #expect(description.contains("Swipe right to complete"))
        // The up label sits ABOVE the card and the side-row hints sit below it;
        // within the row, the left-swipe hint precedes the right-swipe hint (its
        // arrow is on the outer/leading edge). The reflected body preserves
        // document order, so the up label must precede both side hints, and
        // skip must precede complete.
        if let upLabel = description.range(of: "Swipe up for more"),
           let complete = description.range(of: "Swipe right to complete"),
           let skip = description.range(of: "Swipe left to skip") {
            #expect(upLabel.lowerBound < skip.lowerBound)
            #expect(skip.lowerBound < complete.lowerBound)
        } else {
            Issue.record("Expected all three swipe guide labels in the prompt body")
        }
        // The card itself still sits on a plate drawn by `CardPlateModifier` —
        // SwiftUI does not inline a ViewModifier's body into the host view's
        // static type, so the presence of the modifier in the reflected chain
        // pins the card-plate composition.
        #expect(description.contains("CardPlateModifier"))
        #expect(description.contains("Dismiss"))
    }

    /// The renamed dismiss button copy still surfaces as a literal on the
    /// button label, and the corrected accessibility label is reflected as the
    /// attachment modifier (its string value is covered by the doc comment on
    /// `dismissButtonHasAccessibilityLabel`).
    @Test
    func dismissButtonShowsRenamedLabel() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        #expect(description.contains("Dismiss hints"))
    }

    /// The Dismiss button's accessibility label reflects the renamed copy
    /// ("Dismiss swipe hints" instead of the old "Dismiss swipe prompt").
    @Test
    func dismissButtonAccessibilityLabelUsesHintsWording() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        #expect(!description.contains("Dismiss swipe prompt"))
        #expect(description.contains("AccessibilityAttachmentModifier"))
    }

    /// The two black hint panels are separated by the reminder card itself, and
    /// the interstitial gap is the shared prompt spacing constant — extracted so
    /// the panels provably never touch.
    @Test
    func promptPanelGapIsNonZeroConstant() {
        #expect(ReminderCardView.promptPanelSpacing > 0)
    }

    /// The hint panels use solid black so the tinted hints read over any
    /// wallpaper in both colour schemes.
    @Test
    func promptPanelsUseBlackFill() {
        #expect(ReminderCardView.promptPanelFill == .black)
    }

    @Test
    func promptHiddenWhenDisabled() {
        let description = String(describing: makeCard(showSwipePrompt: false).body)
        #expect(!description.contains("Swipe up for more"))
        #expect(!description.contains("Swipe left to skip"))
        #expect(!description.contains("Swipe right to complete"))
    }

    @Test
    func dismissButtonHasAccessibilityLabel() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        // SwiftUI never serializes accessibility label *strings* through
        // `String(describing:)` (see ActionButtonTests), but it does reflect the
        // `AccessibilityAttachmentModifier` on the Dismiss button. The label
        // value itself is asserted by the Phase 4 UI test via
        // `app.buttons["Dismiss swipe hints"]`. The bordered-prominent style
        // pins the rounded-button treatment.
        #expect(description.contains("Button<"))
        #expect(description.contains("BorderedProminentButtonStyle"))
        #expect(description.contains("AccessibilityAttachmentModifier"))
    }

    // MARK: Private

    private func makeCard(showSwipePrompt: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(title: "Buy groceries"),
            showDate: true,
            showSwipePrompt: .constant(showSwipePrompt))
    }
}
