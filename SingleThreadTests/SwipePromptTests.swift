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
        #expect(description.contains("Swipe left to skip"))
        #expect(description.contains("Swipe right to complete"))
        // The two hints stack, complete above skip, so the caption no longer
        // truncates on narrow phones. Skim the source order: the reflected body
        // preserves document order, so the "complete" label must precede the
        // "skip" label.
        if let complete = description.range(of: "Swipe right to complete"),
           let skip = description.range(of: "Swipe left to skip") {
            #expect(complete.lowerBound < skip.lowerBound)
        } else {
            Issue.record("Expected both swipe hint labels in the prompt body")
        }
        // The prompt sits on a separate plate BELOW the card sharing the card
        // fill (off-white light / black dark), with adaptive hint colours
        // (darkened orange/green in light mode, semantic orange/green in dark
        // mode). The filled shape is drawn by `CardPlateModifier` — SwiftUI
        // does not inline a ViewModifier's body into the host view's static
        // type, so the presence of the modifier in the reflected chain pins
        // the plate composition.
        #expect(description.contains("CardPlateModifier"))
        #expect(description.contains("Dismiss"))
    }

    @Test
    func promptHiddenWhenDisabled() {
        let description = String(describing: makeCard(showSwipePrompt: false).body)
        #expect(!description.contains("Swipe left to skip"))
    }

    @Test
    func dismissButtonHasAccessibilityLabel() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        // SwiftUI never serializes accessibility label *strings* through
        // `String(describing:)` (see ActionButtonTests), but it does reflect the
        // `AccessibilityAttachmentModifier` on the Dismiss button. The label
        // value itself is asserted by the Phase 4 UI test via
        // `app.buttons["Dismiss swipe prompt"]`. The bordered-prominent style
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
