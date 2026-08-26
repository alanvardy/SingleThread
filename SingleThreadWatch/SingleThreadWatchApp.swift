import SwiftUI

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle

    init() {
        viewModel = WatchAppViewModel()
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            WatchReminderView(viewModel: viewModel.reminderViewModel)
        }
    }

    // MARK: Private

    private let viewModel: WatchAppViewModel
}
