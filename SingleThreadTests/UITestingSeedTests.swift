import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

// MARK: - UITestingSeed parsing

@MainActor
@Suite(.serialized)
struct UITestingSeedTests {
    @Test
    func parsesRemindersFromCompactJSON() {
        let args = [
            "--seed",
            #"{"reminders":[{"title":"Buy groceries","notes":"milk"},{"title":"Call mom","priority":1}]}"#
        ]
        let seed = UITestingSeed.fromLaunchArguments(args)

        #expect(seed != nil)
        #expect(seed?.reminders.count == 2)
        #expect(seed?.reminders[0].title == "Buy groceries")
        #expect(seed?.reminders[0].notes == "milk")
        #expect(seed?.reminders[1].priority == 1)
    }

    @Test
    func parsesCalendarsAndExcludedProjects() {
        let args = [
            "--seed",
            #"{"reminders":[{"title":"A"}],"calendars":["Groceries","Work"],"excludedProjects":["Work"]}"#
        ]
        let seed = UITestingSeed.fromLaunchArguments(args)

        #expect(seed?.calendars.map(\.title) == ["Groceries", "Work"])
        #expect(seed?.excludedProjectTitles == ["Work"])
    }

    @Test
    func returnsNilWhenSeedAbsentOrMalformed() {
        #expect(UITestingSeed.fromLaunchArguments([]) == nil)
        #expect(UITestingSeed.fromLaunchArguments(["--seed"]) == nil)
        #expect(UITestingSeed.fromLaunchArguments(["--seed", "not json"]) == nil)
        #expect(UITestingSeed.fromLaunchArguments(["--seed", #"{"reminders":["oops"]}"#]) == nil)
    }

    @Test
    func inMemoryStoreRendersSeededRemindersThroughStore() async {
        let args = ["--seed", #"{"reminders":[{"title":"Buy groceries"}]}"#]
        guard let seed = UITestingSeed.fromLaunchArguments(args) else {
            Issue.record("seed did not parse")
            return
        }
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: seed.reminders, calendars: seed.calendars),
            loadsReminders: true)
        await store.start()

        #expect(store.authorizationStatus == .fullAccess)
        #expect(store.visibleReminders.map(\.title) == ["Buy groceries"])
    }
}
