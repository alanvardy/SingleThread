#if os(macOS)
    import EventKit
    @testable import SingleThread
    import SingleThreadCore
    import Testing

    @Suite(.serialized)
    @MainActor
    struct MenuBarExtraOptionsTests {
        // MARK: Internal

        @Test
        func rendersNextReminderActions() {
            let store = seededStore()
            let output = String(describing: MenuBarExtraOptions(store: store).body)
            #expect(output.contains("Buy groceries"))
            #expect(output.contains("Complete Reminder"))
            #expect(output.contains("Skip Reminder"))
            #expect(output.contains("Open SingleThread"))
        }

        @Test
        func rendersNothingWhenNoReminderDue() {
            let store = ReminderStore(
                eventStore: InMemoryEventStore(reminders: [], calendars: []),
                loadsReminders: false,
                entitlementStore: EntitlementStore(testingWithEntitled: true))
            let output = String(describing: MenuBarExtraOptions(store: store).body)
            #expect(!output.contains("Complete Reminder"))
            #expect(!output.contains("Skip Reminder"))
            #expect(!output.contains("Open SingleThread"))
        }

        // MARK: Private

        private func seededStore() -> ReminderStore {
            let inMemoryStore = InMemoryEventStore(reminders: [], calendars: [])
            let reminder = inMemoryStore.makeReminder(
                title: "Buy groceries",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            return ReminderStore(
                eventStore: inMemoryStore,
                loadsReminders: false,
                reminders: [reminder],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                entitlementStore: EntitlementStore(testingWithEntitled: true))
        }
    }
#endif
