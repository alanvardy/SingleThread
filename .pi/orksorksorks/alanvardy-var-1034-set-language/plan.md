# Implementation Plan

## Overview

Add a store-backed `AppLanguage` preference (`AppGroup.defaults`) surfaced as a
`SettingsBindings.appLanguage` computed property and a Settings → Interface
Picker, and drive rendering with a root `.environment(\.locale, effectiveLocale)`
fed by the `@Observable` `AppLocaleState`. Shared strings become *deferred*
(`LocalizedStringResource`) so the environment applies; non-View contexts resolve
via a locale-aware helper. The watch receives the value over the existing keyed
sync payload; the widget reads the store at timeline build.

Everything is app/core/watch/widget source — **no schema migration**, so every
phase is a vertical slice. Slices run skeleton → shared-string shape →
separate-process reach (risk) → content sweep (value) → hardening.

## Ground rules (apply to every phase)

- **Shell**: the command tool runs fish. Use `bash -c '…'` / a `/tmp/x.sh` file
  for loops, heredocs, `$(…)`; `set VAR val`; `$status`. A `fish:` rejection
  means stop and switch form (see `~/.pi/agent/skills/fish-shell`).
- **Simulator pinning**: `scripts/test-one.sh <Target/Suite/case>` and `make …`
  resolve this worktree's `.simulator_id`
  (`D4C34BCA-7C96-418E-BDD3-BB22738A69C7`). Never boot a shared "iPhone 17" by
  name; pass `SIM=<UDID>` if you must override. One `xcodebuild` at a time.
- **Before each commit**: `make format` then `make lint`.
- **Per phase**: build + targeted `-only-testing:` suites only. The full
  `./scripts/test.sh` runs **once**, after Phase 6, via the `run-gate` skill.
- **New `.swift` files** need no pbxproj edit (synchronized groups). No new test
  target.
- **Unit-test names** must not start with `test`/`testing`; UI-test (XCTest)
  names keep `test…`.
- **Comments in code**: match the repo's existing doc-comment density; every new
  public type gets a one-line purpose doc.

### Deviations from `structure.md` (flagged, deliberate)

1. **Phase 1 also converts the enum titles** `AppearanceMode.title` and
   `TextSize.title` to `LocalizedStringResource` (`AppearanceMode.swift`,
   `TextSize.swift`) and updates `AppearanceModeTests`/`TextSizeTests`. Without
   this, the Interface screen's *picker values* stay in the system language while
   its labels switch — the walking skeleton would visibly fail its own outcome.
2. **Phase 2 also converts** `ReminderRecurrenceFormatter.format` →
   `LocalizedStringResource?`, `ReminderDisplay.recurrenceSummary`,
   `ReminderPriority.Level.displayName`, `ContentViewModel.EmptyStateCopy.title/
   description`, and `SettingsLinkLabel.title`, because the `SharedStrings`
   return-type change makes these compile-incompatible in the same commit
   (`??` between `LocalizedStringResource?` and a resource only type-checks when
   both are resources). This is why `structure.md` lists `SingleThreadTests.swift`
   / `ReminderRecurrenceFormatterTests` / `ReminderSkipTests` in Phase 2.
3. **Non-View resolution**: `structure.md` sketched
   `AppLocaleState.current.effectiveLocale` for non-View consumers, but
   `AppLocaleState` is `@MainActor` and formatter/scheduler/notification call
   sites are `nonisolated`. The plan adds a `nonisolated static var
   storedEffectiveLocale` (a store read) plus
   `LocalizedStringResource.resolvedInAppLanguage()` for those sites; Views still
   use `AppLocaleState.current` and `\.locale`.
4. **`AppLanguage` endonyms are intentionally uncatalogued** (rendered verbatim
   as the `LocalizedStringResource` key). Cataloging `"German" → "Deutsch"` for
   all six languages would trip `LocalizationTests`' English-identity guard
   (`guardedCatalogs`), which forbids a non-English value equal to the English
   one. `"System"` reuses the existing App key.
5. **Phase 6 adds a `--ui-testing-app-language <raw>` launch seam** in
   `AppViewModel` to drive the UI sad path; `structure.md` asked for the sad path
   without naming the seam.
6. **Literal sweep is mostly catalog work, not code work**: `Text("…")` and
   `SettingsCaption(text: "…")` are already `LocalizedStringKey` and already
   follow `\.locale`. The fix for a bypassing literal is to add the *missing
   catalog key* (×6 languages); code changes are only needed for eager
   `String(localized:)` / `String`-typed properties. Phase 4/5 steps below call
   this out per file.

---

## Phase 1: Walking skeleton — the Language picker switches the Interface screen live

Outcome: open Settings → Interface, pick *Español*; the Interface screen (and its
picker values) changes immediately, the choice survives relaunch, and round-trips
`AppGroup.defaults`.

### Changes

#### 1. `AppLanguage` — new
**File**: `SingleThreadCore/Sources/SingleThreadCore/AppLanguage.swift`
**Action**: create

```swift
import Foundation

/// User-selectable app language. `.system` preserves the device locale (today's
/// behaviour); the other cases pin the app to one of the six shipped catalogs.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"
    case japanese = "ja"
    case german = "de"
    case french = "fr"

    /// Locale for SwiftUI's `\.locale` and explicit lookups. `.system` follows
    /// the device; the six pinned cases map to their catalog language.
    public var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    /// BCP-47 identifier, or `nil` when following the system.
    public var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    /// Picker label. `.system` localizes through the App catalog; the six
    /// language names are endonyms deliberately left out of every catalog so
    /// they render verbatim (cataloging them would also trip
    /// `LocalizationTests`' English-identity guard).
    public var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
        case .english: LocalizedStringResource("English")
        case .simplifiedChinese: LocalizedStringResource("简体中文")
        case .spanish: LocalizedStringResource("Español")
        case .japanese: LocalizedStringResource("日本語")
        case .german: LocalizedStringResource("Deutsch")
        case .french: LocalizedStringResource("Français")
        }
    }
}
```

#### 2. `AppLanguagePreference` — new
**File**: `SingleThreadCore/Sources/SingleThreadCore/AppLanguagePreference.swift`
**Action**: create — near-copy of `AppearanceModePreference`, but on
`AppGroup.defaults` (mirrors `SortOption`).

