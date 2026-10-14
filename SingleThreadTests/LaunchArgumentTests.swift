@testable import SingleThread
import Testing

// MARK: - Launch-argument seams

@MainActor
@Suite(.serialized)
struct LaunchArgumentTests {
    @Test
    func openSettingsIsDetectedAmongOtherFlags() {
        #expect(
            LaunchArgument.isPresent(
                .openSettings,
                in: ["--ui-testing", "--ui-testing-noop-settle", "--ui-testing-open-settings"]))
    }

    @Test
    func openSettingsIsAbsentWhenNotPassed() {
        #expect(!LaunchArgument.isPresent(.openSettings, in: []))
        #expect(
            !LaunchArgument.isPresent(
                .openSettings,
                in: ["--ui-testing", "--ui-testing-noop-settle"]))
    }

    @Test
    func wholeFlagMatchesSoNearMissesDoNotOpenSettings() {
        #expect(!LaunchArgument.isPresent(.openSettings, in: ["--ui-testing-open"]))
        #expect(!LaunchArgument.isPresent(.openSettings, in: ["ui-testing-open-settings"]))
    }
}
