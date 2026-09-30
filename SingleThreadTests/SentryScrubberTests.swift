import Foundation
import Sentry
@testable import SingleThread
import Testing

struct SentryScrubberTests {
    @Test
    func reminderContentIsRemovedFromEvent() {
        let event = Event()
        event.extra = ["reminderTitle": "Buy milk", "note": "2%"]
        event.user = User(userId: "Buy milk")
        event.tags = ["reminderTitle": "Buy milk", "environment": "debug"]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
        #expect(scrubbed?.tags?["reminderTitle"] == nil)
        #expect(scrubbed?.tags?["environment"] == "debug") // allow-listed field survives
    }

    @Test
    func reminderContentIsRemovedFromBreadcrumb() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")
        breadcrumb.message = "Buy milk from the Grocery list"
        breadcrumb.setData(value: "2%", key: "note")
        breadcrumb.setData(value: "Grocery", key: "listName")

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.data == nil)
        #expect(scrubbed?.category == "reminder") // benign structural field survives
    }
}