```swift
import Foundation

/// Persists the app-language raw string in the App Group so the phone, widget,
/// and (via the sync wire) the watch agree. An absent or unrecognized value
/// resolves to `.system`, preserving today's behaviour.
public struct AppLanguagePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public static let defaultsKey = "appLanguage"

    /// Validated raw value; missing/unrecognized → `AppLanguage.system.rawValue`.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              AppLanguage.allCases.contains(where: { $0.rawValue == raw })
        else { return AppLanguage.system.rawValue }
        return raw
    }

    public func load() -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 3. `AppLocaleState` — new
**File**: `SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift`
**Action**: create. Core has **no** default MainActor isolation → annotate
explicitly. `import Observation` (the `@Observable` macro).

```swift
import Foundation
import Observation

/// Process-wide holder of the chosen language. One instance per process,
/// injected at the app and watch roots into `\.locale`; tests construct their
/// own with an isolated `UserDefaults` suite.
@MainActor
@Observable
public final class AppLocaleState {
    /// Shared instance used by the app and watch roots and by
    /// `SettingsBindings.appLanguage`.
    public static let current = AppLocaleState()

    public private(set) var language: AppLanguage

    public init(language: AppLanguage? = nil, defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.language = language ?? AppLanguagePreference(defaults: defaults).load()
    }

    /// Locale handed to SwiftUI's `\.locale` and to `resolved(in:)`.
    public var effectiveLocale: Locale { language.locale }

    /// Persists and publishes the choice. Writes through the preference store so
    /// any `UserDefaults.didChangeNotification` observer (sync push) sees it.
    public func set(_ language: AppLanguage) {
        AppLanguagePreference(defaults: defaults).setRawValue(language.rawValue)
        self.language = language
    }

    /// Locale for non-View, non-MainActor consumers (formatters, notification
    /// bodies, widget timeline build) — a plain store read, no actor hop.
    public nonisolated static var storedEffectiveLocale: Locale {
        AppLanguagePreference().load().locale
    }

    // MARK: Private

    private let defaults: UserDefaults
}
```

#### 4. Resolution helpers
**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify — append below `SharedStrings` (the accessors themselves
change in Phase 2).

```swift
// MARK: - Explicit-locale resolution

public extension LocalizedStringResource {
    /// Resolves this resource against an explicit locale. Views get this for
    /// free from `\.locale`; non-View callers use this or
    /// `resolvedInAppLanguage()`.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }

    /// Resolves against the persisted app-language preference.
    func resolvedInAppLanguage() -> String {
        resolved(in: AppLocaleState.storedEffectiveLocale)
    }
}
```

#### 5. `SettingsBindings.appLanguage` — modify
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify — add the store-backed computed property in the
“App-Group preferences” MARK, sourced from `AppLocaleState.current` so a synced
change also refreshes the picker:

```swift
/// Store-backed (App Group) like the other App-Group properties. Reads the live
/// `AppLocaleState` so a value delivered over WatchConnectivity also updates the
/// picker; the setter persists and republishes through the same holder.
var appLanguage: AppLanguage {
    get {
        access(keyPath: \.appLanguage)
        return AppLocaleState.current.language
    }
    set {
        withMutation(keyPath: \.appLanguage) {
            AppLocaleState.current.set(newValue)
        }
    }
}
```

#### 6. Interface Language Picker — modify
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify — add `@Binding var appLanguage: AppLanguage` (ungated, both
platforms), a Picker after the Text Size picker, and update both `#Preview`
constructors.

```swift
Picker(selection: $appLanguage) {
    ForEach(AppLanguage.allCases, id: \.self) { language in
        Text(language.title).tag(language)
    }
} label: {
    VStack(alignment: .leading) {
        Text("Language")
        SettingsCaption(text: "Choose the language for the app.")
    }
}
.accessibilityIdentifier("languagePicker")
```

The modifier attaches after the `label:` closure, exactly like the neighbouring
`appearancePicker` / `textSizePicker`.

#### 7. `AppearanceMode.title` / `TextSize.title` — modify
**Files**: `SingleThread/AppearanceMode.swift`, `SingleThread/TextSize.swift`
**Action**: modify — return `LocalizedStringResource` instead of eager `String`
(this is deviation 1):

```swift
var title: LocalizedStringResource {
    switch self {
    case .system: LocalizedStringResource("System", table: "Localizable", bundle: .main)
    case .light: LocalizedStringResource("Light", table: "Localizable", bundle: .main)
    case .dark: LocalizedStringResource("Dark", table: "Localizable", bundle: .main)
    }
}
```

`TextSize.title` likewise (`System`/`Small`/`Medium`/`Large`/`Extra Large`).
`Label(mode.title, systemImage:)` / `Label(size.title, …)` already accept
`LocalizedStringResource` (verified by compiling against the iOS 27 SDK).

#### 8. Wire the binding + root injection — modify
**Files**: `SingleThread/SettingsView.swift`, `SingleThread/SingleThreadApp.swift`
**Action**: modify

- `SettingsView.swift`: pass `appLanguage: $bindings.appLanguage` in **both**
  `#if os(iOS)` / `#elseif os(macOS)` `InterfaceSettingsView(...)` calls.
- `SingleThreadApp.swift` `WindowGroup`:

```swift
WindowGroup {
    ContentView(
        viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
        appViewModel: viewModel)
        .environment(\.locale, AppLocaleState.current.effectiveLocale)
    …
}
```

(`App.body` is `@MainActor`; reading `AppLocaleState.current.effectiveLocale`
here records the observation dependency. If the environment ever fails to
refresh live, the fallback is a tiny `RootView: View` wrapping `ContentView` —
verify in the Phase 1 manual check.)

#### 9. Catalog keys — add
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — add two App keys, each with all six languages
(`en, zh-Hans, es, ja, de, fr`), and the non-English values **must differ from
the English** (the `guardedCatalogs` identity guard):

| Key (exact `Text`/caption literal) | en |
|---|---|
| `Language` | `Language` |
| `Choose the language for the app.` | `Choose the language for the app.` |

