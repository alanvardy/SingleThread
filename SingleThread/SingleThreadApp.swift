import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main
struct SingleThreadApp: App {
    // MARK: Lifecycle

    init() {
        viewModel = AppViewModel()
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel.contentViewModel)
        }
    }

    // MARK: Private

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
    #endif

    private let viewModel: AppViewModel
}
