import EventKit
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Covers the watch demo-reminder seams the App Store screenshot harness drives:
/// localized card copy and the empty state that no other watch seam reaches.
/// Serialized because constructing a `--ui-testing` view model applies the
/// action-buttons preference to the shared defaults.
@MainActor
@Suite(.serialized)
struct WatchDemoReminderTests {
    @Test
    func sampleCopyIsUsedWhenNoSeamsArePresent() {
        let demo = WatchDemoReminder.fromLaunchArguments(["--ui-testing"])
        #expect(demo.title == "Buy groceries")
        #expect(demo.notes == "Don't forget the milk")
        #expect(!demo.isEmpty)
    }

    @Test
    func titleAndNotesSeamsOverrideTheSample() {
        let demo = WatchDemoReminder.fromLaunchArguments([
            "--ui-testing",
            "--ui-testing-title", "猫に確定申告のやり方を教える",
            "--ui-testing-notes", "メモ"
        ])
        #expect(demo.title == "猫に確定申告のやり方を教える")
        #expect(demo.notes == "メモ")
    }

    @Test
    func explicitlyEmptyNotesMeansNoNotes() {
        let demo = WatchDemoReminder.fromLaunchArguments(["--ui-testing", "--ui-testing-notes", ""])
        #expect(demo.notes == nil, "An empty notes seam must drop the line, not render a blank one")
    }

    @Test
    func trailingFlagWithoutAValueFallsBackToTheSample() {
        let demo = WatchDemoReminder.fromLaunchArguments(["--ui-testing", "--ui-testing-title"])
        #expect(demo.title == "Buy groceries")
    }

    @Test
    func emptySeamYieldsTheNoRemindersState() {
        let appViewModel = WatchAppViewModel(arguments: ["--ui-testing", "--ui-testing-empty"])
        #expect(appViewModel.store.reminders.isEmpty)
        #expect(appViewModel.store.listContent == .empty(hasHidden: false))
    }

    @Test
    func titleSeamReachesTheStore() {
        let appViewModel = WatchAppViewModel(
            arguments: ["--ui-testing", "--ui-testing-title", "Teach the cat how to do my taxes"])
        #expect(appViewModel.store.reminders.first?.title == "Teach the cat how to do my taxes")
    }
}
