# Research Questions

## Context

The iOS app presents a modal settings screen (`SettingsView`) inside a
`NavigationStack`. That screen is currently one long `Form` with all
preferences as direct rows, plus one pushed sub-view (`ExcludedListsView`).
Settings are persisted via `@AppStorage` on several stores, and some changes
trigger widget reloads and Apple Watch sync. The watchOS app has no settings
UI of its own.

## Questions

1. How does the settings screen (`SingleThread/SettingsView.swift`) structure
   its `Form` rows, platform `#if` gating, `@Binding` plumbing, and
   `NavigationLink`/`NavigationStack` usage? Specifically, how is
   `ExcludedListsView` declared and pushed, and how are the root toolbar
   ("Done") and per-subview `navigationTitle` configured across the iOS and
   non-iOS (macOS) initializers?

2. Where are the settings state values owned and how do they flow into and out
   of the view? Trace every preference from its `@AppStorage` key (and backing
   `UserDefaults` store) in `ContentView.swift` through to the `SettingsView`
   bindings, and identify which bindings are platform-gated and which are
   synced to the Apple Watch vs phone-only.

3. What happens when a setting changes at runtime? Trace
   `SettingsViewModel`'s methods (`showPreferenceChanged`,
   `allowsLandscapeChanged`) and every `.onChange` modifier in the settings
   form — what each triggers (widget timeline reload, app lock orientation,
   watch sync via `SkippedReminderSyncService`), which settings are wired to
   them, and how those `.onChange` hooks are attached relative to their rows.

4. How do the preference value models (`AppearanceMode`, `TextSize`,
   `BackgroundFade`, `SortOption`) define their cases, presentation labels,
   and `defaultsKey`/persistence keys, and how are their picking/min-max
   mechanics (e.g. fill values, tag) rendered? Where are the presentation
   extensions that map raw values to display titles and SF Symbol images?

5. What automated tests exercise the settings screen? List the unit tests
   (`SettingsViewTests`, `SettingsViewModelTests`) and UI tests
   (`testSettingsOpensAndShowsControls`, persistence/toggle relaunch tests,
   accessibility audit) with the exact strings and labels they assert, so we
   know the invariants a change to the row layout could break.