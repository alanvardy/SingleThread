# Research Questions

## Context

The iOS/macOS app presents a modal settings screen (`SettingsView`) inside a
`NavigationStack`: a root `List` of labeled `NavigationLink` rows grouped into
two headerless `Section`s, pushing one sub-view per settings group (Interface,
Notifications, Reminder, Filtering & Sorting, Background, Purchase, Privacy,
About). Settings state is owned by `SettingsBindings` and persisted via
`@AppStorage` across two `UserDefaults` stores (standard vs App Group),
triggering widget reloads and Apple Watch sync on change. Sub-screen
descriptions use `String(localized:table:bundle:)` from per-target
`.xcstrings` catalogs. The app has unit tests that assert on
`String(describing: view.body)` substrings and UI tests that match rows by
accessibility identifier.

## Questions

1. How do the settings screens (`SettingsView.swift` plus each pushed
   sub-view) structure their `List`/`Section`/`Form` rows, `#if os(iOS)`
   platform gating, `NavigationLink` rows, and any existing section
   `header`/`footer` text? Where do the root `Section`s currently sit and how
   would a per-section header caption be placed, given the root sections are
   headerless today?

2. What is the exact inventory of every setting row across all settings
   screens — the row label, its accessibility identifier, its control type
   (toggle/picker/link), and the preference model it binds to? Trace each from
   `SettingsBindings.swift` and the per-view rows through to its
   `@AppStorage` key in `ContentView.swift`, noting which keys live in App
   Group vs standard defaults, and which rows are platform-gated.

3. Where do time-based constants live that a caption would derive wording
   from at runtime — e.g. the background rotation period and the
   notification-interval hours? What are their names, types, units, and
   visibility (private vs internal), and does any existing formatter
   (e.g. `ReminderRecurrenceFormatter`) show the established pattern for
   interpolating a number into a localized string?

4. How are user-facing strings currently declared, styled, and localized
   across the settings UI? Compare hardcoded `Label("…")` strings vs
   `String(localized:table:bundle:)` calls, how section footers (e.g.
   ExcludedLists, Purchase, About) are rendered and styled, and how the
   `Localizable.xcstrings` catalogs are structured (keys, extraction state,
   plural variants, dev languages) with the `LocalizationTests` that enforce
   all six languages.

5. What automated tests exercise the settings screens and what exact strings,
   labels, and accessibility identifiers do they assert? List the unit tests
   in `SettingsViewTests.swift` (body-substring assertions), the per-pref
   `Show*Preference` tests, and the UI tests in
   `SingleThreadUITestsFlows.swift` / `NotificationsSettingsUITests.swift`
   (row identifiers, static texts, relaunch persistence) so the invariants a
   caption change could break are known.