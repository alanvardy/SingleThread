import SingleThreadCore
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
    }

    // MARK: Private

    @Environment(\.openURL)
    private var openURL

    @State private var viewModel = AppViewModel()
    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system

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
