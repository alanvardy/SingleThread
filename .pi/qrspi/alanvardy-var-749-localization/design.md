# Design Discussion — VAR-749 Localization

## Current State

The project has **zero localization infrastructure** — no `.xcstrings`, `.strings`,
`.stringsdict`, `.lproj` directories, or `PBXVariantGroup` entries exist anywhere
(research Q2). All ~130+ distinct user-facing strings are hardcoded English Swift
literals across four targets:

- **SingleThread (iOS+macOS): ≈105–110 strings** — settings labels (`SettingsView.swift:54-124`),
  empty states (`ContentViewModel.swift:61-75`), action buttons + a11y
  (`ContentView.swift:92-570`), dictation errors (`DictationViewModel.swift:36,41`),
  local-notification title/body (`AppViewModel.swift:134-135`)
- **SingleThreadWatch: ≈18 strings** — `WatchReminderView.swift:49-248`, including
  independent copies of empty-state copy also present in the app and widget
- **SingleThreadWidget: ≈16 strings** — `NextThingWidget.swift:33-225`, widget
  gallery name/description (:121-122), plus duplicated action labels and a11y
- **SingleThreadCore: ≈17 strings** — intent titles (`ReminderIntents.swift:14,37`,
  already `LocalizedStringResource`), priority names (`ReminderSkip.swift:42-44`),
  recurrence summaries (`ReminderRecurrenceFormatter.swift:16-22`), version strings
  (`AppInfo.swift:29-41`)

**~15 strings are duplicated across targets** (action labels, empty states, a11y labels,
priority a11y, "Repeats"/"Alert" fallbacks). Each target re-hardcodes its own copy
independently.

**Info.plist user-facing copy lives in build settings** (`INFOPLIST_KEY_*` at
pbxproj:744-746,941-942,998-1000), not in physical plists (except the trivial widget
plist). Single-language, no `InfoPlist.strings`.

**Tests assert on exact English string literals**: ~230 UI-test subscript call sites
(191 in `SingleThreadUITestsFlows.swift` alone) + ~35 relative/contains matches +
~101 unit-test literal sites. Only 3 accessibility identifiers exist in production
(`completionGlowOverlay`, `pendingStatus`, `lastScheduleStatus`).

**Locale-aware output is nearly absent**: only SwiftUI `Text(date, style: .date)`
at `ReminderCardView.swift:97` / `WatchReminderView.swift:233` / `NextThingWidget.swift:210`.
Plurals use `interval > 1` ternaries; notification bodies use raw `\(count)` interpolation.

## Desired End State

A fully localizable app across all four targets, initially shipping English + 5
additional languages (zh-Hans, es, ja, de, fr — covering ~70% of App Store users).

**Verification criteria:**
1. Every user-facing string across all four targets is routed through a string catalog
2. No duplicated strings across targets — shared strings live once in Core's catalog
3. Info.plist usage descriptions and display names are localized via `InfoPlist.strings`
4. Plurals, interpolated counts, and recurrence summaries use locale-aware formatting APIs
5. All existing unit and UI tests pass (with locale pinned to `en` for unit tests;
   UI tests use accessibility identifiers instead of exact string matching)
6. A new `LocalizationTests` suite verifies catalog integrity (no missing keys,
   no empty translations for supported languages, no orphaned keys)
7. App Store listing localization is scoped to a **separate follow-up ticket**
   (VAR-xxx) — the design documents the approach and creates a scaffold ticket

## Patterns to Follow

### Good patterns (from the existing codebase)

- **`LocalizedStringResource` for AppIntent titles** — `ReminderIntents.swift:14,37` already
  uses the correct type for intent display names. Extend this pattern: any
  `AppIntent` title or `WidgetConfiguration` description should use
  `LocalizedStringResource` rather than a bare `String`, so the system
  picks the right localization automatically.
