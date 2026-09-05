@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct SettingsCaptionTests {
    @Test
    func captionRendersText() {
        let view = SettingsCaption(text: "Show the due date next to each reminder.")
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Show the due date next to each reminder."))
    }

    @Test
    func captionTextDoesNotMatchExistingLabels() {
        // Caption strings are full sentences; no label collision.
        let captions: [LocalizedStringKey] = [
            "Show the due date next to each reminder.",
            "Show which list each reminder belongs to.",
            "Show if a reminder has a time alert."
        ]
        let labels: Set = [
            "Show date", "Show list", "Reminder alerts", "Interface",
            "Reminder", "Background", "Appearance", "Text Size",
            "Sort By", "Privacy Policy", "About", "Done", "Unlock",
            "Completion glow"
        ]
        for caption in captions {
            let desc = String(describing: caption)
            for label in labels {
                #expect(
                    !desc.contains(label),
                    "Caption must not embed an existing row label: \(desc) contains \(label)")
            }
        }
    }

    @Test
    func linkLabelContainsTitleAndCaption() {
        let view = SettingsLinkLabel(
            title: "Reminder",
            systemImage: "bell.badge",
            caption: "Choose what information is shown with each reminder.")
        let bodyDescription = String(describing: view.body)
        #expect(bodyDescription.contains("Reminder"))
        #expect(bodyDescription.contains("Choose what information is shown with each reminder."))
    }
}
