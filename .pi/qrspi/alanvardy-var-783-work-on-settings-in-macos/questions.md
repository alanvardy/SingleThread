# Research Questions

## Context

Focus on the single shared SwiftUI settings surface that ships on both iOS and
macOS from one application target (`SingleThread/`). Relevant areas: the
settings sheet's presentation path in `ContentView.swift` /
`ContentView+Settings.swift`, the `SettingsView` navigation stack and its
pushed sub-settings views (`InterfaceSettingsView`, `BackgroundSettingsView`,
`FilterSortSettingsView`, `ReminderSettingsView`, `NotificationsSettingsView`,
`PurchaseSettingsView`, `PrivacySettingsView`, `ExcludedListsView`,
`AboutView`), the `SettingsBindings`/`SettingsViewModel` data flow, the shared
card/plate styling containers, and the existing unit + UI test coverage for
settings. No specific behavior change is implied — only how these pieces
currently work on each platform.

## Questions

1. Trace the full presentation path of the settings surface from the gear
   button in `ContentView` through the `.sheet(isPresented:)`,
   `settingsSheetContent`, `settingsSheetWritebacks`, and the macOS-only
   `.frame(minWidth: 400, minHeight: 500)` modifier into `SettingsView`. How
   does macOS size and position a sheet presented from the main window, and
   what determines the height of the presented (root) settings view per
   platform?

2. How does `SettingsView` construct its `NavigationStack { List { ... } }`
   hierarchy — enumerate every `NavigationLink` destination and its platform
   gating (`#if os(iOS)` sections/rows versus macOS), and describe the shared
   shape of each pushed sub-settings view (which use `Form`, which `List`,
   which `.navigationTitle(_:)`, and which add `.toolbar` items)?

3. How does the stock macOS `NavigationStack` inside a sheet render the
   navigation bar (title + back button) for pushed views whose content is
   shorter than the available frame — what layout rules determine the vertical
   position of the nav bar, and how does that differ from iOS? Note any
   existing macOS-specific layout workarounds in this codebase (alignment
   modifiers, ScrollView wrapping, min-frames, `navigationBarTitleDisplayMode`
   analogues, custom toolbar overlays) that interact with nav-bar placement.

4. Map every compile-time platform split in the settings data flow:
   `makeSettingsBag` and `settingsSheetWritebacks` in `ContentView+Settings.swift`
   and any `#if os(iOS)` / `#if os(macOS)` branches in the settings and
   sub-settings views. Which binding values, rows, and behaviors exist on each
   platform, and how does a sub-view receive its bindings (full bag vs. focused
   `@Binding` subsets)?

5. How do the shared card/plate containers (`CardPlate`, `CardPlateModifier`,
   `ControlPlateModifier`, `EmptyStateCard`) define content alignment, sizing,
   and background styling, and is any of that styling applied to the settings
   surface on macOS (sheet/window chrome, list background, row plates) as
   opposed to the main reminder content?

6. How are the settings screen and its submenus covered by tests — which unit
   tests (Swift Testing) assert on `SettingsView`/sub-views, which UI tests
   (XCTest) open and navigate settings, which simulator destinations those
   tests run on (is macOS a test destination?), and what `--ui-testing` /
   `--seed` launch-argument seams exist for driving the settings sheet
   deterministically?