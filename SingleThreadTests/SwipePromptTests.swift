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
        // The hints sit on an adaptive plate (mid-light grey in light mode,
        // dark grey in dark mode) with the skip hint orange and the complete
        // hint green (the swipe actions' own tint colors). The
        // filled shape is drawn by `CardPlateModifier` — SwiftUI does not inline
        // a ViewModifier's body into the host view's static type, so the presence
        // of the modifier in the reflected chain pins the plate composition.
        #expect(description.contains("CardPlateModifier"))
        #expect(description.contains("style: orange"))
        #expect(description.contains("style: green"))
        #expect(description.contains("Dismiss"))
    }

    @Test
    func promptHiddenWhenDisabled() {
        let description = String(describing: makeCard(showSwipePrompt: false).body)
        #expect(!description.contains("Swipe left to skip"))
    }

    /// The prompt box uses the adaptive `promptBoxFill(for:)` decision so the
    /// coloured hints read against both the off-white (light) and black (dark)
    /// card plates. The rendered paint can't be asserted headlessly, so the
    /// decision is asserted directly (same rationale as `plateFill`).
    @Test
    func promptBoxFillDarkGreyInDarkMode() {
        #expect(CardPlate.promptBoxFill(for: .dark) == Color(red: 0.16, green: 0.17, blue: 0.18))
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
