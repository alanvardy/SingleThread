@testable import SingleThread
import Testing

@MainActor
struct SettingsViewModelTests {
    /// Crash-guard smoke test: every settings mutation is a side-effect
    /// delegation (AppDelegate lock, WidgetCenter reload) with no observable
    /// state, so init + each mutation path completing without crashing is the
    /// assertion.
    @Test
    func initializationAndMutationsDoNotCrash() {
        _ = SettingsViewModel()
        #if os(iOS)
            let landscapeViewModel = SettingsViewModel()
            landscapeViewModel.allowsLandscapeChanged(true)
            landscapeViewModel.allowsLandscapeChanged(false)
        #endif
        #if os(iOS) || os(macOS)
            let preferenceViewModel = SettingsViewModel()
            preferenceViewModel.showPreferenceChanged()
        #endif
    }
}
