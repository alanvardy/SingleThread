import AppIntents
import SingleThreadCore
import SwiftUI
import WidgetKit

// MARK: - Complete

struct CompleteReminderControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CompleteReminder") {
            ControlWidgetButton(action: CompleteReminderIntent()) {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
            }
        }
        .displayName(SharedStrings.completeActionResource)
    }
}

// MARK: - Skip

struct SkipReminderControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SkipReminder") {
            ControlWidgetButton(action: SkipReminderIntent()) {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
            }
        }
        .displayName(SharedStrings.skipActionResource)
    }
}
