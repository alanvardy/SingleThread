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
    func parsesLongTitlesWithoutTruncation() {
        // 500-character plain title and a >500-character title containing code
        // spans: the Codable seed path must accept arbitrarily long titles
        // (no length truncation at the parser surface).
        let longPlain = String(repeating: "a", count: 500)
        let longCodeSpan = String(repeating: "word `code` ", count: 45)
        let seed = UITestingSeed.fromLaunchArguments([
            "--seed",
            #"{"reminders":[{"title":"\#(longPlain)"},{"title":"\#(longCodeSpan)"}]}"#
        ])

        #expect(seed?.reminders.count == 2)
        #expect(seed?.reminders[0].title == longPlain)
        #expect(seed?.reminders[1].title == longCodeSpan)
    }

    @Test
    func parsesCalendarsAndExcludedLists() {
        let args = [
            "--seed",
            #"{"reminders":[{"title":"A"}],"calendars":["Groceries","Work"],"excludedLists":["Work"]}"#
        ]
        let seed = UITestingSeed.fromLaunchArguments(args)

        #expect(seed?.calendars.map(\.title) == ["Groceries", "Work"])
        #expect(seed?.excludedListTitles == ["Work"])
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

    @Test
    func resetPersistedStateClearsBackgroundEnabled() {
        UserDefaults.standard.set(false, forKey: "backgroundEnabled")
        UITestingSeed.resetPersistedState()
        #expect(UserDefaults.standard.object(forKey: "backgroundEnabled") == nil)
    }
}
