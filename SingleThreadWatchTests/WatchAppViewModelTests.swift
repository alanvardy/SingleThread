import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch composition root: the root reminder view model must be a
/// single stable instance (not rebuilt per access) so the completion-glow UI
/// seam can extend the duration on the same object the view renders.
@MainActor
struct WatchAppViewModelTests {
    @Test
    func reminderViewModelIsStableAcrossAccesses() {
        let appViewModel = WatchAppViewModel()
        let first = appViewModel.reminderViewModel
        let second = appViewModel.reminderViewModel
        #expect(
            first === second,
            "Computed → stored: view model must return the same instance")
    }

    @Test
    func glowUITestSeamExtendsDuration() {
        let appViewModel = WatchAppViewModel(arguments: ["--ui-testing-glow"])
        #expect(appViewModel.isGlowUITesting)
        #expect(
            appViewModel.reminderViewModel.completionGlow.duration == 2.0,
            "The seam must extend the glow to 2 s so waitForExistence is deterministic")
    }
}
