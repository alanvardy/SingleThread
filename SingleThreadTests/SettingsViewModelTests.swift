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
        func showDateChangedDoesNotCrash() {
            let viewModel = SettingsViewModel()
            viewModel.showDateChanged(true)
            #expect(Bool(true))
        }

        @Test
        func showRecurrenceChangedDoesNotCrash() {
            let viewModel = SettingsViewModel()
            viewModel.showRecurrenceChanged(false)
            #expect(Bool(true))
        }

        @Test
        func showAlarmsChangedDoesNotCrash() {
            let viewModel = SettingsViewModel()
            viewModel.showAlarmsChanged(true)
            #expect(Bool(true))
        }
    #endif
}