- **Accessibility identifiers as test contract** — `ContentView.swift:569`
  (`completionGlowOverlay`), `ContentView.swift:703,705` (`pendingStatus` /
  `lastScheduleStatus`). This is the model for UI tests: add
  `.accessibilityIdentifier("…")` on every element UI tests interact with.
  Exact-string XCUITest assertions (`staticTexts["All Done"]`) are brittle
  under localization; identifiers are locale-independent.
- **`Bundle` injection for testability** — `AppInfo.swift:13` (`init(bundle: Bundle = .main)`).
  Follow this pattern for any new code that reads localized strings from a
  bundle: inject the bundle so tests can target a known locale.
- **`@Observable` view models with injected stores** — `ContentViewModel`, `WatchReminderViewModel`.
  String lookups inside view models should use `String(localized:comment:)` or
  `Text(…)` with the injected catalog, never hardcoded literals.
- **`InMemoryEventStore` for previews and tests** — used in `WatchReminderView.swift:27`,
  widget snapshots, and unit tests. Localization should not break this seam;
  preview data continues to use `InMemoryEventStore` and renders locale-dependent
  formatting.

### Patterns to avoid

- **Copy-paste duplicating strings across targets** — the current empty-state copy
  exists in `ContentViewModel.swift:61-75`, `WatchReminderView.swift:148,156`, and
  `NextThingWidget.swift:143-148` as three independent sets of literals. The
  localization layer must make shared strings a single source of truth.
- **String interpolation for formatted values** — `"Every \(interval) days"`
  (`ReminderRecurrenceFormatter.swift:18`) and `"You have \(count) reminders waiting"`
  (`AppViewModel.swift:135`) are not localizable. Replace with `String(localized:)`
  plural-aware APIs.
- **Hardcoded Info.plist build settings** — `INFOPLIST_KEY_NSMicrophoneUsageDescription`
  at pbxproj:744-746, 941-942, 998-1000. These must move to `InfoPlist.strings` for
  localization. The build-setting keys become the fallback; `.strings` overrides
  per language.

## Design Decisions

1. **Per-target catalogs + Core shared catalog**: Core gets a `Localizable.xcstrings`
   (`SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`)
   holding all cross-target shared strings (priority names, recurrence, version,
   action labels, empty states, a11y labels — ~15 strings). Each UI target gets its
   own catalog for target-specific copy. Catches the existing Core-as-model-layer
   boundary and eliminates all cross-target duplication.

2. **Accessibility identifiers for UI tests, en-locale for unit tests**: UI tests
   switch to `.accessibilityIdentifier("…")` assertions (extending the existing
   `completionGlowOverlay` / `pendingStatus` pattern). Unit tests pin
   `Locale(identifier: "en")` and continue asserting English output — they test
   logic (formatting, state transitions), not translation correctness. A new
   `LocalizationTests` suite validates catalog integrity.

3. **Traditional `InfoPlist.strings` per target per language**: Each product
   target gets `<language>.lproj/InfoPlist.strings` keyed to `NSMicrophoneUsageDescription`,
   `NSRemindersUsageDescription` / `NSRemindersFullAccessUsageDescription`,
   `NSSpeechRecognitionUsageDescription`, `CFBundleDisplayName`. The widget's
   physical `Info.plist` (`SingleThreadWidget/Info.plist`) stays as-is (it contains
   only `NSExtensionPointIdentifier`, no user-facing copy). The build-setting keys
   in pbxproj serve as the English fallback; `.strings` files override per language.

4. **Initial languages: en + zh-Hans, es, ja, de, fr**: Six languages total,
   covering the top App Store markets. Infrastructure (catalogs, `InfoPlist.strings`,
   plural rules) is built for all six from day one. Adding more languages later
   is a mechanical operation (add translations to existing catalogs + new
   `InfoPlist.strings`).

5. **App Store listing localization is a separate ticket**: The App Store
   listing (name, subtitle, description, keywords, screenshots) is managed in
   App Store Connect, not in the repo. This task documents the process and
   creates a follow-up Linear ticket (VAR-xxx) to handle storefront metadata
   and screenshot localization. In-app localization ships first; the App Store
   listing can be localized independently afterward.