Do **not** add catalog entries for `English`/`简体中文`/`Español`/`日本語`/
`Deutsch`/`Français` (deviation 4).

### Tests

**New** `SingleThreadTests/AppLanguageTests.swift` (`@testable import SingleThread`,
`import SingleThreadCore`, `import Testing`, `@MainActor` where the type needs it):

```swift
@Test
func languagePreferenceRoundTripsEveryCase() {
    let name = "test-applang-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }   // isolated
    let pref = AppLanguagePreference(defaults: suite, key: "appLanguage")
    for language in AppLanguage.allCases {
        pref.setRawValue(language.rawValue)
        #expect(pref.load() == language)
        #expect(pref.rawValue == language.rawValue)
    }
    // `.standard` untouched
    #expect(UserDefaults.standard.object(forKey: "appLanguage") == nil)
}

@Test
func languagePreferenceFallsBackToSystemOnUnknownRawValue() {
    let name = "test-applang-bad-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    suite.set("klingon", forKey: "appLanguage")
    #expect(AppLanguagePreference(defaults: suite, key: "appLanguage").load() == .system)
}

@Test
func localizedStringResourceResolvesInExplicitLocale() {
    // The one out-of-repo API risk: prove it before anything depends on it.
    let resource = LocalizedStringResource("Skip", table: "Localizable", bundle: Bundle.core)
    #expect(resource.resolved(in: Locale(identifier: "en")) == "Skip")
    #expect(resource.resolved(in: Locale(identifier: "de")) == "Überspringen")
}

@Test
func effectiveLocaleFollowsTheStoredLanguage() {
    let name = "test-applang-loc-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    AppLanguagePreference(defaults: suite, key: "appLanguage").setRawValue("de")
    let state = AppLocaleState(language: AppLanguagePreference(defaults: suite, key: "appLanguage").load(),
                               defaults: suite)
    #expect(state.effectiveLocale == Locale(identifier: "de"))
    state.set(.japanese)
    #expect(AppLanguagePreference(defaults: suite, key: "appLanguage").load() == .japanese)
}
```

Careful: `state.set` writes `defaults` passed in — pass `suite`.

Plus:

```swift
@Test
func endonymsRenderVerbatim() {
    // No catalog entry → the key is returned unchanged in every locale.
    #expect(AppLanguage.german.title.resolved(in: Locale(identifier: "ja")) == "Deutsch")
    #expect(AppLanguage.simplifiedChinese.title.resolved(in: Locale(identifier: "en")) == "简体中文")
}

@Test
func systemTitleLocalizesThroughTheCatalog() {
    #expect(AppLanguage.system.title.resolved(in: Locale(identifier: "de")) == "System")
}
```

**Modify** `SingleThreadTests/AppearanceModeTests.swift` and
`SingleThreadTests/TextSizeTests.swift`: replace `mode.title == String.en(…)`
with `mode.title.resolved(in: Locale(identifier: "en")) == …` (enum titles are
resources now).

**Modify** `SingleThreadTests/SettingsViewTests.swift`:
- both `InterfaceSettingsView(...)` constructors (lines ~88-128 and the
  `interfaceSettingsViewContainsExpectedRows` test) gain
  `appLanguage: .constant(.system)`.
- new `settingsScreenShowsLanguagePickerOnBothPlatforms` — mirror the existing
  differential constructor; assert on the built body description:

```swift
@Test
func settingsScreenShowsLanguagePickerOnBothPlatforms() {
    #if os(iOS)
        let view = InterfaceSettingsView(
            appearanceMode: .constant(.system), textSize: .constant(.system),
            appLanguage: .constant(.system), allowsLandscape: .constant(true),
            showMicrophoneButton: .constant(true), enableActionButtons: .constant(false),
            showSwipePrompt: .constant(true), showUndoButton: .constant(true),
            viewModel: SettingsViewModel())
    #else
        let view = InterfaceSettingsView(
            appearanceMode: .constant(.system), textSize: .constant(.system),
            appLanguage: .constant(.system), showMicrophoneButton: .constant(true),
            enableActionButtons: .constant(false), showMenuBarExtra: .constant(true),
            viewModel: SettingsViewModel())
    #endif
    let bodyDescription = String(describing: view.body)
    #expect(bodyDescription.contains("Language"))
    #expect(bodyDescription.contains("Choose the language for the app."))
    #expect(bodyDescription.contains("languagePicker"))
}
```

Also **modify** the two `InterfaceSettingsView` previews in
`InterfaceSettingsView.swift` to pass `appLanguage: .constant(.system)`.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/AppLanguageTests` — green, and the
      run reports the 6 cases (not a zero-match pass).
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` — green
      (includes the new picker test).
- [x] `scripts/test-one.sh SingleThreadTests/AppearanceModeTests` and
      `scripts/test-one.sh SingleThreadTests/TextSizeTests` — green.
- [x] `make build` — iOS app compiles (catches the `AppLocaleState` /
      `LocalizedStringResource` API usage).
- [x] `make format && make lint` — clean.

#### Manual
- [ ] Launch under a non-English system locale (e.g. set simulator language to
      German), open Settings → Interface, pick **English** — “Darstellung”
      becomes “Appearance”, the Appearance/Text Size picker values flip too, and
      the language row shows the endonyms. No relaunch.
- [ ] Cold-launch the app — the Interface screen is still English (persisted via
      the App Group suite), and `AppGroup.defaults` shows
      `appLanguage = en`.
- [ ] Pick **System** — labels return to the device language.

---

## Phase 2: Shared strings become deferred resources (app + watch + widget)

Outcome: every `SharedStrings.*` accessor, recurrence summary, priority display
name, and empty-state copy is a `LocalizedStringResource`; app, watch, and widget
render them in the chosen language. This is the repo's one **atomic,
compile-wide** change — the accessor return type changes, so all consumers land
in one commit.

### Changes

#### 1. `SharedStrings` accessors → resources
**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify — every `public static var <member>: String` becomes
`LocalizedStringResource` with the identical key/table/bundle; keep the existing
doc comments and `// periphery:ignore` markers.

```swift
public static var completeAction: LocalizedStringResource {
    LocalizedStringResource("Complete", table: "Localizable", bundle: .module)
}
```

