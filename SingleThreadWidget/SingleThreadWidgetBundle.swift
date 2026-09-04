import SwiftUI
import WidgetKit

@main
struct SingleThreadWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextThingWidget()
        CompleteReminderControl()
        SkipReminderControl()
    }
}
