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
    // MARK: Lifecycle

    init() {
        SentryBootstrap.startIfEnabled()
        _viewModel = State(initialValue: AppViewModel())
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
                appViewModel: viewModel)
                .environment(\.openURL, linkOpenURLAction)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
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
            MenuBarExtra(
                "SingleThread",
                systemImage: "checkmark.circle",
                isInserted: $showMenuBarExtra) {
                    MenuBarExtraOptions(store: viewModel.store)
                        .environment(\.locale, AppLocaleState.current.effectiveLocale)
                }
                .menuBarExtraStyle(.menu)
        #endif
    }

    // MARK: Private

    @Environment(\.openURL)
    private var openURL

    @State private var viewModel: AppViewModel
    #if os(macOS)
        @AppStorage("appearanceMode")
        private var appearanceMode = AppearanceMode.system

        @AppStorage(MenuBarExtraPreference.key)
        private var showMenuBarExtra = MenuBarExtraPreference.defaultValue
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

    /// Routes inline `Text` link taps through the same injectable opener the
    /// deep link uses, so `--url-opener-spy` records them. `openURL` here is the
    /// action installed *above* this App (read at App level, so unaffected by the
    /// modifier below); `SystemURLOpener` wraps that captured original, which is
    /// what would recurse if we forwarded to the newly installed action instead.
    private var linkOpenURLAction: OpenURLAction {
        let original = openURL
        return OpenURLAction { url in
            viewModel.resolvedURLOpening(openURLAction: original).open(url)
            return .handled
        }
    }
}
