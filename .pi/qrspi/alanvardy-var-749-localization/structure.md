# Structure Outline

## Approach

Build localization bottom-up: resource files first, then code migration from the
shared Core package outward, then test migration. Each layer ships with its own
tests and is proven green before the next begins. The result is four string
catalogs (one shared in Core + three target-specific), `InfoPlist.strings` for
six languages, accessibility identifiers on every interactive element, and
locale-aware plural formatting — all verified by unit tests (en-locale-pinned),
UI tests (identifier-based), and a new `LocalizationTests` suite (catalog
integrity across all six languages).

---

## Stage 1: String Catalog Infrastructure

Create the four `.xcstrings` files with English entries for every user-facing
string, and `InfoPlist.strings` per target per language. No code changes yet —
this is purely the resource layer.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` — shared (~20 keys)
- `SingleThread/Resources/Localizable.xcstrings` — app (~90 keys)
- `SingleThreadWatch/Resources/Localizable.xcstrings` — watch (~15 keys)
- `SingleThreadWidget/Resources/Localizable.xcstrings` — widget (~12 keys)
- `SingleThread/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings`
- `SingleThreadWatch/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings`
- `SingleThreadWidget/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings`
- `SingleThreadTests/LocalizationTests.swift` — new test file

**Key changes**:
- Four `.xcstrings` files, each a JSON catalog populated with English source
  phrases (`"extractionState": "manual"`; no auto-extraction until Stage 3+)
- `InfoPlist.strings` keyed to `NSMicrophoneUsageDescription`,
  `NSRemindersUsageDescription`, `NSRemindersFullAccessUsageDescription`,
  `NSSpeechRecognitionUsageDescription`, `CFBundleDisplayName`
- Widget gallery strings (`configurationDisplayName`, `description`) noted for
  Stage 5 migration to `LocalizedStringResource`; English copy stored in the
  widget catalog as the source

**Shared catalog keys** (~20, exact after ~15 current duplicates collapse):
`"High"`, `"Medium"`, `"Low"` (priority), `"<level> priority"` (a11y),
`"Repeats"`, `"Alert"`, `"Complete"` / `"Skip"` / `"Delete"` (actions),
`"Complete reminder"` / `"Skip reminder"` / `"Delete reminder"` (a11y),
`"Completion glow"`, `"All Done"` / `"No Reminders"` / `"Nothing due"` /
`"No reminders yet"` (empty states), `"Version %@ (%@)"` / `"Version %@"`
(formatted), `"Complete Reminder"` / `"Skip Reminder"` (intents),
`"Daily"` / `"Weekly"` / `"Monthly"` / `"Yearly"`,
`"Every %lld days"` / `"Every %lld weeks"` / `"Every %lld months"` /
`"Every %lld years"` (recurrence plurals)

**Tests**: `LocalizationTests` — verifies each catalog file parses as valid
JSON, every key has a non-empty English `localizations.en.stringUnit.value`,
and every `InfoPlist.strings` has the required usage-description keys with
non-empty values per language.

**Verify**: `swift test --filter LocalizationTests` passes. Build succeeds
(empty catalogs should not break compilation — this stage adds files without
wiring code to them).

---

## Stage 2: Accessibility Identifiers

Add `.accessibilityIdentifier(_:)` to every interactive, navigable, and
test-asserted element across all three UI targets. No test assertions change
yet — existing UI tests still use exact string matching and must stay green.

**Files**:
- `SingleThread/ContentView.swift` — action buttons, settings rows, empty-state
  texts, swipe-prompt labels, dictation mic, completion glow (already has one),
  undo button, background pin, notification status overlay (already has two)
- `SingleThread/SettingsView.swift` + sub-screens — all row labels, pickers,
  toggles, navigation links
- `SingleThread/ReminderCardView.swift` — priority marker, repeat/alert labels,
  due-date text
- `SingleThreadWatch/WatchReminderView.swift` — action buttons, empty states,
  refresh button, delete button, upgrade prompt, glow overlay (already has one)
- `SingleThreadWidget/NextThingWidget.swift` — complete/skip buttons, empty-state
  texts, priority marker, repeat/alert labels

**Key changes**:
- `View.accessibilityIdentifier(_:)` modifier on every element with a stable,
  descriptive identifier (e.g. `"completeButton"`, `"skipButton"`,
  `"deleteButton"`, `"emptyStateTitle"`, `"settingsDoneButton"`,
  `"appearancePicker"`, `"refreshButton"`, `"priorityMarker"`,
  `"recurrenceLabel"`, `"alertLabel"`)
- No changes to existing `.accessibilityLabel(_:)` or `.accessibilityHint(_:)`
- UI-test seam overlays keep their existing identifiers
  (`completionGlowOverlay`, `pendingStatus`, `lastScheduleStatus`)

**Tests**: Existing `SingleThreadUITests` (all 8 files) and
`SingleThreadWatchUITests` (2 files) must pass unchanged. Accessibility audit
(`performAccessibilityAudit`) must still pass — identifiers don't affect it.

**Verify**: `make ui-test` passes with zero changes to test assertions.

---

## Stage 3: Core Shared Strings Migration

Wire `SingleThreadCore` code to the shared catalog. This layer eliminates all
hardcoded English literals from the Core package and collapses the ~15
cross-target duplicates into one source of truth. Every downstream target
(Stages 4–5) can now import and use these shared strings.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift` — `displayName`
  → reads from catalog
