import Foundation
import SingleThreadCore
import Testing

/// Serialized so these small timing-sensitive tests never interleave with
/// each other on the main actor (mirrors `CompletionGlowTests`).
@MainActor
@Suite(.serialized)
struct CompletionMomentumOverlayTests {
    @Test
    func triggerSetsActiveAndCount() {
        let overlay = CompletionMomentumOverlay()
        overlay.trigger(count: 5)
        #expect(overlay.isActive)
        #expect(overlay.todayCount == 5)
    }

    @Test
    func autoDismissAfterDuration() async {
        let overlay = CompletionMomentumOverlay()
        overlay.duration = 0.05
        overlay.trigger(count: 3)
        #expect(overlay.isActive)

        // Poll for up to ~2s for the overlay to clear. Polling is robust
        // against slow executors: we wait for the invariant rather than
        // asserting at a fixed wall-clock deadline (mirrors
        // `CompletionGlowTests.glowAutoDismissesAfterDuration`).
        for _ in 0 ..< 100 {
            if !overlay.isActive {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!overlay.isActive)
    }

    @Test
    func retriggerResetsTimer() async {
        let overlay = CompletionMomentumOverlay()
        overlay.duration = 0.10
        overlay.trigger(count: 1)
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 s — before the 0.1 s fire
        // Second trigger with a long timer: if the original dismiss task is not
        // cancelled, it fires at ~0.1 s and clears the overlay mid-poll.
        overlay.duration = 1.5
        overlay.trigger(count: 2)

        // Poll for up to ~0.5 s — well past the original timer's fire point
        // (0.1 s) and far short of the reset timer's (1.5 s). The overlay must
        // remain active the whole window, proving the re-trigger replaced the
        // pending dismiss task rather than stacking a second one.
        for _ in 0 ..< 25 {
            if !overlay.isActive {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(overlay.isActive)
        #expect(overlay.todayCount == 2)
    }

    @Test
    func defaultDuration() {
        let overlay = CompletionMomentumOverlay()
        #expect(overlay.duration == 2.0)
    }
}
