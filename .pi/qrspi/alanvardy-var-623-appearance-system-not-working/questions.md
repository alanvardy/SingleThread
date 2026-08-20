# Research Questions

## Context

The SingleThread iOS app is a SwiftUI reminders client whose iOS surface is
built on `ContentView`. User preferences are declared on that root view with
`@AppStorage`, edited through a modal `SettingsView` sheet, and applied to the
view hierarchy via view modifiers. The appearance preference in particular is
represented by an `AppearanceMode` enum and applied with `.preferredColorScheme(_:)`.
This research explores how that preference is persisted, how a selection flows from
the settings sheet back to the root view, how the applied color scheme is resolved
(including the system-following case), and how appearance is currently tested.

## Questions

1. How is the `appearanceMode` preference declared and persisted? Trace the
   `@AppStorage` property on `ContentView` — its storage key, default value, and how
   the `AppearanceMode` enum decodes from and encodes to its stored raw string. What
   value is read back for each of the three cases, and does decoding ever fall back
   to a non-System case?

2. Where and how is `.preferredColorScheme(_:)` applied across the view hierarchy?
   Enumerate every call site (root `ContentView` and the `SettingsView` sheet, plus
   any others), the exact value each passes for System / Light / Dark, and how
   applying it on both the sheet and the root view interact while the sheet is
   presented and after it is dismissed.

3. How does a change in the `SettingsView` appearance picker propagate back to the
   stored value and to the views that observe it? Trace the binding chain from
   `ContentView`'s `@AppStorage` value through the `Binding<AppearanceMode>` passed
   to the sheet, and describe when the root view observes a change — while the sheet
   is open, on dismissal, or eagerly.

4. What does the `.system` case actually resolve to? Describe what
   `AppearanceMode.colorScheme` returns for each case (including the `nil`/system
   case), and how passing that value to `.preferredColorScheme(_:)` maps onto SwiftUI's
   notion of the environment/device color scheme — i.e. what "follow the system"
   means at this layer and whether it can become stale after another mode was set.

5. What testing, preview, and regression coverage currently exists for the appearance
   preference and settings changes? How are settings/modifier behaviours validated in
   unit tests, canvas previews, and UI/accessibility tests, and is there an existing
   pattern for asserting that a preference change retakes effect across modes?