- `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift` —
  plural-aware `String(localized:)` with `.stringsdict` entries in the catalog
- `SingleThreadCore/Sources/SingleThreadCore/AppInfo.swift` — `versionDescription`
  → `String(localized:)` with format specifiers
- `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift` — titles
  already `LocalizedStringResource`; add `table` parameter pointing to catalog
- `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` —
  **new file**: a convenience namespace so callers don't repeat `table:`
  boilerplate

**Key type/interface changes**:
- `ReminderPriority.Level.displayName: String` → computed property reading from
  `String(localized: "High", table: "Localizable", bundle: .module)`
- `ReminderRecurrenceFormatter.format(_:) -> String?` → returns
  `String(localized: "Every \(interval) days", …)` using plural-aware lookup;
  `.stringsdict` entries added to shared catalog for all five frequencies × all
  supported-language plural forms
- `AppInfo.versionDescription: String` →
  `String(localized: "Version \(marketing) (\(build))", table: "Localizable", bundle: .module)`
- `LocalizedString+Shared` enum or extension with static properties like
  `static var completeAction: String { String(localized: "Complete", …) }` —
  the contract for Stages 4–5

**Tests**:
- `ReminderSkipTests.swift` — updated: `displayName` assertions use catalog
  lookup or `String(localized:)` with locale pinned
- `ReminderRecurrenceFormatterTests.swift` — expanded: test plural output in
  `en` (singular vs. plural) and `zh-Hans` (no distinction)
- `AppInfoTests.swift` — updated: `versionDescription` assertions match new
  localized format
- `ReminderIntentsTests.swift` — existing tests using `String(localized:)`
  already pass

**Verify**: `make test` for Core unit tests passes (inject `Locale(identifier: "en")`
where format depends on locale). `make build` succeeds — catalog is wired.

---

## Stage 4: App Target Localization

Move every hardcoded English literal in `SingleThread/` to the app's
`Localizable.xcstrings`, using the shared catalog from Stage 3 where
applicable. Includes locale-aware plurals for the notification body.

**Files**:
- `SingleThread/ContentViewModel.swift` — empty-state copy titles/descriptions
  → `String(localized:)` from app catalog; shared keys (action/a11y labels)
  from Core catalog
- `SingleThread/ContentView.swift` — all `.accessibilityLabel(_:)` literal
  arguments, button titles, action labels, dictation-recording label
- `SingleThread/SettingsView.swift` + all sub-screens — ~45 settings-row labels
  → app catalog
- `SingleThread/ReminderCardView.swift` — swipe prompts, "Repeats"/"Alert"
  fallbacks, priority a11y → shared catalog
- `SingleThread/DictationViewModel.swift` — error messages
- `SingleThread/AppViewModel.swift` — notification title/body →
  `String(localized:)` with plural-aware count; `"SingleThread"` title
  → app catalog
- `SingleThread/CreationFeedback.swift` — feedback accessibility label

**Key changes**:
- `ContentViewModel.EmptyStateCopy(title:description:)` → takes
  `LocalizedStringResource` or string keys instead of hardcoded literals
- `AppViewModel` notification body:
  `String(localized: "You have \(store.visibleReminders.count) reminders waiting — open SingleThread!")`
  with plural variants in the app catalog
- `CreationFeedback` struct: `accessibilityLabel` → reads from app catalog