`priorityAccessibilityLabel` changes signature so a localized level name nests
correctly:

```swift
public static func priorityAccessibilityLabel(_ levelName: LocalizedStringResource) -> LocalizedStringResource {
    LocalizedStringResource("\(levelName) priority", table: "Localizable", bundle: .module)
}
```

All 20 members change; the interpolation-bearing ones (`SharedStrings`
interpolated keys) keep their shape.

#### 2. `ReminderRecurrenceFormatter` → resource
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift`
**Action**: modify — `format(_:) -> LocalizedStringResource?` and each branch
returns `LocalizedStringResource("Every \(interval) days", table: "Localizable",
bundle: .module)` / `LocalizedStringResource("Daily", …)` etc. (all 8 keys:
Daily/Weekly/Monthly/Yearly + the four `Every N …` plural keys).

#### 3. `ReminderDisplay.recurrenceSummary` → resource
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify — `public let recurrenceSummary: LocalizedStringResource?`
and the convenience init default `recurrenceSummary: LocalizedStringResource? = nil`.

#### 4. `ReminderPriority.Level.displayName` → resource
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`
**Action**: modify — `public var displayName: LocalizedStringResource` with
`LocalizedStringResource("High"|"Medium"|"Low", table: "Localizable", bundle: .module)`.

#### 5. `EmptyStateCopy` → resources
**Files**: `SingleThread/ContentViewModel.swift`, `SingleThread/EmptyStateCard.swift`
**Action**: modify

```swift
struct EmptyStateCopy {
    let title: LocalizedStringResource
    let systemImage: String
    let description: LocalizedStringResource
}
```

`emptyStateCopy(hasHidden:)` / `allDoneStateCopy()` construct with
`LocalizedStringResource(…, table: "Localizable", bundle: .main)` and
`LocalizedStringResource(hiddenRemindersDescription, table: "Localizable", bundle: .main)`
(dynamic `String.LocalizationValue`s). `EmptyStateCard`’s `Text(copy.title)` /
`Text(copy.description)` already accept a resource.

#### 6. `SettingsLinkLabel.title → LocalizedStringResource`
**File**: `SingleThread/SettingsCaption.swift`
**Action**: modify — `let title: LocalizedStringResource`. String literals still
compile (`LocalizedStringResource` is `ExpressibleByStringLiteral`); replace the
one `LocalizedStringKey(SharedStrings.reminder)` at `SettingsView.swift:90`
with `SharedStrings.reminder` directly.

#### 7. Consumer compile fixes
**Files / patterns**: all `SharedStrings.` sites listed by
`rg -n 'SharedStrings\.' SingleThread SingleThreadWatch SingleThreadWidget`
(plus the recurrence/display-name sites above):

| Existing shape | New shape |
|---|---|
| `Text(SharedStrings.x)` | unchanged (accepts resource) |
| `Label(SharedStrings.x, systemImage:)` | unchanged (accepts resource — compile-verified) |
| `Button(SharedStrings.x) { }` / `Button(SharedStrings.x, role:)` | unchanged |
| `.accessibilityLabel(SharedStrings.x)` | unchanged |
| `.navigationTitle(SharedStrings.x)` / `CommandMenu(…)` / `ProgressView(…)` / `confirmationDialog(…)` / `alert(…)` / `Menu(…)` / `Section(…)` | unchanged (all compile-verified against the SDK) |
| `display.recurrenceSummary ?? SharedStrings.repeats` | unchanged — both now resources |
| `Text(hasHidden ? SharedStrings.a : SharedStrings.b)` | unchanged |
| `String`-typed param (e.g. any `title: String` still in the tree) | change the parameter to `LocalizedStringResource` |
| non-View `String` context | `SharedStrings.x.resolvedInAppLanguage()` |

If a `Label`/`Button` overload ever rejects a resource, the universally valid
fallback is `Label { Text(resource) } icon: { Image(systemName: …) }` — but all
forms above were compile-verified; do not pre-emptively rewrite them
(`swiftui-sdk` skill: compile, don't mine SDK files).

#### 8. Test updates
**Files**: `SingleThreadTests/ReminderRecurrenceFormatterTests.swift`,
`SingleThreadTests/ReminderDisplayTests.swift`,
`SingleThreadTests/ShowRecurrenceTests.swift`,
`SingleThreadTests/SingleThreadTests.swift`,
`SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — where a test compares a now-resource value to a
`String.en(…)`, compare `.resolved(in: Locale(identifier: "en"))` instead:

```swift
// ReminderRecurrenceFormatterTests
private func formatted(frequency: EKRecurrenceFrequency, interval: Int) -> String? {
    let rule = EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil)
    return ReminderRecurrenceFormatter.format([rule])?.resolved(in: Locale(identifier: "en"))
}
```

- `ShowRecurrenceTests.swift`: `recurrenceSummary: hasRecurrence ? "Weekly" : nil`
  still compiles (string literal → resource).
- `ReminderDisplayTests.swift`: resolve `display.recurrenceSummary` before
  comparing to the spec string.
- `SingleThreadTests.swift`: `.title`/`.description` assertions resolve with
  `.resolved(in: Locale(identifier: "en"))`.
- `ReminderSkipTests.swift`: `displayName` assertions resolve with
  `.resolved(in: Locale(identifier: "en"))`.

Add one new test (in `AppLanguageTests.swift`, deviation 2 keeps it near the
language machinery):

```swift
@Test
func sharedStringResolvesToEveryShippedLanguage() {
    let expected: [String: String] = [
        "en": "Skip", "zh-Hans": "跳过", "es": "Omitir",
        "ja": "スキップ", "de": "Überspringen", "fr": "Passer"
    ]
    // SharedStrings.skipAction is a resource in Phase 2.
    for (identifier, value) in expected {
        #expect(SharedStrings.skipAction.resolved(in: Locale(identifier: identifier)) == value,
                "Skip in \(identifier)")
    }
}
```

The existing `LocalizationTests` (catalog parse, six-language invariant, plurals,
`guardedCatalogs`) needs **no** change and must stay green — it is the safety net
for this phase.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` — green
      (proves the catalogs still satisfy the six-language + plural invariants).
- [x] `scripts/test-one.sh SingleThreadTests/AppLanguageTests` — green incl.
      `sharedStringResolvesToEveryShippedLanguage`.
