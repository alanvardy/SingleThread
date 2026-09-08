# Research Findings

## Q1: Key-level translation state in the string catalogs

### Findings

**The four catalogs.** All are xcstrings JSON (`sourceLanguage: en`, one entry per string with per-string `extractionState: "manual"` and per-locale `stringUnit.state: "translated"`), same six locales en/zh-Hans/es/ja/de/fr, every key present in all six locales, no duplicate keys.

| Product | Path | Keys | Lines |
|---|---|---|---|
| iOS App | `SingleThread/Resources/Localizable.xcstrings` | 130 | 5396 |
| Core SPM | `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` | 30 | 1476 |
| Watch | `SingleThreadWatch/Resources/Localizable.xcstrings` | 4 | 49 |
| Widget | `SingleThreadWidget/Resources/Localizable.xcstrings` | 5 | 211 |

**Flagged keys (non-English value byte-identical to English source).** No case/whitespace/punctuation-only differences exist; all 19 flags across 7 keys are byte-identical English. App catalog line refs are the key line; flagged value lines noted.

- App `SingleThread/Resources/Localizable.xcstrings`:
  - `%lld%%` (`:4`) — flagged in all 5 non-English locales (values `:16,:22,:28,:34,:40`). Format string; no translatable words.
  - `SingleThread` (`:2505`) — flagged in all 5 (values `:2511,:2517,:2523,:2529,:2535,:2541` — en itself at `:2511`). Product name.
  - `Copyright 2026 Alan Vardy` (`:455`) — flagged es/ja/de/fr (values `:473,:479,:485,:491`); zh-Hans translated (`:467` 版权所有 2026 Alan Vardy). Proper noun in boilerplate.
  - `System` (`:3754`) — flagged de only (value `:3784` "System"); zh 系统 / es Sistema / ja システム / fr Système.
  - `Interface` (`:1070`) — flagged fr only (value `:1106` "Interface"); zh 界面 / es Interfaz / ja インターフェース / de Oberfläche.
  - `Notifications` (`:1316`) — flagged fr only (value `:1352` "Notifications"); zh 通知 / es Notificaciones / ja 通知 / de Mitteilungen.
- Core `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`:
  - `Version %@` (`:1310`) — flagged de (`:1340`) and fr (`:1346`); zh (版本 %@) / es (Versión %@) / ja (バージョン %@) genuine.
- Watch and Widget: no flagged keys (all 4 / 5 keys genuinely distinct in every non-English locale).

Per-locale totals (App): zh-Hans 2, es 3, ja 3, de 4, fr 5 — i.e. de and fr carry the bulk of identical-spelling flags; zh-Hans has none in App/Core.

**Classification.** Format strings: `%lld%%` (identity is content-neutral), `Version %@` in de/fr (cognate spelling). Proper noun/product name: `SingleThread`, `Copyright 2026 Alan Vardy`. Plain UI text where the foreign word is spelled identically to English: `Interface` (fr), `Notifications` (fr), `System` (de).

**variations.plural.** Genuinely distinct per language; zero non-English forms identical to English. App has 1 plural key: `You have %lld reminders waiting — open SingleThread!` (`:3366`, plural blocks `:3370-:3399`). Core has 4: `Every %lld days/months/weeks/years` (`:373,:474,:575,:676`). Pattern: en/es/de/fr carry `one`+`other`, zh-Hans/ja carry `other` only (CLDR-correct for single-form languages). Note: de/fr "one" forms reuse the bare noun (e.g. `Alle %lld Tag`, `Tous les %lld jour`) — a form-quality observation, not identity. Watch/Widget have no plural entries.

**Cross-catalog shared keys (same English source in multiple catalogs):** `Medium` (App `:3918` / Core `:859`; only translation divergence: iOS es Mediano vs Core es Media), `Reminder` (App `:1931` / Watch `:26`), `Complete Reminder` (App `:4164` / Widget `:127`), `Skip Reminder` (App `:4205` / Widget `:168`). Near-duplicates (different casing → different keys): Core `Complete reminder`/`Skip reminder` vs App/Widget `Complete Reminder`/`Skip Reminder`.

