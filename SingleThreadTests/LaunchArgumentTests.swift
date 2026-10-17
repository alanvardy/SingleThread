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

    @Test
    func openSettingsReminderIsDetectedAmongOtherFlags() {
        #expect(
            LaunchArgument.isPresent(
                .openSettingsReminder,
                in: ["--ui-testing", "--ui-testing-open-settings-reminder"]))
    }

    @Test
    func openSettingsReminderIsAbsentWhenNotPassed() {
        #expect(!LaunchArgument.isPresent(.openSettingsReminder, in: []))
        #expect(!LaunchArgument.isPresent(.openSettingsReminder, in: ["--ui-testing-open-settings"]))
    }

    @Test
    func openSettingsAndOpenSettingsReminderAreDistinctFlags() {
        #expect(!LaunchArgument.isPresent(.openSettings, in: ["--ui-testing-open-settings-reminder"]))
        #expect(!LaunchArgument.isPresent(.openSettingsReminder, in: ["--ui-testing-open"]))
        #expect(
            !LaunchArgument.isPresent(
                .openSettingsReminder, in: ["ui-testing-open-settings-reminder"]))
    }

    @Test
    func opensSettingsIsTrueForEitherSettingsSeam() {
        #expect(LaunchArgument.opensSettings(in: ["--ui-testing-open-settings"]))
        #expect(LaunchArgument.opensSettings(in: ["--ui-testing-open-settings-reminder"]))
        #expect(!LaunchArgument.opensSettings(in: ["--ui-testing"]))
        #expect(!LaunchArgument.opensSettings(in: []))
    }
}
