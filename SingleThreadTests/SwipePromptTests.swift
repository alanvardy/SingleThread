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
        #expect(description.contains("← Swipe left to skip"))
        #expect(description.contains("Dismiss"))
    }

    @Test
    func promptHiddenWhenDisabled() {
        let description = String(describing: makeCard(showSwipePrompt: false).body)
        #expect(!description.contains("← Swipe left to skip"))
    }

    @Test
    func dismissButtonHasAccessibilityLabel() {
        let description = String(describing: makeCard(showSwipePrompt: true).body)
        // SwiftUI never serializes accessibility label *strings* through
        // `String(describing:)` (see ActionButtonTests), but it does reflect the
        // `AccessibilityAttachmentModifier` around the button. This confirms the
        // Dismiss button carries an accessibility attachment; the label value
        // itself is asserted by the Phase 4 UI test via `app.buttons["Dismiss
        // swipe prompt"]`.
        #expect(description.contains("Button<Text>, AccessibilityAttachmentModifier"))
    }

    // MARK: Private

    private func makeCard(showSwipePrompt: Bool) -> ReminderCardView {
        ReminderCardView(
            display: ReminderDisplay(title: "Buy groceries"),
            showDate: true,
            showSwipePrompt: .constant(showSwipePrompt))
    }
}
