# Task

Make the privacy policy screen (Settings → Privacy Policy) render in the
in-app interface language — the `AppLanguage` picker in Settings → Interface —
instead of following the device/process locale.

The screen (`PrivacySettingsView` → `PrivacyGuideContent`) is the last
holdout from the localization effort: its section titles, bodies, and closing
line resolve through `PrivacyGuideContent.localized(_:)`, which calls
`String(localized: LocalizationValue(stringLiteral: key), table: "Localizable",
bundle: .main)` with **no locale pin**. That resolves against the *device*
locale, not the interface language chosen in-app (`AppLocaleState` →
`\.locale` environment). Everything else in the app either uses
`LocalizedStringResource` (SwiftUI resolves those against the environment
`\.locale`) or pins non-view resolution via
`LocalizedStringResource(...).resolved(in: AppLocaleState.storedEffectiveLocale)`
/ `resolvedInAppLanguage()` (see `NotificationScheduler`, `CreationFeedback`,
`ContentView`, `BackgroundSettingsView`) — that is the pattern to follow.

No catalog work is needed: all 9 privacy strings ("Reminders", "Display &
Sync Preferences", "Skipped & Excluded Lists", "Background Image", the four
bodies, and the closing line "SingleThread has no analytics, no tracking, and
no advertising.") already exist in `SingleThread/Resources/Localizable.xcstrings`
with genuine translations in all six languages (en, zh-Hans, es, ja, de, fr) —
`LocalizationTests` enforces every key resolves in all six languages.

Ship unit tests proving the privacy copy resolves in each interface language
(and, where applicable, that non-English values are not English-identity).
Note the existing `PrivacySettingsContentTests` deliberately pin `locale: en`
"so this test stays host-locale independent" — that comment documents the
current defect; the new tests should assert the picker-driven behavior.
Also verify a language switch while the screen is visible re-renders the copy
(precedent: root `\.locale` injection in `SingleThreadApp.swift` and
`localizedNavigationTitle` re-resolving on locale change).

## Why SMALL

A single module (app target + its unit tests) and 2–3 files, following the
existing `LocalizedStringResource.resolved(in:)` / `resolvedInAppLanguage()`
pattern; one known unknown (live re-render on switch) with established
precedent; no schema, no new subsystem, no shared/convention-code changes,
no design sign-off; a few local unit tests.

## Key files

- `SingleThread/PrivacySettingsContent.swift` — the `localized(_:)` helper and
  `sections` / `closingLine`; the fix lives here (pin the locale to the
  interface language).
- `SingleThread/PrivacySettingsView.swift` — renders already-resolved `String`s;
  may need to observe `AppLocaleState` so switching language re-renders while
  the screen is open.
- `SingleThreadTests/PrivacySettingsContentTests.swift` — today pins `locale: en`
  and notes the runtime strings follow the host locale; add per-interface-
  language resolution tests.
- `SingleThread/Resources/Localizable.xcstrings` — keys + all six languages
  already present; no edits expected.
- Reference patterns: `LocalizedStringResource.resolved(in:)` and
  `resolvedInAppLanguage()` in `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`,
  `AppLocaleState` in `SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift`,
  `String.en(...)` locale-pinned test helper in `SingleThreadTests/LocalizationTestHelpers.swift`.