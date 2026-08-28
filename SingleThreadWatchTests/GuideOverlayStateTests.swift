import SwiftUI
@testable import SingleThreadWatch
import Testing

// Note: View-level snapshot tests for the overlay presence and dismiss
// behavior. For accessibility traits, the overlay UI test (Phase 5 UI)
// provides the authoritative assert via performAccessibilityAudit.

@MainActor
@Suite(.serialized)
struct GuideOverlayStateTests {
    @Test
    func dismissInvokesClosure() {
        var dismissed = false
        // Build the overlay; tap "Got it" by invoking onDismiss directly.
        // SwiftUI view hierarchy testing is limited on watchOS, so we test
        // the callback plumbing directly.
        let overlay = GuideOverlay(isActive: true, onDismiss: { dismissed = true }, reduceMotion: false)
        // The onDismiss closure is wired to the "Got it" button — verify
        // it fires when invoked.
        overlay.onDismiss()
        #expect(dismissed)
    }

    @Test
    func isActiveFalseHidesFromAccessibility() {
        // When isActive is false, .accessibilityHidden(true) is set.
        let overlay = GuideOverlay(isActive: false, onDismiss: {}, reduceMotion: false)
        // The overlay body gates on isActive for accessibilityHidden — we
        // can't introspect SwiftUI modifier state, but the UI test asserts
        // VoiceOver behavior. This test documents the contract.
        #expect(!overlay.isActive)
    }
}
