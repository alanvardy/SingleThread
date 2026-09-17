# Design Discussion

## Current State

The app renders in the **system locale** and has no user-selectable language.

- `InterfaceSettingsView` holds `@Binding` fields for `appearanceMode` and
  `textSize` (`SingleThread/InterfaceSettingsView.swift:9-10`) and renders two
  Pickers in its "Interface" section (`:37-50`, `:58-75`), each with an
  `.accessibilityIdentifier`. There is no Language row.
- Preferences reach the view through `SettingsBindings`, an `@Observable
  @MainActor` class with 13 defaulted init params (`SettingsBindings.swift:15-35`).
  Two plumbing patterns coexist:
  - `@AppStorage`-backed bag fields plus explicit `.onChange` write-backs —
    `appearanceMode`/`textSize` live in **`UserDefaults.standard`**
    (`ContentView.swift:71-76`; write-back `ContentView+Settings.swift:11-21`;
    bag seed `:46-71`).
  - Store-backed computed properties writing straight through core
    `UserDefaults` stores in `AppGroup.defaults` (`SettingsBindings.swift:104-114`;
    header `:1-10`). `SortOption` is the enum-valued precedent (`SortOption.swift:18`,
    `SortOptionStore`).
- Enum persistence precedent: `AppearanceModePreference` — `UserDefaults`-backed,
  `defaultsKey`, `load`/`setRawValue`, missing/unrecognized → default
  (`AppearanceModePreference.swift:8-35`).
- `AppGroup.defaults = UserDefaults(suiteName: "group.app.alanvardy.SingleThread")
  ?? .standard` (`SingleThreadCore/.../AppGroup.swift:11-17`). On watchOS the
  suite is unregistered, so it falls back to `.standard` — the wire, not the
  suite, is the watch's live channel.
- Phone→watch sync is a generic keyed mechanism: one combined application
  context in `SkippedReminderSyncService.pushAll()`
  (`SkippedReminderSyncService.swift:216-257`, keys `:344-361`), gated per key
  (e.g. `enableActionButtons` only when `.isSet`, `:229-231`), decoded by
  `apply(context:)` (`:423-441`) into per-key hooks. The watch wires hooks in
  `WatchAppViewModel.wireStateReceiveHooks()` (`:249-284`) onto `@Observable`
  holders like `ShowDateState` (`ShowDateState.swift:9-31`).
- Localization is four `.xcstrings` catalogs (App 137 keys, Core 33, Watch 7,
  Widget 5), each key carrying exactly six languages `en, zh-Hans, es, ja, de, fr`
  (`SingleThreadTests/LocalizationTests.swift:222`). Core exposes 20 typed
  `SharedStrings` accessors returning **eager `String`**
  (`LocalizedString+Shared.swift:11-99`); watch and widget consume only those.
- The locale-pinning seam already exists: `String(localized:table:bundle:locale:)`
  with an explicit `Locale` (`LocalizationTestHelpers.swift:7-13`). Prod code
  never passes a `locale:` and never sets SwiftUI's `\.locale`.
- ~47 user-facing literals bypass the catalogs entirely (app + watch; see Q2 in
  `research.md`). Locale-sensitive rendering sites: `Text(date, style:)` at
  `ReminderCardView.swift:102`, `NextThingWidget.swift:209`,
  `WatchReminderView.swift:338`, `MenuBarExtraOptions.swift:20`; `DatePicker` at
  `WatchReminderView.swift:297` and `RescheduleSheet.swift:67`.

Grounding fact from outside the repo: SwiftUI resolves `LocalizedStringKey` /
`LocalizedStringResource` handed directly to a view against the environment's
`\.locale`, but `String(localized:)` resolves **eagerly against the system
locale** and ignores the environment. Non-view APIs (`Locale.current`,
`DateFormatter`) likewise ignore it.

## Desired End State

