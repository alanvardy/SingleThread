# Research Questions

## Context
This is a SwiftUI iOS/watchOS/macOS app whose single iOS main screen composes its action buttons and settings affordances inline as overlays rather than through system chrome. Research should map how the main screen view hierarchy is built, how the shared button-chrome view modifiers are defined and shared across platforms, how SwiftUI toolbar APIs are used elsewhere in the app, how the app's window/scene configuration works and whether any external-display handling exists, and how existing tests introspect these views. Focus on `SingleThread/`, `SingleThreadCore/`, `SingleThreadTests/`, `SingleThreadUITests/`, the Xcode project settings, and `scripts/`.

## Questions
1. How is the iOS main screen's view hierarchy composed — what is the root container, where does the settings gear live, where is the bottom bar/action cluster attached, and how are safe areas, overlays and padding handled? Trace the body of `ContentView` and its helper subviews with `file:line` references.
2. How are the `controlPlate` and `singleThreadButton` view modifiers defined, and how does each call site differ per platform (iOS vs macOS) — including which buttons apply which modifier and any platform conditional compilation?
3. What SwiftUI toolbar APIs (`.toolbar`, `ToolbarItem`, `ToolbarItemGroup`, placement options, `NavigationStack`/`NavigationSplitView`) are used in this codebase, and what patterns/placements do those usages follow?
4. How is the app's window/scene configuration set up (App entry point, AppDelegate/SceneDelegate, Info.plist, scene-manifest generation, orientation, `UIWindowScene` usage), and what handling — if any — exists for external displays, multiple windows, or additional `UISceneSession`s?
5. Which unit/reflection tests and UI tests assert on the main screen's buttons, settings gear, and chrome modifiers, and what introspection technique does each use (Mirror/reflection, accessibility audit, launch arguments)?
6. How is iOS- vs macOS-specific view code organized and gated in this target (separate files, `#if os(...)`, availability annotations), and what build/lint/test entry points exist for verifying iOS vs macOS builds separately?