## Q2: InfoPlist.strings translation state

### Findings

**Files.** 18 files = 3 targets × 6 locales:
- `SingleThread/{de,en,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` (4 keys)
- `SingleThreadWatch/{de,en,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` (2 keys)
- `SingleThreadWidget/{de,en,es,fr,ja,zh-Hans}.lproj/InfoPlist.strings` (2 keys)

**Keys per target.** App: `NSMicrophoneUsageDescription`, `NSRemindersUsageDescription`, `NSSpeechRecognitionUsageDescription`, `CFBundleDisplayName` (e.g. `SingleThread/en.lproj/InfoPlist.strings:1-4`). Watch/Widget: `NSRemindersFullAccessUsageDescription`, `CFBundleDisplayName` (e.g. `SingleThreadWatch/en.lproj/InfoPlist.strings:1-2`).

**Locale values identical to English source.** Only `CFBundleDisplayName = "SingleThread"` — 15 instances total (5 non-English locales × 3 targets, e.g. `SingleThread/de.lproj/InfoPlist.strings:4`, `SingleThreadWatch/fr.lproj/InfoPlist.strings:2`). Intentional (brand name). All other keys translated in all locales; the usage-description translations are word-for-word identical between the App `NSRemindersUsageDescription` and Watch/Widget `NSRemindersFullAccessUsageDescription` lines per locale (different keys, same text).

**Missing keys, syntax, encoding.** No missing/extra keys in any locale (every locale in a product has the identical key set). No malformed syntax: all 48 lines match `"KEY" = "VALUE";` (balanced quotes, semicolons, no stray chars, no BOM, trailing newline, no CR/tabs/trailing whitespace). All files valid UTF-8; non-ASCII only where the language requires it (e.g. fr `/c3 a8`, de `/c3 b6, c3 bc`); zero double-encoded mojibake signatures; both `en` files are pure ASCII.

## Q3: Existing localization validation and test infrastructure

### Findings

**`SingleThreadTests/LocalizationTests.swift`** (240 lines, `struct LocalizationTests` at `:17`; Swift Testing `#expect`/`#require`). Four tests:

1. `catalogsParseAndHaveNonEmptyEnglish()` (`:20-58`) — for each of the four catalogs in `Self.catalogs` (`:166-172`): reads via `Data(contentsOf:)` (`:23`), parses `JSONSerialization.jsonObject(with:)` forced with `try #require` (`:24`), requires top-level `strings` non-empty (`:25-26`), every key has `localizations.en` (`:28-30`), and either a non-empty direct `stringUnit.value` (`:31-33`) or `variations.plural` with non-empty `stringUnit.value` per category (`:36-53`).
2. `catalogsHaveAllSixLanguages()` (`:63-82`) — every key must have all `Self.languages = ["en","zh-Hans","es","ja","de","fr"]` (`:164`) and pass `Self.hasNonEmptyValue(loc)` (`:187-219`): direct value non-empty, or every plural category value non-empty.
3. `pluralKeysCarryPluralVariationsInAllLanguages()` (`:87-122`) — only `Self.pluralKeys` (`:150-158`, the 5 `%lld` keys in Core+App): each language must have `variations.plural`; `other` required everywhere; `one` required only for `Self.pluralLocales = ["en","es","de","fr"]` (`:147`). Checks category membership only, never variant text; watch/widget plurals not enumerated.
4. `infoPlistStringsHaveRequiredKeysPerLanguage()` (`:124-141`) — for each `(target, keys)` in `Self.infoPlistTargets` (`:174-183`) × 6 languages, builds `<repoRoot>/<Target>/<lang>.lproj/InfoPlist.strings` (`:128-130`, `repoRoot` at `:160-162` via `URL(fileURLWithPath: #filePath)` minus two components; name map at `:232-238`), parses with `PropertyListSerialization.propertyList(from: data, format: nil)` (`:132-134`), requires each key present (`:136`) and non-empty (`:137`).