- [x] `scripts/test-one.sh SingleThreadTests/ReminderRecurrenceFormatterTests` +
      `ReminderDisplayTests` + `ShowRecurrenceTests` + `SingleThreadTests` +
      `ReminderSkipTests` — green.
- [x] `make watch-build` — proves the watch consumers adapted to the resource
      shape (`watch-build` builds the watch target; the widget builds with the
      app).
- [x] `make build` — the widget/app consumers compile.
- [x] `make format && make lint` — clean.

#### Manual
- [ ] Launch, pick Deutsch: the main screen’s Complete/Skip/Delete/All Done/No
      Reminders labels, the recurrence summary on a repeating reminder, and the
      empty-state card all show German.
- [ ] `rg -n 'String\(localized:' SingleThread SingleThreadCore SingleThreadWatch SingleThreadWidget`
      — every remaining hit is either Phase 4/5 content or the debug-only
      exceptions (no `SharedStrings` accessor left eager).

---

## Phase 3: Phone → watch → widget propagation

Outcome: the chosen language reaches the watch and widget; both render in it
without the phone open, surviving relaunch.

### Changes

#### 1. Sync payload key + store — modify
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

- `PayloadKey`: add `static let appLanguage = "appLanguage"`.
- Add stored properties `appLanguageStore: AppLanguagePreference` and
  `sendsAppLanguage: Bool`; add init params with defaults
  `appLanguageStore: AppLanguagePreference = AppLanguagePreference()` and
  `sendsAppLanguage: Bool = false` (mirroring `sendsShowDate`). Assign in `init`.
- `pushAll()` — after the `sortOption` entry, add:

```swift
if sendsAppLanguage {
    context[PayloadKey.appLanguage] = appLanguageStore.load().rawValue
}
```

- Add the write-once hook next to the other `on…Received` hooks:

```swift
/// Hook invoked on the counterpart watch when the iPhone's chosen language
/// arrives. Same write-once-before-activate / `nonisolated(unsafe)` rationale
/// as `onShowDateReceived`.
public nonisolated(unsafe) var onAppLanguageReceived: ((AppLanguage) -> Void)?
```

- `apply(context:)` — add (mirroring the `sortOption` decode):

```swift
if let rawValue = context[PayloadKey.appLanguage] as? String {
    appLanguageStore.setRawValue(rawValue)
    let handler = onAppLanguageReceived
    handler?(AppLanguage(rawValue: rawValue) ?? .system)
}
```

Absent key ⇒ no-op, so a fresh watch keeps its own stored/system default.

#### 2. Phone push trigger + widget reload — modify
**Files**: `SingleThread/AppViewModel.swift`, `SingleThread/ContentView+Settings.swift`
(research: the `UserDefaults.didChangeNotification` diff lives at
`AppViewModel.swift:438-479`), `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

- In the existing App-Group `didChangeNotification` diff, add an
  `appLanguage` last-seen raw value: when it changes, call
  `AppLocaleState.current.set(AppLanguagePreference().load())` (idempotent) and
  `service.pushAll()`. This covers writes from the picker **and** any other
  writer of the key.
- Phone `AppViewModel` builds `SkippedReminderSyncService` with
  `sendsAppLanguage: true`.
- `InterfaceSettingsView`: add

```swift
.onChange(of: appLanguage) { _, _ in
    viewModel.showPreferenceChanged()
}
```

  on the Language Picker so the existing `WidgetCenter.shared.reloadAllTimelines()`
  chokepoint fires on a language change.

#### 3. Watch receive + root injection — modify
**Files**: `SingleThreadWatch/WatchAppViewModel.swift`,
`SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

- `makeSyncService()`: pass
  `appLanguageStore: AppLanguagePreference(defaults: .standard)` and
  `sendsAppLanguage: false`.
- `wireStateReceiveHooks(_:)`: add

```swift
service.onAppLanguageReceived = { value in
    Task { @MainActor in AppLocaleState.current.set(value) }
}
```

- `SingleThreadWatchApp`:

```swift
WindowGroup {
    WatchReminderView(viewModel: viewModel.reminderViewModel)
        .environment(\.locale, AppLocaleState.current.effectiveLocale)
}
```

`AppLocaleState.current` on watchOS seeds from `AppGroup.defaults`, which falls
back to `.standard` (`AppGroup.swift:16-17`) — the same suite the sync store
writes, so the wire value and the launch seed cannot diverge.

#### 4. Watch literals → catalog keys — modify
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify — localize the four bypassing literals at lines
`55, 167, 303, 319` (from `research.md` Q4). Each is a `Text("…")` literal, so
**no code change is needed for the deferral** — add the missing key to the Watch
catalog (`SingleThreadWatch/Resources/Localizable.xcstrings`) with all six
languages (Watch is not in `guardedCatalogs`, but translate anyway).
The DatePicker at `:297` needs no code change: it follows the injected
`.environment(\.locale)`.

#### 5. Widget locale — modify
**File**: `SingleThreadWidget/NextThingWidget.swift`
**Action**: modify — inside the `StaticConfiguration` view closure:

```swift
NextThingWidgetView(entry: entry)
    .environment(\.locale, AppLanguagePreference().load().locale)
    .containerBackground(.fill.tertiary, for: .widget)
```

The widget target has a real App Group (unlike watchOS), so
`AppLanguagePreference()` reads the phone’s choice at timeline build.
`Text(dueDate, style: .date)` at `:209` then follows the injected locale.

#### 6. Watch catalog keys — add
**File**: `SingleThreadWatch/Resources/Localizable.xcstrings`
**Action**: modify — add the four literals from `WatchReminderView.swift` as keys
with six languages.

### Tests

**New** `SingleThreadTests/AppLanguageSyncTests.swift` — mirror
`EnableActionButtonsSyncTests.swift`:
`#if os(iOS) || os(watchOS)`, `@Suite(.serialized)` (it uses real App Group keys
unless injected), `makeTestSortStore()`-style helpers:

```swift
@Test
func pushPayloadCarriesLanguageWhenSet() throws {
    let fake = FakeSession()
    let suffix = UUID().uuidString
    let pref = AppLanguagePreference(defaults: .standard, key: "test-applang-push-\(suffix)")
    pref.setRawValue("de")
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-ids-\(suffix)"),
        appLanguageStore: pref, sendsAppLanguage: true)
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect((context["appLanguage"] as? String) == "de")
}

@Test
func pushPayloadOmitsLanguageWhenNeverSet() throws {
    // sendsAppLanguage false (the watch configuration) → key absent; a fresh
    // device keeps its own stored/system value.
    let fake = FakeSession()
    let suffix = UUID().uuidString
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-abs-\(suffix)"))
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["appLanguage"] == nil)
}

@Test
func applyContextPersistsLanguageAndFiresHook() {
    let fake = FakeSession()
    let suffix = UUID().uuidString
    let pref = AppLanguagePreference(defaults: .standard, key: "test-applang-recv-\(suffix)")
    defer { UserDefaults.standard.removeObject(forKey: "test-applang-recv-\(suffix)") }
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "test-applang-recvids-\(suffix)"),
        appLanguageStore: pref)
    var received: [AppLanguage] = []
    service.onAppLanguageReceived = { received.append($0) }
    service.session(WCSession.default, didReceiveApplicationContext: ["appLanguage": "ja"])
    #expect(pref.load() == .japanese)      // persisted
    #expect(received == [.japanese])       // then notified
    service.session(WCSession.default, didReceiveApplicationContext: ["skippedReminderIdentifiers": ["X"]])
    #expect(received == [.japanese])       // absent key is a no-op
}
```

**New watch test** under `SingleThreadWatchTests/` (run via `make watch-test`):
decode + locale-state update — `watchAppLanguageReceiveUpdatesLocaleState`.
Construct a `SkippedReminderSyncService` with an isolated `.standard` key, call
`session(_:didReceiveApplicationContext:)`, assert the injected
`AppLanguagePreference` and `AppLocaleState` update. Keep the name free of a
`test` prefix.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/AppLanguageSyncTests` — green, 3 cases ran.
- [x] `make watch-test` — green incl. `watchAppLanguageReceiveUpdatesLocaleState`.
- [x] `make watch-build` — watch app + widget compile.
- [x] `make format && make lint` — clean.

#### Manual
- [ ] Pair a watch sim (see `simulator-pairing` skill), launch both apps, pick
      **日本語** on the phone; the watch UI flips without a relaunch.
- [ ] Put a widget on the Home Screen, change language on the phone; the widget
      timeline refreshes and the due-date row renders in the new language.
- [ ] Relaunch the watch app with the phone closed — it stays in 日本語
      (`.standard` seed).

---

## Phase 4: Reminder + main-screen surfaces localized

Outcome: every reminder-facing screen renders fully in the chosen language.

Reminder: literal `Text("…")` / `SettingsCaption(text: "…")` already defer — the
work here is (a) adding **missing catalog keys**, and (b) converting eager
`String(localized:)` sites to resources. `research.md` Q4 gives the exact line
numbers.

### Changes

#### 1. Add missing App catalog keys
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — for each literal below, if the exact string is **not** a key
in the App catalog, add it with all six languages (non-English must differ from
English). The `research.md` Q4 App list is the checklist:

- `ContentView.swift`: `592` (`You've cleared \(count) today`),
  `390` (`Enable access in Settings…`).
- `ReminderCardView.swift`: `189, 196, 206` (swipe hints / `Dismiss`).
- `FilterSortSettingsView.swift`: `27, 34, 49`.
- `InterfaceSettingsView.swift`: `44, 56, 65, 80, 91, 103, 116, 128` — most
  already exist (`Allow landscape`, `Show microphone`, `Show action buttons`,
  `Show swipe prompt`, `Show undo button`, `Show in Menu Bar`); verify with
  `rg '"<literal>"' SingleThread/Resources/Localizable.xcstrings` and only add
  the genuinely missing ones.
- `ReminderSettingsView.swift`: `28, 44, 55, 71, 98`.
- `NotificationsSettingsView.swift`: `16, 25-27, 30`.
- `BackgroundSettingsView.swift`: `23, 33, 37, 46`.
- `RescheduleSheet.swift`: `25`; `ExcludedListsView.swift`: `27`.
- Debug-only literals (`ContentView+iOS.swift:26,28`, `ContentView.swift:331,
  701,711,721`) are **out of scope** (decision 2) — add a one-line comment where
  they sit? No: leave untouched.

#### 2. Convert eager `String(localized:)` sites to resources
**Files**: `SingleThread/ContentView.swift` (`218, 733, 758`),
`SingleThread/ReminderDictation.swift` (`227, 239`),
`SingleThread/ReminderCardView.swift` (`128`),
`SingleThread/CreationFeedback.swift` (`29-30`),
`SingleThread/ContentViewModel.swift` (`105`), and the non-View Core sites below.
**Action**: modify — replace
`String(localized: "key", table: "Localizable", bundle: .main)` with
`LocalizedStringResource("key", table: "Localizable", bundle: .main)` handed to
the view; where the value must stay a `String` (non-View storage), use
`.resolvedInAppLanguage()`.

#### 3. Non-View / formatter / scheduler sites
**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderRecurrenceFormatter.swift`,
`SingleThreadCore/Sources/SingleThreadCore/NotificationScheduler.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift`
**Action**: modify

- `NotificationScheduler.swift:82,84` (`@MainActor`): keep `String` content
  (UNMutableNotificationContent needs a String) but resolve against the chosen
  locale:

```swift
content.title = LocalizedStringResource(
    "SingleThread", table: "Localizable", bundle: .main).resolvedInAppLanguage()
content.body = LocalizedStringResource(
    "You have \(reminderCount) reminders waiting — open SingleThread!",
    table: "Localizable", bundle: .main).resolvedInAppLanguage()
