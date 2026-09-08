# Research Questions

## Context

The codebase under study is a SwiftUI iOS (plus watchOS, widget, macOS) app in
`SingleThread/`, `SingleThreadCore/`, `SingleThreadWatch/`, `SingleThreadWidget/`,
`SingleThreadTests/`, and `SingleThreadUITests/`, built with Xcode 26 / Swift 6 and
deployed to the local iOS Simulator. The iOS surface is `ContentView` under a
`WindowGroup` in a SwiftUI `App`, bridged to UIKit through an `AppDelegate`
registered via `@UIApplicationDelegateAdaptor`. This research focuses on the iOS
app's launch path, its foreground/activation lifecycle, the EventKit/Reminders
access flow that can fire during startup, how the simulator launches apps, and how
the XCTest UI-test infrastructure launches the app. Each question should be answered
by reading the actual code, entitlements, project/scheme configuration, and shell
scripts, not by speculation.

## Questions

1. Trace the iOS app's launch and activation lifecycle. How and when does UIKit
   wake the SwiftUI `App` — which SwiftUI/UIKit callbacks fire in what order
   (`applicationDidBecomeActive`, `applicationWillEnterForeground`, the
   `@UIApplicationDelegateAdaptor`, `didFinishLaunchingWithOptions`, scene/window
   presentation), and what drives an app into the active/foreground state rather
   than merely running? Where in this lifecycle is `AppDelegate.applyAppearance`
   invoked?

2. What happens on the EventKit/Reminders access path at startup? Trace
   `ReminderStore.init`/`start()`, `requestAccess()`, and
   `requestFullAccessToReminders()` — what OS-level permission (TCC) prompt is
   triggered, when, and what happens if it is unresolved or cannot render? How do
   `loadsReminders`, the `--ui-testing` launch argument, the App Group identifier in
   `AppGroup.swift`, and `INFOPLIST_KEY_NSRemindersUsageDescription` each interact
   with that prompt's firing?

3. How does the iOS Simulator install and launch installed apps headlessly? Describe
   the `simctl` device/launch/dashboard surface (boot, bootstatus, launch, erase,
   screenshot) for the configured devices and runtimes (e.g. `iPhone 17`, `iPad (A16)`,
   iOS 26.5), and what determines whether a launched app takes the foreground versus
   stays backgrounded behind SpringBoard.

4. How do the UI tests launch and drive the app on the likely the same simulator
   device? Compare the launch paths in `SingleThreadUITests` (e.g.
   `SingleThreadUITestsLaunchTests` `app.launch()` vs `testAccessibilityAudit`
   `app.launch()` with `launchArguments = ["--ui-testing"]`), their target-config
   entitlements/`TEST_TARGET_NAME`, and `XCUIApplication`/XCTest mechanics — i.e.
   what actually performs the foregrounding in the XCTest case.

5. What project/plist/entitlements/scheme configuration governs how this app is
   built and launched for the iOS Simulator, in Debug vs Release and for test
   vs run? Cover: `SingleThread.entitlements` vs `AppGroup.entitlements`
   (`CODE_SIGN_ENTITLEMENTS` per sdk), `ENABLE_APP_SANDBOX` / `ENABLE_HARDENED_RUNTIME`
   / app groups / `REGISTER_APP_GROUPS`, `GENERATE_INFOPLIST_FILE` and injected
   `INFOPLIST_KEY_*` keys, `ProductBundleIdentifier` for `app.alanvardy.SingleThread`,
   the `SingleThread.xcscheme` LLDB launcher/debugger settings, and how launch
   arguments/`ProcessInfo.processInfo.arguments` and preprocessor/compilation
   conditions (`DEBUG=1`) alter the built app. Note any differences between the iOS
   simulator target and the macOS target.