A user opens Settings → Interface, picks "Language", selects one of
**System, English, 简体中文, Español, 日本語, Deutsch, Français**, and the app's
UI switches language **immediately, without relaunch**: navigation titles,
labels, buttons, catalog strings, `Text(date, style:)` output and `DatePicker`
chrome all render in the chosen language. The choice persists in the shared App
Group, survives relaunch, and is reflected on the paired watch and in the
widget.

Verification: an in-process unit test proves the resolved locale drives a
localized lookup and that the store round-trips; a differential view-construction
test proves the new Picker exists on both platforms; `LocalizationTests` remains
green with the six-language invariant; a targeted UI test (justified: this is an
end-to-end user flow that only manifests at the UI layer) selects a language and
asserts a visible string changed.

## Patterns to Follow

Good patterns to copy:

- **Enum preference store**: `AppearanceModePreference.swift:8-35` — `defaultsKey`,
  `load(from:)` with unrecognized → default, `setRawValue`. `AppLanguagePreference`
  should be a near-copy over `AppGroup.defaults`.
- **Store-backed computed property on `SettingsBindings`**: `SettingsBindings.swift:104-114`
  — no `@AppStorage`, no `.onChange` write-back. Preferred over the
  `appearanceMode` standard-suite pattern because it writes straight to
  `AppGroup.defaults` and posts `didChangeNotification`.
- **Keyed sync payload**: `SkippedReminderSyncService.swift:216-257` + per-key
  receive hook (`:455-458`, `:461-464`) + watch `@Observable` holder
  (`ShowDateState.swift:9-31`). Mirror exactly for `language`.
- **Deferred resources**: hand `LocalizedStringResource` directly to `Text` so
  the environment applies; `LocalizedString+Shared.swift` becomes the single
  place that changes shape.
- **Pinned-locale tests**: `LocalizationTestHelpers.swift:7-13` `String.en` — the
  new helper's behaviour should be testable the same way.
- **Store tests**: `BoolPreferenceStoreTests.swift` — UUID-randomized keys,
  `defer` cleanup, isolated `UserDefaults(suiteName:)` to prove `.standard` is
  never written. `SettingsViewTests.swift:18-28` for the bag round-trip and
  `:88-128` for the differential constructor.
- **Widget reload chokepoint**: `SettingsViewModel.swift:21-23` already calls
  `WidgetCenter.shared.reloadAllTimelines()` on preference change.

Bad / mismatched patterns — do **not** copy:

- `appearanceMode`/`textSize`'s `@AppStorage` on the **standard suite**
  (`ContentView.swift:71-76`). A shared value on the wrong suite diverges
  silently on simulator (AGENTS.md App Group rule).
- Eager `Text(String(localized: ...))` and `Text(someSharedString)` — invisible
  to the environment; these are exactly the call sites that will not switch.
- `SharedStrings` accessors returning `String` (`LocalizedString+Shared.swift:16-98`)
  — must become deferred resources.
- Hardcoded view literals (`InterfaceSettingsView.swift:44,56,65,...`; watch
  `WatchReminderView.swift:55,167,...`) — the reason a switcher looks broken.
- Unreferenced watch/widget catalog keys (`LocalizationTests.swift:236-237`) —
  dead translations; don't add more.
- `NotificationScheduler.swift:82`'s `bundle: .main` from Core — outlier; not a
  template.

## Design Decisions

1. **Override mechanism**: environment-based, no restart — inject
   `.environment(\.locale, effectiveLocale)` at the root from an `@Observable`
   locale holder, convert `SharedStrings` to `LocalizedStringResource`, convert
   eager `Text(String(localized:))` sites to deferred keys, and add a
   locale-aware resolve helper (`resource.locale = locale; String(localized:)`)
   for non-View contexts. — Instant switching, testable in-process, and it makes
   `Text(date, style:)`/`DatePicker` follow automatically. The `AppleLanguages`
   + restart alternative was rejected: relaunch-gated, untestable, and it does
   not reach the watch.

