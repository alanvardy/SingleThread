# Structure Outline

## Approach

Add a store-backed `AppLanguage` preference (`AppGroup.defaults`) surfaced as a
`SettingsBindings` computed property and a Settings → Interface Picker, and drive
rendering with a root `.environment(\.locale, effectiveLocale)` fed by an
`@Observable` locale holder. Strings become *deferred* (`LocalizedStringResource`)
so the environment applies; non-View contexts resolve via a locale-aware helper.
The watch receives the value over the existing keyed sync payload; the widget
reads the store at timeline build. Everything is app/core/watch/widget source —
no schema migration, so every phase is a vertical slice.

Slices are ordered skeleton → shared-string shape → separate-process reach
(risk) → content sweep (value) → hardening. Verify commands assume
`SIM=`/`.simulator_id` pinning per `conventions.md`; `make format` + `make lint`
run in-line before each commit. Full `./scripts/test.sh` runs once, after all
phases, via the `run-gate` skill.

---

## Phase 1: Walking skeleton — the Language picker switches the Interface screen live

A user opens Settings → Interface, picks *Español*, and the Interface screen's own
labels change **immediately, without relaunch**; the choice survives relaunch
because it round-trips `AppGroup.defaults`. This is the thinnest real path:
real store → real observable holder → real environment injection → real UI +
persisted output. Green tests prove the override mechanism and the
`LocalizedStringResource` + explicit-locale API the whole ticket depends on.
The ~14 settings literals are converted here so the screen is a visible,
self-demonstrating outcome rather than a stub.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/AppLanguage.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/AppLanguagePreference.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
(helper), `SingleThread/InterfaceSettingsView.swift`,
`SingleThread/SettingsBindings.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/SingleThreadApp.swift`, `SingleThread/Resources/Localizable.xcstrings`

**Key changes**:
- `enum AppLanguage: String, CaseIterable, Sendable { case system, english = "en", simplifiedChinese = "zh-Hans", spanish = "es", japanese = "ja", german = "de", french = "fr" }` — new
- `AppLanguage.locale: Locale` (`.current` for `.system`), `AppLanguage.localeIdentifier: String?`, `AppLanguage.title: LocalizedStringResource` — new
- `struct AppLanguagePreference { static let defaultsKey = "appLanguage"; init(defaults: UserDefaults = AppGroup.defaults); func load() -> AppLanguage; func setRawValue(_ raw: String) }` — new; missing/unrecognized → `.system` (near-copy of `AppearanceModePreference`)
- `@MainActor @Observable final class AppLocaleState { init(language: = AppLanguagePreference().load()); private(set) var language: AppLanguage; var effectiveLocale: Locale; func set(_ language: AppLanguage) }` — new, in Core (explicit `@MainActor`; Core has no default MainActor isolation)
- `extension LocalizedStringResource { func resolved(in locale: Locale) -> String }` — new; sets `locale` on a copy then `String(localized:)`
- `SettingsBindings.appLanguage: AppLanguage { get set }` — new store-backed computed property (the `showDate`/`sortOption` shape, not `@AppStorage`)
- `InterfaceSettingsView(appLanguage: Binding<AppLanguage>, …)` — new Language Picker after Text Size, both `#if os` branches, with `.accessibilityIdentifier`
- `SingleThreadApp.body` → `.environment(\.locale, localeState.effectiveLocale)` on the `ContentView`

**Contract**: `AppLanguage` cases/raw values and `defaultsKey == "appLanguage"`;
`AppLanguagePreference.load()/setRawValue`; `AppLocaleState.language`/`effectiveLocale`/`set`;
`LocalizedStringResource.resolved(in:)`. All later slices consume these only.

**Tests**: new `SingleThreadTests/AppLanguageTests.swift` —
`languagePreferenceRoundTripsEveryCase` (isolated `UserDefaults(suiteName:)`,
proves `.standard` untouched, UUID key not needed — real key with `defer` restore),
`languagePreferenceFallsBackToSystemOnUnknownRawValue` (sad path),
`localizedStringResourceResolvesInExplicitLocale` (proves the one out-of-repo API
risk before anything depends on it), `effectiveLocaleFollowsTheStoredLanguage`.
`SettingsViewTests.swift` — add `settingsScreenShowsLanguagePickerOnBothPlatforms`
(differential ctor, both `#if os` branches) + a11y-id assertion.
**Verify**: `scripts/test-one.sh SingleThreadTests/AppLanguageTests` and
`scripts/test-one.sh SingleThreadTests/SettingsViewTests` green; manual: launch
under a non-English system locale, pick English, switch back — labels change with
no relaunch, and the picker is still English after a cold launch.

---

## Phase 2: Shared strings become deferred resources (app + watch + widget)

