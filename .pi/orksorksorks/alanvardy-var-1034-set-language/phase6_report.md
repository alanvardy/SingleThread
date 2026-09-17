# Phase 6: Hardening — the locale change sticks everywhere

Branch: `alanvardy-var-1034-set-language` (this worktree)
Commit: `e161c0a6` (pushed as `d1c8aaac..e161c0a6` on `alanvardy-var-1034-set-language`)

## Introduction

Phase 6 hardened the language-picker feature end to end: a nav-title/sheet
re-localization decision backed by the new UI test, a `--ui-testing-app-language`
launch seam for the UI sad path, one leftover eager `String(localized:)` in
`BackgroundSettingsView` converted, the macOS Commands Appearance submenu
converted to the Phase 5 resolution pattern, a widget/watch refresh
verification (no code change), and two new UI tests. Phase 6 is deliberately
code-light; most of its value is in *proving* the runtime behavior matches the
design.

## Changes

### 1. Navigation-title / sheet re-identity — DECISION: verified re-localize, no `.id(locale)`, no sheet `.environment` (ContentView untouched)

Plan step 1 asked for a manual test of whether nav titles re-localize and, if
not, to re-key the stack on `\.locale`. The plan's step 6 UI test is the
definitive local evidence.

**Evidence:** `testLanguageSelectionChangesVisibleString` launches
`--ui-testing`, presents the settings sheet, pushes the Interface screen,
asserts the English "Appearance" label, switches the language picker to
Deutsch, and asserts the *same presented, pushed view* now shows "Darstellung"
with no relaunch. The test **passes** with no `.id(locale)` and no
`.environment(\.locale, …)` anywhere added (ContentView.swift is byte-identical
to the committed Phase 5 state).

**Decision:** nav titles + sheets re-localize on the iOS 27 SDK. The published
iOS 18 "stale sheet locale" risk does not materialize here — the root
`.environment(\.locale, AppLocaleState.current.effectiveLocale)` in
`SingleThreadApp` propagates into the already-presented sheet and its pushed
row, driven by the `@Observable` invalidation of `AppLocaleState.current`.
No `.id(locale)` (and its navigation-reset trade-off) and no sheet
`.environment` were added.

**Observation/adaptation:** the plan's original snippet tapped
`app.staticTexts["Deutsch"]` immediately after tapping `languagePicker`. That
races the picker's menu presentation and failed with `Failed to tap "Deutsch"
StaticText: No matches found`. The test now waits
(`waitForExistence(timeout: 5)`) for the German option queried type-agnostically
(`app.descendants(matching: .any)` + `NSPredicate("label == %@", "Deutsch")`),
so menu rows are matched regardless of whether they surface as buttons or
static texts.

### 2. `--ui-testing-app-language` seam (AppViewModel.swift)

Added inside the `--ui-testing` branch of `makeStore`, after the branch's
reset/seed writes (so the staged value is not wiped):

```swift
if let index = arguments.firstIndex(of: "--ui-testing-app-language"),
   index + 1 < arguments.count {
    AppLanguagePreference().setRawValue(arguments[index + 1])
    AppLocaleState.current.set(AppLanguagePreference().load()) // validates → .system
}
```

- `AppLanguagePreference().setRawValue("klingon")` writes the raw value to the
  App Group key.
- `AppLanguagePreference().load()` validates: `klingon` is not in
  `AppLanguage.allCases`, so `rawValue` falls back to
  `AppLanguage.system.rawValue` and `load()` returns `.system` —
  `AppLocaleState.current.set(.system)` persists and republishes it.
- This is the only write path touched; Phase 1's validated read guarantees the
  degradation. No other path writes an unvalidated raw value (audited).

### 3. Audit — residual list

`rg -n 'String\(localized:' SingleThread SingleThreadCore SingleThreadWatch SingleThreadWidget`

Residual (only the helper's body remains):

```
SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:111:
    return String(localized: resource)
```

That is the `resolved(in:)` body — the intentional non-View resolution helper.
No prod `String(localized:)` site remains outside it and the debug-only
`Text(...)` literals.

`rg -n 'SharedStrings\.' SingleThread SingleThreadWatch SingleThreadWidget`
— every accessor is consumed in a resource-accepting API
(`ProgressView`, `ContentUnavailableView`, `Label`, `Button`, `.accessibilityLabel`,
`.confirmationDialog`, `.navigationTitle`, `Text`, `SettingsLinkLabel(title:)`,
`display.recurrenceSummary ?? SharedStrings.repeats` — a `LocalizedStringResource? ?? LocalizedStringResource`)
or through `.resolvedInAppLanguage()` (macOS `SingleThreadApp+Commands.swift`).
No `SharedStrings.` accessor is consumed as a bare `String`.

### 4. BackgroundSettingsView credit (prod eager `String(localized:)` removed)

The two-line `String(localized: "Photo by \(photographer) on Unsplash", …)`
credit in the footer (missed by the single-line audit in earlier phases) is now:

```swift
let credit = LocalizedStringResource(
    "Photo by \(photographer) on Unsplash",
    table: "Localizable", bundle: .main).resolvedInAppLanguage()
