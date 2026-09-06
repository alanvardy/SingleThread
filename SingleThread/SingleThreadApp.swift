import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

@main
struct SingleThreadApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
                appViewModel: viewModel)
            #if os(macOS)
                .sheet(isPresented: $showAbout) {
                    NavigationStack { AboutView() }
                }
            #endif
        }
        #if os(macOS)
        .commands {
            appCommands(
                store: viewModel.store,
                appearanceMode: $appearanceMode,
                showAbout: $showAbout)
        }
        #endif
        #if os(macOS)
            // Always-present menu-bar extra; the plan's conditional scene
            // (`if !visibleReminders.isEmpty`) crashes the Swift 6 compiler
            // (SceneBuilder expression bug), so the documented fallback applies:
            // `MenuBarExtraOptions` renders empty content when nothing is due.
            MenuBarExtra("SingleThread", systemImage: "checkmark.circle") {
                MenuBarExtraOptions(store: viewModel.store)
            }
            .menuBarExtraStyle(.menu)
        #endif
    }

    // MARK: Private

    @Environment(\.openURL)
    private var openURL

    @State private var viewModel = AppViewModel()
    #if os(macOS)
        @AppStorage("appearanceMode")
        private var appearanceMode = AppearanceMode.system
    #endif

    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self)
        private var appDelegate
    #endif
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MacAppDelegate.self)
        private var macAppDelegate
        @State private var showAbout = false
    #endif
}