Every `SharedStrings.*` accessor — *Skip*, *Complete*, *Undo*, completion glow,
show-date labels — now follows the chosen language in the app, instead of
resolving eagerly against the system locale. This is the repo's one genuinely
**cross-cutting, atomic** change: the accessor return type changes, so all
app/watch/widget consumers must compile against the new shape in one commit
(no vertical slice can land the type change partially). It is still one green,
shippable increment, and it front-loads the biggest compilation-blast-radius risk
before the content sweep.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`,
the app/watch/widget `SharedStrings.` call sites named in `research.md` Q2
(`WatchReminderView.swift`, `NextThingWidget.swift`, app call sites), and the
`.en`-helper test call sites (`ReminderRecurrenceFormatterTests`,
`ReminderSkipTests`, `SingleThreadTests.swift`, `PrivacySettingsContentTests`,
`ReminderIntentsTests`, `AppInfoTests`, `AppearanceModeTests`).

**Key changes**:
- `public static var <member>: LocalizedStringResource` (was `String`) for all 20 `SharedStrings` members
- Non-View consumers switch to `resource.resolved(in: AppLocaleState.current.effectiveLocale)`; `Text`/`Label` sites take the resource directly
- Test assertions move from `String.en(…)` to `SharedStrings.x.resolved(in: Locale(identifier: "en"))`

**Contract**: `SharedStrings.<member>` is `LocalizedStringResource`; use
`.resolved(in:)` outside a View. No new persistence.

**Tests**: existing `LocalizationTests` stays green (six-language invariant,
plural variations, `guardedCatalogs`); update the `.en`-assertion suites in place
so they still pin English **and** add one test asserting a shared string resolves
to each of the six languages in turn.
**Verify**: `scripts/test-one.sh SingleThreadTests/LocalizationTests` plus the
updated suites green; `make watch-build` compiles (proves the watch consumers
adapted).

---

## Phase 3: Phone → watch → widget propagation

The chosen language reaches the watch and the widget: the watch's UI and the
widget's due-date rows render in the selected language without the phone open,
surviving relaunch. This front-loads the remaining integration risk — separate
processes, an App Group that does not exist on watchOS, and a widget snapshot
built at timeline time.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThread/AppViewModel.swift`, `SingleThreadWatch/WatchAppViewModel.swift`
(+ its root view), `SingleThreadWidget/NextThingWidget.swift` (+ provider),
`SingleThreadWatch/WatchReminderView.swift`, watch + widget `.xcstrings`,
`SingleThread/ContentViewModel.swift` or `SettingsViewModel.swift` (reload hook).

**Key changes**:
- `SkippedReminderSyncService.PayloadKey.appLanguage` (raw `"appLanguage"`) + `sendsAppLanguage` init flag (phone `true`, watch `false`), pushed in `pushAll()` and decoded in `apply(context:)` — mirrors `sortOption`
- `onAppLanguageReceived` write-once hook; watch wires it in `wireStateReceiveHooks()` → `localeState.set(_:)`
- watch root: `.environment(\.locale, localeState.effectiveLocale)`; watch `AppLanguagePreference(defaults: .standard)` seeds at launch
- widget root: `.environment(\.locale, AppLanguagePreference().load().locale)` inside the widget view; the existing `WidgetCenter.shared.reloadAllTimelines()` chokepoint fires on the new preference's change
- 4 watch literals (`WatchReminderView.swift:55,167,303,319`) → catalog keys ×6

**Contract**: payload key `"appLanguage"` carrying an `AppLanguage.rawValue`;
absent key ⇒ receiver keeps its own stored/default value (the `enableActionButtons`
"never-set keys omitted" rule). Watch `AppLocaleState` is the same concrete type
as the app's.

**Tests**: new `SingleThreadTests/AppLanguageSyncTests.swift` —
`pushPayloadCarriesLanguageWhenSet`, `pushPayloadOmitsLanguageWhenNeverSet` (sad
path / fresh-device default), `applyContextPersistsLanguageAndFiresHook`;
watch-side decode test under `SingleThreadWatchTests` via `make watch-test`.
**Verify**: `scripts/test-one.sh SingleThreadTests/AppLanguageSyncTests` and
`make watch-test` green; manual: change the language on the phone, confirm the
paired-watch UI and a widget timeline both flip.

---

## Phase 4: Reminder + main-screen surfaces localized

Any reminder-facing screen — card, dictation, reschedule, empty states — renders
fully in the chosen language, with no leftover English. This is the first half of
the content sweep: the ~40 bypassing literals and eager `String(localized:)`
sites in the reminder surfaces plus their keys.

**Files**: `SingleThread/ContentView.swift`, `SingleThread/ReminderCardView.swift`,
`SingleThread/ReminderDictation.swift`, `SingleThread/RescheduleSheet.swift`,
`SingleThread/ExcludedListsView.swift`, `SingleThread/FilterSortSettingsView.swift`,
`SingleThread/NotificationScheduler.swift` (Core outlier — `bundle: …`), and
`SingleThread/Resources/Localizable.xcstrings` (+ Core catalog where the key is shared).