```

- The photographer name is dynamic (`BackgroundImageStore.photographer: String?`),
  so the key is interpolated, exactly as before; the catalog key
  `"Photo by %@ on Unsplash"` (already present, all 6 languages translated)
  is matched as before.
- `resolvedInAppLanguage()` resolves against `AppLocaleState.storedEffectiveLocale`
  — the same non-View resolution pattern Phase 4/5 used for formatter,
  scheduler, and notification sites.
- `Link(credit, …)` / `Text(credit)` both accept the resulting `String`.

### 5. Widget / watch refresh — verified, no code change

- **Widget** (`SingleThreadWidget/NextThingWidget.swift`): the timeline view
  applies `.environment(\.locale, AppLanguagePreference().load().locale)` at
  build; the phone side triggers `WidgetCenter.shared.reloadAllTimelines()` from
  `SettingsViewModel.showPreferenceChanged()`, which
  `InterfaceSettingsView`'s `.onChange(of: appLanguage)` already invokes — so a
  mid-session language change reloads the widget timelines with the new locale.
- **Watch** (`SingleThreadWatch`): the root applies
  `.environment(\.locale, AppLocaleState.current.effectiveLocale)`
  (`SingleThreadWatchApp.swift:17`); phone-side choice lands via the Phase 3
  wire (`AppViewModel.handlePreferencesChanged` → `pushAll` →
  `service.onAppLanguageReceived` → `AppLocaleState.current.set(value)` in
  `WatchAppViewModel.swift:289-290`), flipping the watch UI without a relaunch.
- Both read their locale at build or from synced state; no widget/watch view
  change is needed. If the widget ever showed a stale language, the fault would
  be the reload chokepoint (Phase 3), not the widget view.

### 6. macOS Commands Appearance submenu (SingleThreadApp+Commands.swift)

Converted the literal `CommandMenu("Appearance")` /
`Picker("Appearance", …)` / `Text("System"|"Light"|"Dark")` tags to the exact
Phase 5 pattern used by About/Quit and the Reminder menu in this file —
`.resolvedInAppLanguage()` on the `LocalizedStringResource` (keys already in the
catalog with all 6 language translations). macOS-only (not compiled locally):
I type-checked `CommandMenu(String)`, `Picker(String, selection:)`, and
`Text(String)` against the macOS 27 SDK (`swiftc -typecheck`, exit 0), so the
StringProtocol overloads are confirmed available.

### 7. UI tests (SingleThreadUITests.swift)

Two new XCTest methods, justified as end-to-end UI-layer flows no unit test can
observe (environment-locale propagation through the presented sheet, pushed
row, and picker values is SwiftUI runtime behavior; the sad-path launch seam is
only meaningful at launch):

1. `testLanguageSelectionChangesVisibleString` — `--ui-testing` launch → settings
   sheet → Interface row → English "Appearance" baseline → picker → Deutsch →
   "Darstellung" appears and "Appearance" is gone, with no relaunch.
2. `testUnsupportedStoredLanguageFallsBackToSystem` — `--ui-testing
   --ui-testing-app-language klingon` launch → settings → Interface → the
   system-language "Appearance" label renders (`.system` under the English test
   locale).

Existing `testLaunchAndRenderSmoke` untouched; unit-test suites
(LocalizationTests, SettingsViewTests) not modified — their assertions relate
to catalog/API behavior that this phase did not change.

## Verification

| Command | Result |
|---|---|
| `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLanguageSelectionChangesVisibleString` | OK — `ok: 1 case(s) ran for …testLanguageSelectionChangesVisibleString` (script rc 0) |
| `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testUnsupportedStoredLanguageFallsBackToSystem` | OK — `ok: 1 case(s) ran for …testUnsupportedStoredLanguageFallsBackToSystem` (script rc 0) |
| `make format && make lint` | Clean — swiftformat lint 0/200 require formatting; swiftlint `0 violations, 0 serious` (193 files) |

(The first `testLanguageSelectionChangesVisibleString` runs failed for a real
reason: the plan snippet tapped `staticTexts["Deutsch"]` without waiting for the
picker menu; once the wait/type-agnostic query was added the test passed, and
the pass occurred with the ContentView fix absent — proving the no-`.id`/no
`.environment` decision.)

plan.md Phase 6 automated checkboxes flipped `- [ ]` → `- [x]` (the three
`#### Automated` items). Manual items (line 1181, macOS), `#### Full gate`
items, prior phases, and the Testing-checkpoint table intentionally untouched.

## Risks / notes for the gate

- The macOS Commands conversion is unverifiable locally (macOS app target is
  pre-broken on origin/main; `apple-macOS` destination not run here).
  Type-checked pattern against the SDK; the full gate builds watch + widget,
  not macOS, so it stays a review item.
- The picker-menu race in the plan's snippet was a genuine test-robustness gap;
  the fixed query keeps the plan's intent (hard assertion on Appearance →
  Darstellung).
- The iOS UI-test runs exercised the worktree-pinned sim
  (D4C34BCA-7C96-418E-BDD3-BB22738A69C7); no shared "iPhone 17" was booted.