6. **Plurals and formatted strings use `LocalizedStringResource` with plurals**:
   Recurrence summaries, notification bodies with counts, and any other
   dynamic strings with numeric interpolation move to
   `String(localized: "Every \(interval) days", table: nil, locale: …)` with
   proper `.stringsdict` plural rules for each supported language where
   plurals differ from English (ja, zh-Hans, ko typically need zero/other;
   ar needs six forms). The string catalog's built-in plural support handles
   this.

## What We're NOT Doing

- **Not changing the dictation parser**: `ReminderDictationParser.swift:106-144`
  hardcodes English regexes and weekday vocabulary. Speech recognition in
  non-English languages requires a fundamentally different approach
  (language-specific parsers, `SFSpeechRecognizer` locale selection). This is
  out of scope — dictation remains English-only for now.
- **Not adding `AppShortcuts`, SiriKit, or `CSSearchable`**: Those surfaces
  don't exist today; localization won't create them.
- **Not localizing developer-facing strings**: Logger output
  (`AppDelegate.swift:41,46`), `print` statements, and debug-only overlays
  (`ContentView.swift:702-706`) stay in English.
- **Not changing the app's bundle ID or product name**: `PRODUCT_NAME` /
  `CFBundleDisplayName` are localized (via `InfoPlist.strings`) but the
  identifiers themselves don't change.
- **Not adding RTL layout support as a mandatory deliverable**: String
  catalogs and SwiftUI `Text` handle RTL text automatically for languages
  like Arabic/Hebrew, but those aren't in our initial six. RTL layout testing
  is a best-effort bonus, not a gate.
- **Not localizing preview or seed fixture data**: `"Buy groceries"`, `"Work"`,
  `"Personal"`, `"milk"` — these are test/test-data strings, not user-facing copy.
- **Not running full `./scripts/test.sh` from inside phase subagents**: Per
  project conventions, workers run targeted `-only-testing:` suites. The full
  gate runs once from the parent.

## Open Risks

- **`GENERATE_INFOPLIST_FILE = YES` + `InfoPlist.strings` interaction**: The app
  and watch generate their Info.plist at build time from `INFOPLIST_KEY_*` settings.
  We need to verify that placing an `InfoPlist.strings` in the target's source
  directory correctly overrides the generated plist values. If not, we may need
  to switch to physical plists for those targets (more pbxproj work).
- **Watch widget catalog loading**: The watch target imports SingleThreadCore but
  runs in a separate process with its own bundle. We must verify that
  `Bundle.module` resolves correctly from within the watch extension when
  loading Core's string catalog. Xcode 16+ handles this correctly for SPM
  packages with resources, but the `objectVersion = 77` synchronized-folder
  layout makes this worth verifying early.
- **Plural engine for zh-Hans and ja**: These languages don't distinguish
  singular/plural grammatically — our current `interval > 1` ternary is
  accidentally correct for them. The new plural-aware API must not introduce
  spurious "1 reminders" output in English or unnecessary plural variants in
  zh-Hans/ja. The string catalog plural editor handles this correctly by
  default, but it's worth an explicit test.
- **UI test migration churn**: ~230 XCUITest call sites switch from
  `staticTexts["…"]` / `buttons["…"]` with exact strings to
  `staticTexts["identifier"]`. This is mechanical but error-prone — a missed
  site silently breaks under a non-English locale. Best approach: add
  identifiers alongside existing strings first, then switch tests, then
  remove English assertions in a follow-up. A `--ui-testing` launch-arg
  override could surface the active locale in the test runner for debugging.
- **Translation sourcing**: The design assumes translations exist for zh-Hans,
  es, ja, de, fr. A solo developer needs either manual translation, a
  translation service, or machine translation with human review. Machine
  translation (e.g., DeepL) is fast and adequate for a v1, but strings like
  `"Swipe left to skip"` need careful review — gesture direction metaphors
  vary by culture. Budget time for review.