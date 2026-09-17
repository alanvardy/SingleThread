# Phase 1 Report — Walking skeleton (language picker switches the Interface screen)

Commit: `accf9502` — "Phase 1: walking skeleton — language picker switches the Interface screen"
Branch: `alanvardy-var-1034-set-language` (pushed; fast-forward `1294cedb..accf9502`)

## Changes

### New files (4)
- `SingleThreadCore/Sources/SingleThreadCore/AppLanguage.swift` — enum `AppLanguage: String, CaseIterable, Sendable` (system + 6 catalogs), `locale`/`localeIdentifier`/`title`.
- `SingleThreadCore/Sources/SingleThreadCore/AppLanguagePreference.swift` — App-Group-backed preference store (mirrors `AppearanceModePreference`, defaults to `AppGroup.defaults` like `SortOption`).
- `SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift` — `@MainActor @Observable` holder (`import Observation`), `static current`, `language`, `effectiveLocale`, `set(_:)`, `nonisolated static storedEffectiveLocale`.
- `SingleThreadTests/AppLanguageTests.swift` — the 6 plan tests.

### Modified files (11)
- `LocalizedString+Shared.swift` — appended `public extension LocalizedStringResource` with `resolved(in:)` + `resolvedInAppLanguage()` (SharedStrings accessors untouched — Phase 2).
- `SettingsBindings.swift` — store-backed computed `appLanguage` in the App-Group MARK (`access(keyPath:.appLanguage)` / `withMutation` → `AppLocaleState.current.set`).
- `InterfaceSettingsView.swift` — `@Binding var appLanguage: AppLanguage` (ungated), Picker after Text Size with label "Language" + caption, `.accessibilityIdentifier("languagePicker")`; both `#Preview` constructors gain `appLanguage: .constant(.system)`.
- `AppearanceMode.swift` / `TextSize.swift` — `title` now returns `LocalizedStringResource` (deviation 1).
- `SettingsView.swift` — `appLanguage: $bindings.appLanguage` in both `InterfaceSettingsView(...)` calls (iOS + macOS).
- `SingleThreadApp.swift` — `import SingleThreadCore` + `.environment(\.locale, AppLocaleState.current.effectiveLocale)` on `ContentView`.
- `Localizable.xcstrings` — keys `Language` and `Choose the language for the app.` × six languages; all non-English values differ from English (identity guard); no endonym catalog entries (deviation 4).
- `AppearanceModeTests.swift` / `TextSizeTests.swift` — title assertions now `title.resolved(in: Locale(identifier: "en"))`.
- `SettingsViewTests.swift` — `appLanguage: .constant(.system)` at all 6 `InterfaceSettingsView(...)` construction sites; new differential test `settingsScreenShowsLanguagePickerOnBothPlatforms`.

### plan.md
Phase 1 "#### Automated" checkboxes (the 5 items under `### Verification`) flipped `- [ ]` → `- [x]`. Manual items left unchecked; Testing-checkpoint table untouched.

## Verification results (all automated, in the required order)

| # | Command | Result |
|---|---------|--------|
| 1 | `scripts/test-one.sh SingleThreadTests/AppLanguageTests` | passed — 6/6 cases ran |
| 2 | `scripts/test-one.sh SingleThreadTests/SettingsViewTests` | passed — 16/16 cases ran (twice: once fail → fix → green) |
| 3a | `scripts/test-one.sh SingleThreadTests/AppearanceModeTests` | passed — 5/5 cases ran |
| 3b | `scripts/test-one.sh SingleThreadTests/TextSizeTests` | passed — 7/7 cases ran |
| 4 | `make build` | passed — "** TEST BUILD SUCCEEDED **" |
| 5 | `make format && make lint` | passed — 0 violations, 0 serious (192 files) |

Full `./scripts/test.sh` gate NOT run (owned by a later step).

## Adaptations vs plan (all forced by actual signatures/behavior)

1. **`import SingleThreadCore` added to `AppearanceModeTests.swift` and `TextSizeTests.swift`** — the `resolved(in:)` extension is not visible transitively; the compiler demanded the defining module's import (test target import semantics).
2. **`import SwiftUI` added to `AppLanguageTests.swift`** — Foundation types (`UUID`, `UserDefaults`, `Locale`, `LocalizedStringResource`, `Bundle`) are exposed to the test target through `SwiftUI`, not through `SingleThread`/`SingleThreadCore`; without it the plan's test bodies failed with "Cannot find 'UUID'".
3. **`SettingsViewTests` macOS-only constructors** (`interfaceSettingsViewContainsActionButtonsRowOnMacOS`, `macOSToggleTogglesBinding`, `interfaceSettingsViewContainsMenuBarToggle`, `interfaceSettingsViewRendersMenuBarToggleOnce`) also gained `appLanguage: .constant(.system)` — the new required `@Binding` param made these fail to compile otherwise (plan only listed the two sites in `interfaceSettingsViewContainsExpectedRows`).
4. **New-test third assertion adapted from `contains("languagePicker")` → `contains("SingleThreadCore.AppLanguage")`** — empirical: `String(describing:)` never reflects accessibility-identifier *values* (verified: `languagePicker` and even the pre-existing `appearancePicker` appear 0× in the description; the identifier modifier only reflects as the type `AccessibilityAttachmentModifier`). The Picker's element type `SingleThreadCore.AppLanguage` is the discriminating reflected artifact. Comment added documenting the same limitation the repo already documents in `purchaseSettingsViewContainsTopAnchor` / `excludedListsViewContainsTopAnchor`. The `languagePicker` identifier itself remains on the live view (covered by the a11y audit later).
5. **`interfaceSettingsViewContainsExpectedRows` macOS `#expect` folded to one line** — swiftlint `function_body_length` (50 lines) tripped at 52 after the added param; the fold is message-only, no assertion semantics changed.

## Observations / notes for later phases

- `import Observation` compiled fine in Core (module exists in iOS 27 SDK); existing Core `@Observable` files omit it, so it is optional — keeping the plan's explicit import since it verified.
- `AppLocaleState.current` static + `@Observable` compiled and linked without issue.
- `localizedStringResourceResolvesInExplicitLocale` (Bundle.core) passed → the `resource.locale = locale; String(localized:)` resolve path is proven in-process; Phase 2 can rely on it.
- Catalog JSON validated with `json.load` (139 App keys; both new keys ×6 languages, non-English differ from English).
- `make format` after edits touched only the Phase 1 files (repo-wide sweep produced no out-of-scope diffs).

## Residual risks
- macOS `InterfaceSettingsView` construction is only compile-checked (iOS host). The plan's macOS checkpoints are Manual/UI-test territory.
- The layout/hit-region of the new Picker row is not UI-tested in this phase (a11y audit later).
- `AppLanguagePreference.rawValue` uses `defaults.object(forKey:) as? String` exactly per plan (matches `AppearanceModePreference`); string-typed read equivalent.