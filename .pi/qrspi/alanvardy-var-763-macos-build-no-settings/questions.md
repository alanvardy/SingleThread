# Research Questions

## Context

This SwiftUI app ships a single application target for iOS and macOS
(`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`), with per-SDK
entitlements and compile-time `#if os(...)` branches throughout. A modal
settings screen (`SettingsView`) lives inside a `NavigationStack` presented as
a sheet from `ContentView`. The research focus is the settings screen's
cross-platform presentation and rendering, plus how the macOS variant of the
app shell and settings data get wired up.

## Questions

1. How is the settings screen constructed and presented on both platforms —
   trace the full path from the gear button in `ContentView` through
   `makeSettingsBag()` / `settingsSheetContent` / `.sheet` to `SettingsView`'s
   `NavigationStack { List { Section {...} } }` and its "Done" toolbar item?
   Where exactly does the sheet content get its bindings and observed objects,
   and what differs between the `#if os(iOS)` and `#else` branches in
   `ContentView+Settings.swift`?

2. What is the complete set of compile-time platform conditionals (`#if
   os(iOS)` / `#if os(macOS)` / `#elseif`) affecting the settings screen — in
   `SettingsView`, each settings sub-view, `SettingsBindings`, and
   `SettingsViewModel`? Which rows, fields, and behaviors exist on each
   platform, and which are intentionally omitted on macOS (and why, per any
   comments)?

3. How does the app's platform entry point and window lifecycle differ between
   iOS and macOS — `SingleThreadApp`'s `@main` body, the
   `UIApplicationDelegateAdaptor`/`NSApplicationDelegateAdaptor` split in
   `AppDelegate.swift`, whether a dedicated `Settings` scene exists, and how
   sheets are sized/hosted under macOS `WindowGroup`?

4. What runtime state does the settings screen depend on at render time —
   how are the `SettingsBindings` bag, `@AppStorage` values, `EntitlementStore`,
   `availableLists`, and the `excludedLists` binding initialized in each
   platform branch (`makeSettingsBag`, `settingsSheetWritebacks`), and could
   any of those inputs be empty/absent at first render on macOS in a way that
   isn't true on iOS?
5. How is the macOS build configured — the project file's per-SDK
   `CODE_SIGN_ENTITLEMENTS`, the `SingleThread.entitlements` vs
   `AppGroup.entitlements` contents, scheme launch settings, and which code
   paths are exercised on macOS (StoreKit IAP, WidgetKit, notifications) vs
   iOS?
6. How are the settings screen covered by tests — unit tests
   (`SettingsViewTests`, assertions on the row labels), UI tests (the
   settings-open flow in `SingleThreadUITestsFlows`), which destinations those
   tests run on, and what `--ui-testing` / `--seed` launch-argument seams exist
   for driving the settings sheet deterministically?