2. **Literal scope**: localize every user-facing bypassing literal in app + watch
   now, excluding debug-only strings (`ContentView+iOS.swift:26,28`,
   `ContentView.swift:331`, `:701,711,721`). — A language switcher that leaves
   whole screens in English is not a shipped feature; the catalog six-language
   invariant makes the work mechanical.

3. **Platform reach**: app + watch + widget. — Matches the ticket's "phone +
   watch" wording and the App Group rule. Watch gets a synced wire key (suite is
   unavailable there); widget reads the store at timeline build and is refreshed
   through the existing `reloadAllTimelines()` chokepoint.

4. **Options and placement**: "System" plus all six shipped languages, as an
   `AppLanguage` enum; new Picker in `InterfaceSettingsView` after Text Size, on
   both iOS and macOS settings screens, and no new macOS `CommandMenu` entry.
   — "System" preserves today's behaviour as the default; the settings-screen-only
   surface keeps the differential-constructor test (and its 14 `#if os` gates)
   the single place to prove presence.

5. **Persistence and propagation**: core `AppLanguage` enum +
   `AppLanguagePreference` on `AppGroup.defaults`, surfaced as a store-backed
   computed property on `SettingsBindings`, synced as a new payload key with a
   watch-side `@Observable` locale state. — Follows the `SortOption`/`ShowDateState`
   precedent instead of the standard-suite `@AppStorage` pattern, so the watch
   actually receives it.

## What We're NOT Doing

- No `AppleLanguages`/`AppleLocale` UserDefaults hack and no "restart to apply"
  prompt.
- No new test target, no pbxproj target restructuring.
- No RTL work: none of the six languages is RTL, so `\.layoutDirection` is not
  driven (noted as a future extension, not implemented).
- No locale-aware reformatting of numbers via `NumberFormatter` — the only
  numeric strings are cataloged interpolations (`ReminderRecurrenceFormatter.swift:11-30`,
  `NotificationScheduler.swift:84`, `AppInfo.swift:40-46`).
- No change to `Calendar.current` date arithmetic
  (`ReminderDateFilter.swift:30-57`, `DailyCompletionStore.swift:49`) — that is
  calendar/region, not display language.
- No macOS `CommandMenu("Appearance")` language entry.
- No translation of debug-only strings.
- No new languages beyond the shipped six; no per-key catalog divergence
  (`guardedCatalogs`, `LocalizationTests.swift:249-252` stays intact).

## Open Risks

- **Eager-resolution completeness**: any `String(localized:)` site missed during
  conversion silently stays in the system locale. Mitigation: grep-audit all
  `String(localized:` and `SharedStrings.` call sites listed in `research.md`
  before the gate.
- **iOS 18 toolbar-title refresh**: navigation titles may not re-localize on a
  locale change. May need a re-identity (`.id(...)`) on the `NavigationStack`,
  which resets navigation state — to be confirmed at plan/build time.
- **Sheets built at presentation time** can keep the old locale; the settings
  sheet (`ContentView.swift:607-612`) may need an explicit
  `.environment(\.locale, ...)` on its content.
- **Watch/widget separate processes**: the widget's locale is read at timeline
  build; correctness depends on `reloadAllTimelines()` actually firing after a
  change, and the widget's `.environment(\.locale,)` must be set inside the
  widget view.
- **`String(localized:)` on `LocalizedStringResource` with an explicitly set
  `locale`** is the one API behaviour outside the repo that the helper depends
  on; the plan must prove it with a compiling test before relying on it.
- **Content lift**: ~40 new keys × 6 languages; translation quality (not just
  presence) is not verified by `LocalizationTests`, which only checks the six
  languages exist.
- **macOS settings differences**: `SettingsViewTests.swift:88-128` and the 14
  `#if os(` gates mean the new Picker needs explicit coverage on both branches.