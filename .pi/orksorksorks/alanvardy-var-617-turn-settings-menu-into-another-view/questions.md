# Research Questions

## Context

Focus on the `SingleThread` Xcode project: the iOS/macOS app sources
(especially `ContentView` and the settings-related type files), the shared
`SingleThreadCore` package, the watch app target, and the unit/UI test suites.
Investigate how the app's single SwiftUI scene presents its content, what
navigation and presentation mechanisms exist (or don't) across all targets,
how the main view layers its interface and binds persisted user preferences,
how those preferences flow into appearance, orientation, and dynamic-type
effects, how platform-specific code is conditionalized, how views are factored
into separate types and files, and how the view and its controls are tested and
previewed.

## Questions

1. What navigation infrastructure exists anywhere in the codebase —
   `NavigationStack`, `NavigationLink`, `NavigationView`, sheets, or any
   presentation/dismissal state? Trace how the single `WindowGroup` scene
   presents `ContentView`, and whether any view (including
   `SingleThreadWatch/WatchReminderView.swift`) pushes, presents, or dismisses
   another view today.

2. How does `ContentView` compose and layer its interface? Trace its `body`:
   the `ZStack`, the `.overlay(alignment: .topTrailing)` that hosts the
   gear-shaped settings `Menu`, how that `Menu`'s `Picker` and `Toggle` items
   are constructed, and how the `@AppStorage`-backed preferences
   (`appearanceMode`, `textSize`, `allowsLandscape`, `showMicrophoneButton`) are
   bound into that UI.

3. How are the settings preferences applied to the surrounding view hierarchy?
   Trace `AppearanceMode.colorScheme` into `.preferredColorScheme`,
   `TextSize.dynamicTypeSize` into `TextSizeModifier`/`.dynamicTypeSize`, and
   `allowsLandscape` into `AppDelegate.applyLock` and
   `supportedInterfaceOrientationsFor`, including where persisted `UserDefaults`
   values are read at launch to avoid a wrong-orientation flash.

4. What shape and conventions do the settings option enums (`AppearanceMode`,
   `TextSize`) use? What protocol conformances, computed properties, and
   `@AppStorage` key naming do they rely on, and where are those keys
   referenced elsewhere in the app (for example `AppDelegate`)?

5. How does the codebase conditionalize behavior per platform
   (`#if os(iOS)` / `#if os(macOS)`)? Which targets compile `ContentView`, and
   which settings-related controls or behaviors are gated by platform — such as
   the landscape toggle and the macOS action buttons?

6. How are views extracted and organized into separate types and files in this
   codebase? What conventions exist for factoring UI (private `some View`
   computed properties, `private struct … : ViewModifier` at file bottom,
   standalone view files like `WatchReminderView.swift`), and how does the
   Xcode project's synchronized file group discover newly added source files?

7. How is `ContentView` — and the settings menu specifically — tested? Trace
   what `MicrophoneToggleTests` asserts and the `String(describing: view.body)`
   technique it uses, what `AppDelegateTests` covers, what the UI accessibility
   audit checks, and how previews and mock reminders are constructed.