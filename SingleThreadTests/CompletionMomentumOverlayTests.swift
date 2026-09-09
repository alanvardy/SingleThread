import Foundation
import SingleThreadCore
import Testing

@MainActor
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
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
        #expect(!overlay.isActive)
    }

    @Test
    func retriggerResetsTimer() async {
        let overlay = CompletionMomentumOverlay()
        overlay.duration = 0.20
        overlay.trigger(count: 1)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
        overlay.trigger(count: 2)
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 s — past original fire (0.2 s), before reset (0.3 s)
        #expect(overlay.isActive)
        #expect(overlay.todayCount == 2)
    }

    @Test
    func defaultDuration() {
        let overlay = CompletionMomentumOverlay()
        #expect(overlay.duration == 2.0)
    }
}