**Tests**:
- Unit tests (`SettingsViewTests.swift`, `ContentViewModelTests`,
  `AppDelegateTests.swift`, etc.) — update string-body reflection checks,
  `EmptyStateCopy` assertions, and any `.contains("literal")` matches to use
  catalog keys or locale-pinned `String(localized:)`
- `make build` + `make test` (with `-only-testing:SingleThreadTests`)

**Verify**: `./scripts/test.sh` (full gate) passes — all unit + UI tests green
under `en` locale. The app catalog has zero missing keys.

---

## Stage 5: Watch + Widget Localization

Wire the watch app and widget extension to their respective catalogs +
the shared Core catalog. The widget gallery strings move to
`LocalizedStringResource`.

**Files**:
- `SingleThreadWatch/WatchReminderView.swift` — all `Text("…")` and
  `.accessibilityLabel("…")` literals → watch catalog + shared catalog
- `SingleThreadWidget/NextThingWidget.swift` — empty-state strings, action
  labels, "Repeats"/"Alert" fallbacks → widget catalog + shared catalog;
  `.configurationDisplayName(_:)` / `.description(_:)` → already take
  `LocalizedStringResource` (replace with catalog ref)
- `SingleThreadWidget/NextThingWidgetView.swift` — any remaining view-body literals

**Key changes**:
- `NextThingWidget.body.configurationDisplayName` →
  `LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main)`
  (or the widget-bundle equivalent)
- Same for `.description("Your next reminder, with Complete and Skip.")`
- Watch view uses `String(localized:…)` or `Text("key", tableName: "Localizable", bundle: .main)` like the app
- Watch `accessibilityLabel` on priority/action buttons → shared catalog keys

**Tests**:
- `SingleThreadWatchTests` — update any literal assertions
- Widget snapshot tests — must produce snapshots identical to pre-localization
  under `en` locale
- `make ui-test` (watch UI tests)

**Verify**: `make build` succeeds for all targets. Watch + widget UI tests
pass under `en` locale. Widget renders correctly in the simulator.

---

## Stage 6: Test Migration & Final Verification

Switch UI tests from exact string matching to accessibility identifiers.
Hard-pin unit tests to `Locale(identifier: "en")`. Expand `LocalizationTests`
to full catalog integrity checks for all six languages.

**Files**:
- `SingleThreadUITests/` — all 8 files: replace `staticTexts["English String"]`,
  `buttons["…"]`, `switches["…"]`, etc. with `staticTexts["identifier"]`
- `SingleThreadWatchUITests/` — both files: same migration
- `SingleThreadTests/` — all ~101 literal sites: pin locale, update assertions
  to match localized output (English)
- `SingleThreadTests/LocalizationTests.swift` — expand from Stage 1

**Key changes**:
- ~230 UI-test subscript call sites switch from e.g.
  `staticTexts["All Done"]` → `staticTexts["emptyStateTitle"]`
- ~35 relative/contains matches switch to identifier assertions or are dropped
  (e.g. `label BEGINSWITH "Remind after"` → check identifier + setting value)
- Unit tests: inject `Locale(identifier: "en")` via an environment or explicit
  `String(localized:locale:)` parameter; current exact-English assertions
  continue to work since locale is pinned
- `LocalizationTests`:
  - Every key in every catalog has a non-empty `en` value
  - Every key has entries for all six languages (no missing `localizations`)
  - No orphaned keys (keys in catalog with no code referencing them, via
    a grep/build-symbol check)
  - Plural variants exist in the catalog for each locale where they matter

**Verify**: `./scripts/test.sh` passes — full gate (format, lint, build,
Periphery, unit tests, UI tests, accessibility audit). Build with a non-`en`
scheme run destination and spot-check that UI renders localized strings (manual
simulator check). `make periphery` reports zero dead code.

---

## Testing Checkpoints

| After Stage | What must be green |
|---|---|
| 1 | `swift test --filter LocalizationTests` + `make build` (all targets) |
| 2 | `make ui-test` (all existing assertions unchanged) + accessibility audit |
| 3 | Core unit tests (`make test -only-testing:SingleThreadTests`) + `make build` |
| 4 | Full `./scripts/test.sh` (unit + UI + lint + Periphery) |
| 5 | `make build` all targets + watch/widget UI tests |
| 6 | Full `./scripts/test.sh` + manual non-English simulator check |