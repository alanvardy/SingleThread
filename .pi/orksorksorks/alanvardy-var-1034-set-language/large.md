# Task

Add a "language" dropdown to the Interface section of the iOS/macOS settings
screen (`InterfaceSettingsView`; see linear issue VAR-1034, "Set language"),
letting the user pick a display language and persist that preference. The
picked language must then actually drive the app's displayed strings and
locale-sensitive rendering, not just sit as an inert stored value.

The app already ships 6-language `.xcstrings` catalogs (en, zh-Hans, es, ja, de,
fr) consumed via Foundation's `String(localized:)` API, but today it renders in
the **system locale** — there is no user-selectable language enum, no persisted
language preference, and no runtime locale-override mechanism (`App_Language`,
a global locale setter, or a locale-threading path). Building that override —
and deciding how far it reaches (all app strings vs. subset, SwiftUI date
rendering, phone↔watch sync, which of the 6 languages to offer) — is the real
work of this ticket.

## Why LARGE

Matched triggers: **UNKNOWNS** (runtime locale-override mechanism doesn't
exist and needs API/platform research — how to override `String(localized:)`
lookups and SwiftUI locale-aware dates at runtime; no precedent in repo),
**NEW_SURFACE** (the override mechanism is a new subsystem — only the dropdown
and persistence have existing patterns to copy), and **CROSS_CUTTING, unknown
ordering** (UI surface + new persisted preference + possibly the watch platform
target, with no established layering for how the override reaches ~56 localized
call sites and 47 hardcoded strings). ~15–25 files across Core+App, and the
feature is meaningless unless the setting actually switches the UI.