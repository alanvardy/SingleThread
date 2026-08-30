import EventKit
import SingleThreadCore
import Testing

@MainActor
struct UndoStoreTests {
    // MARK: Internal

    @Test
    func hasUndoableReminderFalseInitially() {
        let store = UndoStore()
        #expect(!store.hasUndoableReminder)
        #expect(store.lastCompletedReminder == nil)
    }

    @Test
    func retainStoresReminder() {
        let store = UndoStore()
        let reminder = makeReminder()
        store.retain(reminder)
        #expect(store.lastCompletedReminder === reminder)
        #expect(store.hasUndoableReminder)
    }

    @Test
    func clearNilsReminder() {
        let store = UndoStore()
        store.retain(makeReminder())
        store.clear()
        #expect(store.lastCompletedReminder == nil)
        #expect(!store.hasUndoableReminder)
    }

    @Test
    func retainOverwritesPrevious() {
        let store = UndoStore()
        let first = makeReminder()
        let second = makeReminder()
        store.retain(first)
        store.retain(second)
        #expect(store.lastCompletedReminder === second)
        #expect(store.lastCompletedReminder !== first)
    }

    // MARK: Private

    /// Uses a single shared EKEventStore (construction only, never saved).
    private let eventStore = EKEventStore()

    private func makeReminder() -> EKReminder {
        let rem = EKReminder(eventStore: eventStore)
        rem.title = "Test"
        return rem
    }
}