**Parsing approach.** Pure JSONSerialization/PropertyListSerialization API walk with `as? [String: Any]` casts — no regex, no hand-rolled parser. Catalog paths are hardcoded relative to `repoRoot` (`:166-172`).

**Can the current assertions detect an exact-English translation? No.** All checks are presence + non-emptiness; no test compares any non-English value against the English value. `hasNonEmptyValue` (`:187`) never receives the `en` entry, so it is structurally incapable of the comparison. An English-copy value passes every assertion. Evidence it is live today: the Q1 flagged entries (e.g. `%lld%%`, `Copyright 2026 Alan Vardy`, `Interface`, `Version %@`) all satisfy the current suite.

**Reusable infrastructure (describe-what-exists only).**
- `SingleThreadTests/LocalizationTestHelpers.swift` (31 lines): `extension String`, `static func en(_ key: String.LocalizationValue, bundle: Bundle, table: String = "Localizable") -> String` (`:6-10`) → `String(localized: key, table: table, bundle: bundle, locale: Locale(identifier: "en"))`, 33 call sites (e.g. `SingleThreadTests.swift:36,38,42,45,49,59,62,66`; `AppInfoTests.swift:19,42`). `extension Bundle`, `static var core: Bundle` (`:23-30`) → `main.url(forResource: "SingleThreadCore_SingleThreadCore", withExtension: "bundle")`, `preconditionFailure` if not embedded (`:24-28`); doc `:15-22` explains tests cannot use package-only `Bundle.module`.
- Bundle loading: production passes `bundle: .main` (app: `ContentViewModel.swift:90-96`, `CreationFeedback.swift:29-30`, `SortOption+Presentation.swift:12-14`, `ReminderDictation.swift:227-239`) and `bundle: .module` (Core: `LocalizedString+Shared.swift:11-79`, `ReminderRecurrenceFormatter.swift:13-30`, `AppInfo.swift:36-47`). Tests use `.main` or `.core`; `StubBundle` (`SingleThreadTests/StubBundle.swift:8-29`) overrides `infoDictionary`/`object(forInfoDictionaryKey:)` for AppInfo tests. All production call sites pass `table: "Localizable"`. No `LocalizedStringBundle` symbol exists anywhere.
- The suite is run via `xcodebuild ... test -only-testing:SingleThreadTests`; it was not executed during research (requires simulator).

## Q4: Runtime resolution and fallback behavior

### Findings

**Resolution API is SDK-side.** No `LocalizedString.swift` in the repo; the machinery is `Foundation.swiftinterface` (`/Applications/Xcode.app/.../Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-ios.swiftinterface`): `String.init(localized:)` overloads (`:20227-20232`, `@_semantics("string.init_localized")`), `String.LocalizationValue` (`:20165-20226`), `LocalizedStringResource` + `BundleDescription main|forClass|atURL` (`:20481-20520`), `NSLocalizedString` (`:20562`), `Bundle.localizedString(forKey:value:table:localizations:)` (`:21218-21221`), bundle-URL discovery for `.module` (`:21222-21312`). SwiftUI literal path: `Text.init(_ key: LocalizedStringKey, ...)` (`SwiftUICore.swiftinterface:4930`). Lookup execution is inside the compiled Foundation runtime.

