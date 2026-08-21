# Research Questions

## Context

The iOS app renders its settings menu in `SingleThread/SettingsView.swift` as a
set of preference rows — `Picker` rows for Appearance, Text Size, and Sort By,
and `Toggle` rows for several boolean preferences plus an action-button flag —
alongside a pushed `ExcludedProjectsView` submenu. Each row is composed from a
`Label(text, systemImage:)` and backed by bindings that live in
`ContentView.swift`. User-facing strings and icons for the picker options come
from computed properties on SwiftUI enums (`appearanceMode`, `TextSize`, and
the `SortOption` presentation extension), while the app target also renders
descriptive strings in other places (notably an error-description property and
view constructors that take a description argument). This research maps how
these setting rows are composed, how their labels and any secondary copy are
modeled, what informational/description affordances already exist across the
SwiftUI code and SDK, and how the settings screen is previewed, unit-tested,
and accessibility/UI-tested.

## Questions

1. How is the settings menu in `SettingsView.swift` composed row by row? Trace
   the `Form` structure: how the three `Picker` rows and each `Toggle` row are
   laid out, what `Label(systemImage:)` calls style them, how `ExcludedProjectsView`
   and its `footer { Text(...) }` block are structured, and how the iOS vs
   macOS builds differ in which rows exist.

2. What user-facing text is defined on the enums and presentation extensions
   that back the settings rows? Report the `title`, `systemImage`, and any
   `subtitle`/description-like computed properties on `AppearanceMode`,
   `TextSize`, and the `SortOption` presentation extension — where each is
   declared, how cases map to strings, and whether any case currently carries
   secondary descriptive copy.

3. What informational/description affordances already exist in the SwiftUI
   codebase and its presentation APIs? Search for any tooltip, popover,
   presentation/auxiliary surface, dialog/sheet, help/footer text, or
   per-string secondary-description pattern (e.g. `DictationError.errorDescription`,
   `ContentUnavailableView`'s description argument, the `excluded` footer).
   Note which SwiftUI primitives are actually in use and any APIs available to
   the iOS target that could present supplementary text over a row.

4. How is the settings screen previewed, unit-tested, and UI/accessibility
   tested? Report which `#Preview` declarations build `SettingsView`, what
   `SettingsViewTests.swift` and `MicrophoneToggleTests.swift` assert about the
   settings body (`String(describing:)`), how headless XCTest locates settings
   rows and the Appearance picker (labels/identifiers), and which accessibility
   traits (`for: [.dynamicType, .hitRegion, ...]`) are audited on settings
   controls.

5. How is the settings sheet opened, populated, and closed in `ContentView.swift`?
   Trace the `@AppStorage` bindings passed into `SettingsView` via `.sheet`,
   the computed `excludedProjectsBinding` reading `store.excludedProjectTitles`,
   and how `dismiss()` is wired to the toolbar "Done" action.