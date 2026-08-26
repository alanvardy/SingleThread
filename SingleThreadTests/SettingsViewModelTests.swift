@testable import SingleThread
import Testing

@MainActor
struct SettingsViewModelTests {
    @Test
    func initializesWithoutCrash() {
        _ = SettingsViewModel()
        #expect(Bool(true))
    }

    #if os(iOS)
        @Test
        func allowsLandscapeChangedDoesNotCrash() {
            let viewModel = SettingsViewModel()
            viewModel.allowsLandscapeChanged(true)
            viewModel.allowsLandscapeChanged(false)
            #expect(Bool(true))
        }
    #endif

    #if os(iOS) || os(macOS)
        @Test
        func showPreferenceChangedDoesNotCrash() {
            let viewModel = SettingsViewModel()
            viewModel.showPreferenceChanged()
            #expect(Bool(true))
        }
    #endif
}