**Key changes**: each user-facing literal at the sites listed in `research.md` Q4
becomes a `LocalizedStringKey` / `LocalizedStringResource` handed to the view;
eager `String(localized:)` sites (`ContentView.swift:218,733,758`,
`ReminderCardView.swift:128`, …) become deferred. Debug-only literals
(`ContentView+iOS.swift:26,28`, `ContentView.swift:331,701,711,721`) are left alone
by decision 2.

**Contract**: new catalog keys, six languages each — the only cross-slice
dependency later content slices share is the key-naming convention + the
`LocalizationTests` six-language invariant.

**Tests**: extend `LocalizationTests` so every newly added key must carry all six
languages, and add a unit test per converted call site asserting it resolves in
`.en` (the `String.en`-style assertion pattern already used by
`BackgroundCardTests`/`SingleThreadTests`).
**Verify**: `scripts/test-one.sh SingleThreadTests/LocalizationTests` +
`SingleThreadTests/SingleThreadTests` green; `make format && make lint`;
manual pass over the reminder screens in the two most-different languages
(Deutsch + 日本語).

---

## Phase 5: Settings, purchase, and about surfaces localized

The remaining non-reminder screens — settings subscreens, purchase, about,
notifications, background, macOS menu extras — render fully in the chosen
language. Second half of the content sweep; same mechanical shape as Phase 4,
independently shippable.

**Files**: `SingleThread/InterfaceSettingsView.swift` (remaining literals),
`SingleThread/ReminderSettingsView.swift`, `SingleThread/NotificationsSettingsView.swift`,
`SingleThread/BackgroundSettingsView.swift`, `SingleThread/PurchaseSettingsView.swift`,
`SingleThread/AboutView.swift`, `SingleThread/SingleThreadApp+Commands.swift`,
`SingleThread/MenuBarExtraOptions.swift`, catalogs.

**Key changes**: literals → catalog keys ×6; `SingleThreadApp+Commands.swift:46-48`
appearance tags resolve through the catalog alongside `AppearanceMode.title`;
`MenuBarExtraOptions.swift:20`'s `Text(due, format: .dateTime)` inherits the
injected locale (no code change beyond the root injection from Phase 1).

**Contract**: none new — Phase 4's key convention and `LocalizationTests`
invariant are reused. Before this phase, agree and document the key-naming
convention (Phase 4) so the two sweeps cannot drift.

**Tests**: `LocalizationTests` (six languages on every new key, no unreferenced
keys added), per-site `.en` assertions; `SettingsViewTests` still green.
**Verify**: `scripts/test-one.sh SingleThreadTests/LocalizationTests` +
`SingleThreadTests/SettingsViewTests` green; `make lint`; manual pass over the
settings stack + purchase/about screens in Deutsch and 日本語.

---

## Phase 6: Hardening — the locale change sticks everywhere

Switching language mid-session leaves nothing stale: navigation titles re-localize,
presented sheets pick up the new locale, the widget refreshes after a change, and
an unsupported stored raw value degrades to *System* rather than a blank UI.

**Files**: `SingleThread/ContentView.swift` (nav-title re-identity / sheet
`.environment(\.locale,…)`), `SingleThread/SingleThreadApp.swift` (macOS scene +
`MenuBarExtra` locale), `SingleThreadWidget/NextThingWidget.swift`,
`SingleThreadWatch/WatchReminderView.swift`, `SingleThreadUITests/SingleThreadUITests.swift`.

**Key changes**:
- `.id(localeState.language)` (or equivalent re-identity) on the `NavigationStack`
  if titles do not re-localize — confirm at build time against the iOS 18 risk
- explicit `.environment(\.locale, …)` on sheet content built at presentation time
  (`ContentView.swift:607-612`) and on the macOS `MenuBarExtra` scene
- audit: `rg 'String\(localized:'` and `SharedStrings\.` — no prod site left eager
  and un-`resolved`

**Contract**: none — behaviour only.

**Tests**: UI test `testLanguageSelectionChangesVisibleString`
(**justified**: end-to-end flow that only manifests at the UI layer — the reason
is stated in the PR) driving `--ui-testing`: open Settings → Interface → pick
Deutsch → assert a formerly-English label now matches the German catalog string;
sad path: a pre-seeded bogus raw value falls back to System.
**Verify**: `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLanguageSelectionChangesVisibleString`
green; then the full `./scripts/test.sh` **once**, via the `run-gate` skill.

---

## Testing Checkpoints

| After | Must be green before advancing |
|---|---|
| Phase 1 | `scripts/test-one.sh SingleThreadTests/AppLanguageTests` + `SettingsViewTests` |
| Phase 2 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + updated `.en` suites; `make watch-build` |
| Phase 3 | `scripts/test-one.sh SingleThreadTests/AppLanguageSyncTests`; `make watch-test` |
| Phase 4 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + `SingleThreadTests`; `make lint` |
| Phase 5 | `scripts/test-one.sh SingleThreadTests/LocalizationTests` + `SettingsViewTests`; `make lint` |
| Phase 6 | `scripts/test-one.sh …testLanguageSelectionChangesVisibleString`; then `./scripts/test.sh` once via `run-gate` |
