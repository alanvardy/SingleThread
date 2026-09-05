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
                .task { await viewModel.drainPendingReminderAction() }
        }
    }

    // MARK: Private

    private let viewModel: WatchAppViewModel
}
