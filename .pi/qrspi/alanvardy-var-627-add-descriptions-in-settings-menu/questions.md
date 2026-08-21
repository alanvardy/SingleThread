# Research Questions

## Context

Focus on the `SingleThread` iOS/macOS app target's settings surface
(`SingleThread/SettingsView.swift`) and the SwiftUI (Swift 6) primitives it
composes. Trace how each settings row is currently rendered as SwiftUI content
inside a `Form` / `NavigationStack` / `Section`, the SDK's available
transient-popup and anchoring primitives, where every settings row's label
strings live today, and the platform-conditional code paths, tests, and
accessibility constraints that govern the screen.

## Questions

1. How are the settings rows currently declared in `SettingsView`? Map every
   row construct (each `Picker`, `Toggle`, `Label`, `NavigationLink`, and the
   `ExcludedProjectsView` submenu) to the SwiftUI primitives and initializer
   overloads they use, noting which use `Label(title, systemImage:)` and how
   platform guards (`#if os(iOS)`) split the iOS vs. otherwise initializers.

2. What does the SwiftUI SDK offer for attaching a supplementary, trailing
   element to a row and for invoking a transient, user-dismissable pop-up tied
   to a control? Enumerate the `SwiftUI` components and API (e.g. `Popover`,
   `Alert`, `Sheet`, `ActionSheet`, `Menu`, `Button`, `Field`, and any
   `info`/help affordance), their initializer overloads, anchoring behavior, and
   platform availability (iOS/macOS/tvOS/watchOS).

3. Where does each settings row's label string currently live, and what is the
   codebase's convention for user-facing copy and localization? Locate title
   strings on `AppearanceMode`, `TextSize`, `SortOption`, on `Label`/`Toggle`
   literals, and in the `ExcludedProjectsView` footer, and note any existing
   localization wrappers.

4. What does each existing settings preference actually do at its consumption
   site? Trace `allowsLandscape` → `AppDelegate.applyLock` /
   `supportedInterfaceOrientationsFor`, `enableActionButtons`,
   `showMicrophoneButton`, `showUndatedReminders` → `ReminderStore`,
   `showDate` → `WidgetCenter.reloadAllTimelines`, `appearanceMode` →
   `applyAppearance`, `textSize` → `TextSizeModifier`, `sortOption` →
   `setSortOption`, and `excludedProjects` → the reminder filter, so accurate
   per-setting explanations only describe implemented behavior.

5. How is the settings window tested, previewed, and constrained by
   accessibility rules? Trace `SettingsViewTests` (`String(describing:
   view.body)`, `.contains` assertions, iOS/macOS splits), the SwiftUI
   `#Preview` blocks, the SwiftLint accessibility rules
   (`accessibilityLabel_ForImage`, `accessibilityTrait_ForButton`) and the
   `XCUIApplication.performAccessibilityAudit()` row-based UI test, noting how
   new interactive affordances would be verified.

6. On which targets and platforms is `SettingsView` presented, and how does its
   sheet/`Content` presentation and `#if os`-guarded composition differ from
   other app surfaces? Trace `ContentView`'s `.sheet(isPresented:…)`,
   `isShowingSettings`, and the same file's platform-conditional branches to
   see what must hold across iPhone, iPad, and macOS.