```

- `ReminderSkip.swift` `displayName` was already converted in Phase 2 — verify no
  eager `String(localized:)` remains there.
- `ReminderRecurrenceFormatter.swift` was converted in Phase 2 to resources;
  verify no `String(localized:)` remains.

#### 4. `SortOption.title` → resource
**File**: `SingleThread/SortOption+Presentation.swift`
**Action**: modify — `var title: LocalizedStringResource`; the
`FilterSortSettingsView` label and `SingleThreadTests/SortOptionTests.swift`
assertions update to `.resolved(in: Locale(identifier: "en"))`.

### Tests

**Modify** `SingleThreadTests/LocalizationTests.swift` — no structural change
needed: the existing “every key carries all six languages” + identity guard
already covers every key added above. (Do **not** add a hardcoded list of keys;
the catalog-wide invariant is the contract.)

**Add** per-converted-site assertion tests:
- `SortOptionTests.swift` → `.resolved(in:)`.
- A new `@Test` in `SingleThreadTests/SingleThreadTests.swift` (or the existing
  empty-state test) proving a converted Phase-4 string resolves in a non-English
  locale, e.g. `LocalizedStringResource("Reschedule", table: "Localizable",
  bundle: .main).resolved(in: Locale(identifier: "de"))` equals the catalog’s
  German value.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` — green.
- [x] `scripts/test-one.sh SingleThreadTests/SingleThreadTests` — green.
- [x] `scripts/test-one.sh SingleThreadTests/SortOptionTests` — green.
- [x] `make format && make lint` — clean.
- [x] `rg -n 'String\(localized:' SingleThread SingleThreadCore` — only Phase 5
      sites and the debug-only exceptions remain.

#### Manual
- [ ] Run the reminder flows (card, dictate, reschedule, empty state, filter/sort
      settings) in **Deutsch** and **日本語** — no leftover English on any
      reminder-facing screen.

---

## Phase 5: Settings, purchase, and about surfaces localized

Outcome: the remaining non-reminder screens render fully in the chosen language.
Same mechanical shape as Phase 4.

### Changes

#### 1. Add missing App catalog keys
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify — `research.md` Q4 checklist:

- `InterfaceSettingsView.swift` — any remaining literal not covered in Phase 4.
- `ReminderSettingsView.swift`, `NotificationsSettingsView.swift`,
  `BackgroundSettingsView.swift` — remaining literals.
- `PurchaseSettingsView.swift` (`27, 30, 32, 35, 45, 51, 128`) — note `Purchase`
  is currently **missing** as a key (verified); add it plus the others.
- `AboutView.swift` (`27-28`), `RescheduleSheet.swift`/`ExcludedListsView.swift`
  leftovers.
- `SingleThreadApp+Commands.swift:46-48` — the appearance tag labels
  (`System`/`Light`/`Dark`) already exist as keys; `AppearanceMode.title` now
  returns a resource (Phase 1), so the tags resolve through the catalog too.

For every literal: `rg '"<literal>"' SingleThread/Resources/Localizable.xcstrings`
first; add only if missing; all six languages; non-English must differ from
English.

#### 2. `MenuBarExtraOptions` locale
**File**: `SingleThread/MenuBarExtraOptions.swift`
**Action**: modify — no code change beyond Phase 1’s root injection; the
`Button(SharedStrings.completeReminder)` sites already take resources and the
macOS `MenuBarExtra` scene inherits `\.locale` from the `WindowGroup`’s
environment? **No** — a `Scene` is siblings with the `WindowGroup`, so the
`MenuBarExtra` content does not inherit it. Add the environment explicitly to the
`MenuBarExtra` content in `SingleThreadApp.swift`:

```swift
MenuBarExtra("SingleThread", systemImage: "checkmark.circle",
             isInserted: $showMenuBarExtra) {
    MenuBarExtraOptions(store: viewModel.store)
        .environment(\.locale, AppLocaleState.current.effectiveLocale)
}
.menuBarExtraStyle(.menu)
```

`Text(due, format: .dateTime)` at `MenuBarExtraOptions.swift:20` then follows it.

#### 3. macOS commands locale
**File**: `SingleThread/SingleThreadApp+Commands.swift`
**Action**: modify — the `CommandMenu(SharedStrings.reminder)` and `Button(…)`
sites already take resources; the macOS menu is built outside the view
environment, so append `.environment(\.locale, AppLocaleState.current.effectiveLocale)`
to the label/content where a resource must resolve (verify the command labels
switch in the macOS manual pass; macOS commands are not covered by the iOS UI
test).

### Tests

- `LocalizationTests` covers every added key (six languages + identity guard).
- Per-site `.en`/locale assertions for any newly converted `String`-typed
  property (there are none new expected beyond Phase 4).
- `SettingsViewTests` must stay green (its body-description assertions cover the
  settings labels).

### Verification

#### Automated
- [ ] `scripts/test-one.sh SingleThreadTests/LocalizationTests` — green.
- [ ] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` — green.
- [ ] `make lint` — clean.
- [ ] `rg -n 'String\(localized:' SingleThread SingleThreadCore` — only debug-only
      exceptions remain (`ContentView+iOS.swift:26,28`,
      `ContentView.swift:331,701,711,721`).

#### Manual
- [ ] Walk the full settings stack + purchase + about + macOS menu bar in
      **Deutsch** and **日本語** — no leftover English.

---

## Phase 6: Hardening — the locale change sticks everywhere

Outcome: switching language mid-session leaves nothing stale; an unsupported
stored raw value degrades to *System*.

### Changes

#### 1. Navigation-title re-identity (the iOS 18 risk)
**File**: `SingleThread/ContentView.swift`
**Action**: modify — first test manually whether navigation titles re-localize.
If they do not, re-key the stack on the environment locale:

```swift
@Environment(\.locale) private var locale
…
NavigationStack { … }
    .id(locale)
```

Document the decision in the PR (either “verified re-localize, no `.id` needed”
or the `.id(locale)` with its navigation-reset trade-off).

#### 2. Sheets pick up the new locale
**File**: `SingleThread/ContentView.swift`
**Action**: modify — the settings sheet (`settingsSheetContent`, ~`:607-612`) is
built at presentation time. If it keeps the old locale, append
`.environment(\.locale, AppLocaleState.current.effectiveLocale)` to its content
(in the same `#if os(macOS)` frame chain region). Same for the reschedule sheet
if it shows stale text (verify manually).

#### 3. Unsupported stored value degrades
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — this is already guaranteed by
`AppLanguagePreference.rawValue` (Phase 1). Confirm no other path writes an
unvalidated raw value. Add the `--ui-testing-app-language <raw>` seam for the UI
sad path (deviation 5), placed **after** `resetPersistedState` in the
`--ui-testing` branch so it is not wiped:

```swift
if let index = arguments.firstIndex(of: "--ui-testing-app-language"),
   index + 1 < arguments.count {
    AppLanguagePreference().setRawValue(arguments[index + 1])
    AppLocaleState.current.set(AppLanguagePreference().load()) // validates → .system
}
```

#### 4. Audit
**Files**: none (grep gate)
**Action**: run the audit and fix anything it finds:

```bash
rg -n 'String\(localized:' SingleThread SingleThreadCore SingleThreadWatch SingleThreadWidget
rg -n 'SharedStrings\.' SingleThread SingleThreadWatch SingleThreadWidget
```

- [ ] No prod `String(localized:)` site outside the debug-only exceptions and
      the intentional non-View `.resolvedInAppLanguage()` conversions.
- [ ] No `SharedStrings.` accessor consumed as a bare `String`.

#### 5. Widget / watch refresh confirmation
**Files**: `SingleThreadWidget/NextThingWidget.swift`,
`SingleThreadWatch/WatchReminderView.swift`
**Action**: verify (no code change expected) — both read their locale at build
or from the synced state, so a mid-session change on the phone must arrive via
the Phase 3 wire (`watchAppLanguageReceiveUpdatesLocaleState`) and the widget
via `reloadAllTimelines()`. If the widget still shows the old language after a
change, the fault is the reload chokepoint (Phase 3, step 2) — fix there, not in
the widget view.

#### 6. UI test
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify — add the end-to-end language test. **Justification (state in
the PR):** this is a new end-to-end user flow whose value only manifests at the
UI layer (environment-locale propagation through the settings sheet, nav titles,
and picker values); no unit test can observe it.

```swift
@MainActor
func testLanguageSelectionChangesVisibleString() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
    app.buttons["settingsButton"].tap()
    XCTAssertTrue(app.buttons["settingsInterfaceRow"].waitForExistence(timeout: 5))
    app.buttons["settingsInterfaceRow"].tap()

    // English baseline, then switch to Deutsch.
    XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
    app.buttons["languagePicker"].tap()
    app.staticTexts["Deutsch"].tap()

    // The Interface screen's own label re-localizes with no relaunch.
    XCTAssertTrue(
        app.staticTexts["Darstellung"].waitForExistence(timeout: 5),
        "Appearance label should re-localize to German after selection")
    XCTAssertFalse(app.staticTexts["Appearance"].exists)
}
```

Second case (sad path) as a separate XCTest method:

```swift
@MainActor
func testUnsupportedStoredLanguageFallsBackToSystem() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--ui-testing-app-language", "klingon"]
    app.launch()
    app.buttons["settingsButton"].tap()
    app.buttons["settingsInterfaceRow"].tap()
    // .system under the (English) test locale → the source labels render.
    XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
}
```

(Adjust the German value if the catalog’s `Appearance` translation differs —
`research`-verified it is `Darstellung`.)

### Verification

#### Automated
- [ ] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLanguageSelectionChangesVisibleString`
      — green, and the run executed ≥1 case.
- [ ] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testUnsupportedStoredLanguageFallsBackToSystem`
      — green.
- [ ] `make format && make lint` — clean.

#### Manual
- [ ] Switch language while a reminder card and a reschedule sheet are open — the
      sheet’s chrome (DatePicker month names) follows the new locale.
- [ ] macOS (if in scope for the session): menu bar extra + Commands menu labels
      switch.

#### Full gate
- [ ] After all six phases are committed, launch the **`run-gate` skill** (one
      async gate subagent in a managed worktree, multi-hour timeout) to run
      `./scripts/test.sh` **once**. Do not `nohup` it ad-hoc.
- [ ] Before merging: `git rm DELETEME` (branch-bootstrap marker).

---

## Testing checkpoints

| After | Must be green before advancing |
|---|---|
| Phase 1 | `scripts/test-one.sh SingleThreadTests/AppLanguageTests` + `SettingsViewTests` + `AppearanceModeTests` + `TextSizeTests`; `make build` |
| Phase 2 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + updated `.en` suites; `make watch-build` |
| Phase 3 | `scripts/test-one.sh SingleThreadTests/AppLanguageSyncTests`; `make watch-test`; `make watch-build` |
| Phase 4 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + `SingleThreadTests` + `SortOptionTests`; `make lint` |
| Phase 5 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + `SettingsViewTests`; `make lint` |
| Phase 6 | the two UI tests above; then `./scripts/test.sh` once via `run-gate` |

## Known-good API facts (compile-verified this session against the iOS 27 SDK)

- `LocalizedStringResource("key", table: "Localizable", bundle: Bundle.main)` and
  `bundle: .module` compile; the `bundle:` argument accepts a `Bundle` and
  `.main`/`.module` descriptions.
- `LocalizedStringResource` has a mutable `locale`; `String(localized: resource)`
  exists (the `resolved(in:)` helper body).
- `Text`, `Label(_:systemImage:)`, `Button(_:action:)`,
  `.accessibilityLabel(_:)`, `.navigationTitle(_:)`, `.confirmationDialog(_:isPresented:)`,
  `.alert(_:isPresented:)`, `Picker`/`Section`/`Menu`/`ProgressView` labels all
  accept a `LocalizedStringResource`. `CommandMenu(_:)` accepts it on macOS.
- `LocalizedStringKey(resource)` does **not** exist — `SettingsLinkLabel.title`
  becomes `LocalizedStringResource` instead of bridging via `LocalizedStringKey`.
- `LocalizedStringResource("\(innerResource) priority", …)` compiles (used by
  `SharedStrings.priorityAccessibilityLabel`).
- `LocalizedStringResource` is `ExpressibleByStringLiteral`, so
  `SettingsLinkLabel(title: "Interface")` keeps compiling after the type change.

## Open questions

None — every ambiguity above is resolved by an explicit decision (see
“Deviations”). If Phase 6’s manual check shows nav titles or sheets do not
re-localize and `.id(locale)` / explicit `.environment` cannot fix it without
breaking navigation state, stop and report rather than shipping a stale title.
