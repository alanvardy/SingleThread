# Research Questions

## Context

The SingleThread iOS app is a SwiftUI reminders client whose preference surface
lives in a modal `SettingsView` sheet. The text-size preference is modeled as a
`String, CaseIterable` enum (`TextSize`) with five cases (system, small, medium,
large, extraLarge), each mapping to a SwiftUI `DynamicTypeSize`. The stored value
is persisted via `@AppStorage` on `ContentView` and applied to the view hierarchy
through a `TextSizeModifier` view modifier. This research maps how those enum
values translate to real framework text sizes, how a setting flows from the picker
to persistence and then to the applied hierarchy, how fixed `.font(...)` sizes
compose with Dynamic Type scaling, and how the choice is currently tested and
previewed.

## Questions

1. What `DynamicTypeSize` values does the SwiftUI framework expose, and what are
   the actual rendered point sizes / relative scale differences between the steps
   in use (`.small`, `.medium`, `.large`, `.xLarge`) and any adjacent ones the
   framework offers (e.g. `.xSmall`, `.default`, `.xxLarge`)? What is the full
   smallest-to-largest range available at this layer?

2. How is the `TextSize` preference declared, persisted, and decoded? Trace the
   `@AppStorage("textSize")` property on `ContentView` — its storage key, default
   value, and how the `String, CaseIterable` enum encodes to and decodes from the
   stored raw string, including whether the `.system` default round-trips.

3. How does a selection in the "Text Size" `Picker` flow back to the app's text
   rendering? Trace the `Binding<TextSize>` passed from `ContentView` into the
   `SettingsView` sheet, the `Picker`/`ForEach(TextSize.allCases, ...)` labels
   and tags, and how `TextSizeModifier` conditionally applies `dynamicTypeSize`
   across the hierarchy (including the `.system` case, which applies none).

4. How does text sizing compose with the rest of the `ContentView` hierarchy?
   Which SwiftUI constructs already set explicit `.font(...)` text styles (e.g.
   `.caption`, `.callout`, `.title`, `.title2` on cards, bars, and the dictation
   UI), and how do those fixed sizes interact with a Dynamic Type override applied
   at the top level?

5. What unit tests, canvas previews, and accessibility checks cover the
   `TextSize` preference and its value mappings? Describe `TextSizeTests.swift`,
   the `TextSizeModifier` behavior, the `SettingsView` previews (Default / Dark +
   Extra Large), and any SwiftLint or accessibility rules that constrain dynamic
   type or font sizing.