**`bundle:` and `table:` semantics.** All explicit calls pass `table: "Localizable"` (each product's `Localizable.xcstrings` compiles to a resource table of that name). `bundle: .main` = embedding app/extension bundle — all iOS app call sites plus widget (`NextThingWidget.swift:103,105-108,122-127`) and Core's notification strings (`NotificationScheduler.swift:82-86`). `bundle: .module` = the SPM package's own resource bundle — every `SharedStrings` accessor plus `ReminderSkip.swift:42-44`, `ReminderRecurrenceFormatter.swift:17-30`, `AppInfo.swift:42,47`. Default resolution: key → table "Localizable" → bundle → current locale; key==value overloads make the key text the default. Watch app has zero explicit `String(localized:)` calls — all literals (`WatchReminderView.swift:55,167,202,215,277,295,298,316`) go through SwiftUI `LocalizedStringKey` literal lookup against the watch main-bundle `Localizable` table. Compiler gates: `SWIFT_EMIT_LOC_STRINGS = YES` (pbxproj `:778,:828,:962,:990,:1018,:1049`), `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` (`:670,:727`), `knownRegions = (en, Base, zh-Hans, es, ja, de, fr)` (`:447-455`).

**Shared keys — `LocalizedString+Shared.swift`** (`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`, doc `:1-8`: keys shared across ≥2 targets live here, never duplicated in a target's own catalog). 17 members, all `bundle: .module`: `Complete` (`:12-14`), `Skip` (`:16-18`), `Delete` (`:20-22`), `Skipped 6 times` (`:24-27`), `Complete reminder` (`:29-31`), `Skip reminder` (`:33-35`), `Delete reminder` (`:37-39`), `Completion glow` (`:41-43`), `All Done` (`:45-47`), `No Reminders` (`:49-51`), `Repeats` (`:53-55`), `Alert` (`:57-59`), `Reminders Access` (`:61-63`), `Requesting access…` (`:65-67`), `Nothing due right now` (`:69-71`), `No reminders yet` (`:73-75`), `"\(levelName) priority"` → key `%@ priority` (`:77-79`). Consumers span watch (`WatchReminderView.swift:51,134,...`), widget (`NextThingWidget.swift:124,...`), iOS (`ContentView.swift:356,...`). All 17 keys exist in the Core catalog.

**Fallback behavior: silent.** The runtime silently falls back to source-language (English) text; never surfaces an error. Evidence: (a) `Bundle.localizedString(forKey:value:table:localizations:)` (`swiftinterface:21220`) carries an explicit `value:` fallback and ordered language list; (b) all catalogs declare `sourceLanguage: "en"`; (c) the repo's own tests treat English-equal values as valid (Q3), so nothing flags them; (d) English-equal entries currently ship (Q1 list) and render silently with `state: "translated"`. The only "fail loudly" guard is test-only `Bundle.core` (`LocalizationTestHelpers.swift:19-23`), which protects a *missing bundle in the test host*, not missing/identical translations.

**Hardcoded English bypassing catalogs.** iOS app: `ContentView.swift:663` `Text("Processing…")`, `:667` `.accessibilityLabel("Processing")`, `:687` `Text("Speech recognition is unavailable.")`, `:692` `Button("Open Settings")`; `ReminderCardView.swift:169` `.accessibilityLabel("Skipped 6 times — tap to manage")`. macOS-only: `SingleThreadApp+Commands.swift:17,23` (`About SingleThread` / `Quit SingleThread`), `MenuBarExtraOptions.swift:32` (`Open SingleThread`). Watch: `WatchReminderView.swift:215,295,298` (`Reschedule`/`Reschedule to`) and `:316` (`Cancel`) — English on the watch even though the app catalog translates them. Widget: placeholder/mock copy only (`NextThingWidget.swift:38,58,236-247`). Core package has no bypasses. Files bypassing catalogs entirely: `SingleThreadApp+Commands.swift`, `MenuBarExtraOptions.swift`, parts of `ContentView.swift` dictation block (`:640-700`), `WatchReminderView.swift` reschedule block (`:283-320`).

## Q5: Tooling available for inspecting the catalogs

### Findings

- **`xcstringstool`**: not on PATH; at `/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool`, resolvable via `xcrun --find xcstringstool`. Subcommands: `print`, `compile`, `sync`, `extract`, `generate-symbols`, `installloc`.
- **`xcodebuild -help`** advertises `-exportLocalizations -localizationPath <path> -project <project> [-defaultLanguage <lang>] [-exportLanguage <lang>...]` and `-importLocalizations -localizationPath <path> -project <project> [-mergeImport]` (note: `-localizationPath` is documented as a path to XLIFF localization files).
- **`plutil`** (`/usr/bin/plutil`): `plutil -lint` on `SingleThread/en.lproj/InfoPlist.strings` → OK. **`jq`** parses the xcstrings. **`python3`** available.
- **No existing localization automation**: zero references in Makefile (targets at `Makefile:13-104`), scripts/ (count_tests, distribute-macos, run-devices, simverify, test), `.github/workflows/ci.yml`, AGENTS.md, or docs/. `xcrun` is used only for `simctl`/`xccov`/`devicectl`. No plutil/jq/JSON export pipeline anywhere.
- **Schema/extractionState**: NO top-level `schemaVersion` in any catalog (0 repo-wide grep hits); all start with `"sourceLanguage": "en"` + `"strings"`. `extractionState` is per-string, always `"manual"` (App 130, Core 30, Watch 4, Widget 5). Watch file uses spaces-around-colon JSON style; others compact.
- **Project wiring**: `knownRegions`/`LOCALIZATION_PREFERS_STRING_CATALOGS` in pbxproj; no direct file refs to `*.xcstrings`/`InfoPlist.strings` (synchronized-folder resource groups). `exportOptions.plist` is app-store signing config, unrelated.
- **Only tests that read catalog sources**: `SingleThreadTests/LocalizationTests.swift` (paths at `:166-172`, `:200-206` Q3 numbering) and the `String.en`/`Bundle.core` helpers for compiled-bundle assertions. No catalog references in Watch/UI test suites.

## Cross-Cutting Observations

- **Catalog state is uniformly "all translated"** — every one of 1,010 stringUnits across the four catalogs has `state: "translated"`, so the `state` field carries no signal about translation quality; identical-to-English entries are indistinguishable from genuine ones by any existing machine check.
- **Design intent vs reality on shared keys**: shared keys live in the Core catalog path (`.module` bundle) and are never duplicated in target catalogs — but `Reminder`, `Complete Reminder`, `Skip Reminder`, `Medium` are duplicated across catalogs anyway (Q1), suggesting partial drift from the documented convention.
- **de and fr are the weakest locales in App/Core catalogs** (identical-spelling flags cluster there); zh-Hans is clean. In `.lproj` files all non-English content is genuinely translated except the brand name.
- **The silent-fallback contract is uniform**: for `String(localized:)`, a missing locale entry or English-equal value both render English with no diagnostic; tests validate structure only (presence + non-emptiness), never value equivalence.
- **Watch and Widget catalogs are tiny (4/5 keys)** because most of their copy resolves either via SwiftUI literal-keyed lookup into their own catalogs or via Core's `.module` shared strings — but the Reschedule/Cancel literals in the watch bypass its catalog entirely.

## Open Areas

- Exact internal runtime fallback algorithm of `String(localized:)` (fuzzy locale matching, plural-category selection) is inside the compiled Foundation dylib; only the swiftinterface contract and observable catalog/test behavior are readable.
- Whether `SWIFT_EMIT_LOC_STRINGS` would auto-extract the §4 hardcoded literals as English-only `reference` entries on a future build was not empirically verified.
- Whether the de/fr `one`-form plural entries ("Alle %lld Tag", "Tous les %lld jour") are intentional form choices is not determinable from the codebase.
- The Q3 report listed 10 flagged App entries vs Q1's 14 — this was a sectional artifact of Q3's partial list; Q1's byte-checked enumeration is authoritative (verified by targeted re-reads: `Interface` `:1070/:1106`, `System` `:3754/:3784`, `Version %@` `:1310/:1340/:1346`).