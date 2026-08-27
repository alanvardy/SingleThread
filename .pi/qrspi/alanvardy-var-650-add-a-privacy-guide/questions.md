# Research Questions

## Context

The iOS app presents a modal settings screen (`SettingsView`) that pushes
themed sub-views (Interface, Reminder, Filtering & Sorting, Background, and
nested Excluded Lists) from a root `List` inside a `NavigationStack`. The app
target builds for both iOS and macOS in a single Swift file tree with
platform `#if` gating; watchOS and a widget are separate targets. There is no
localization (strings are hardcoded). The app reads Apple Reminders through
EventKit, persists display preferences in two `UserDefaults` tiers, syncs some
state to the Watch via WatchConnectivity, and caches a background image on
disk under Application Support.

## Questions

1. How are the pushed settings sub-views declared and surfaced from
   `SingleThread/SettingsView.swift`'s root `List` inside its `NavigationStack`?
   Describe the `NavigationLink` + `Label` row pattern, each sub-view's
   `.navigationTitle`, the platform `#if` gating (iOS-only vs iOS+macOS), and
   how `ExcludedListsView` is nested under `FilterSortSettingsView` inside a
   `Section`. Note which sub-views use `Form` vs `List` and how footers/long
   text are currently rendered (e.g. `ExcludedListsView`'s footer and
   `BackgroundSettingsView`'s photo-credit `Link`).

2. What user data does the app actually read, store, and transmit, and across
   which tiers/filesystems? Trace the EventKit reads/writes in
   `ReminderStore`, the two `UserDefaults` persistence tiers (`@AppStorage` on
   `.standard` vs `AppGroup.defaults` — which keys live where), the
   `BackgroundImageStore` file cache under Application Support, and exactly
   what `SkippedReminderSyncService` pushes/receives via WatchConnectivity
   (which values and in which direction). Identify what, if anything, leaves
   the user's device.

3. What patterns exist for rendering explanatory text, footnotes, and
   external `Link`s that a long-form privacy/transparency screen could reuse?
   Specifically, how is the Unsplash photo credit rendered in
   `BackgroundSettingsView`, how is multi-line `Text` used in `Form` Section
   footers, and how are SF Symbols chosen for settings rows? Note that no
   localization infrastructure exists (no `Localizable.strings`/`.xcstrings`).

4. Which automated tests assert on the settings screen and its sub-views, and
   what exact labels/strings do they depend on? List the unit tests
   (`SettingsViewTests`) and UI tests (`testSettingsOpensAndShowsControls`,
   toggle-persistence relaunch tests, appearance tests, and the accessibility
   audit `testAccessibilityAudit`) with their file paths and the exact label
   strings they look up — so we know which invariants (existing top-level
   labels, accessibility categories) a change that ADDs a new row or sub-view
   to Settings would or would not break.