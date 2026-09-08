# Conventions — shared factual appendix (Localization Research, VAR-791)

Repo root: `/Users/vardy/dev/alanvardy-var-791-check-localizations`. Shell is fish; run `./scripts/test.sh` for the full gate (`make check`).

## Build / test / lint / format / verify commands

- **Full CI-identical gate**: `./scripts/test.sh` (alias `make check`, Makefile:99-101). Formats, lints, builds iOS+watch, Periphery, unit + UI tests. Long multi-hour run — run detached (`nohup … > /tmp/gate.log 2>&1 &`).
- **Unit only**: `make test` → `./scripts/test.sh --unit-only` (Makefile:75-76). Targeted suite: `xcodebuild -scheme SingleThread … test -only-testing:SingleThreadTests` (Makefile:26-27 mac; scripts/test.sh:287-292).
- **LocalizationTests alone**: `-only-testing:SingleThreadTests/LocalizationTests`.
- **UI only**: `make ui-test` → `./scripts/test.sh --ui-only` (Makefile:78-79). iOS UI: `-only-testing:SingleThreadUITests` (Makefile:53-56); watch UI: `make watch-ui-test`, `-only-testing:SingleThreadWatchUITests` (Makefile:84-90); watch unit: `make watch-test`, `-only-testing:SingleThreadWatchTests` (Makefile:92-98).
- **Destinations** (Makefile:1-8): `SIM ?= platform=iOS Simulator,name=iPhone 17` — name-only is ambiguous when multiple runtimes exist; pin `,OS=<ver>` or `,id=<UDID>` (`SIM=` override). `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (unpaired watch sim for UI tests). `MAC_SIM = platform=macOS`.
- **Other**: `make build` (:18, `build-for-testing`, Debug), `make watch-build` (:21), `make lint` (:106-109 swiftlint --strict), `make format` (:111-113 swiftformat; `--exclude SingleThreadUITests`), `make periphery` (:115 — clean `DerivedData/` first after branch switches; reads stale build index). `swiftlint lint --strict` = every warning is an error (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, scope per-target in pbxproj).

## Test-suite inventory (localization-relevant)

All in Swift Testing (`import Testing`, `@Test`, function names must NOT start with `test`; XCTest is UI-test-only). Platform gating via `#if os(iOS)` / `#if os(macOS)` / `#if os(iOS) || os(watchOS)` file headers.

| File | Covers | Gating / notes |
|---|---|---|
| `SingleThreadTests/LocalizationTests.swift` (240 ln) | The four `Localizable.xcstrings` parse + non-empty en (`:20-58`), all six locales present + non-empty per key (`:63-82`), plural category membership for the 5 `%lld` keys — `other` everywhere, `one` for en/es/de/fr (`:87-122`), `InfoPlist.strings` required keys per language (`:124-141`). Paths hardcoded rel. `repoRoot` (`:160-172,221-228,232-238`); parsers `JSONSerialization.jsonObject` + `PropertyListSerialization.propertyList` | macOS + iOS (`mac-test` / unit jobs) |
| `SingleThreadTests/LocalizationTestHelpers.swift` (31 ln) | `String.en(key, bundle:, table: "Localizable")` pins `en` locale (`:6-11`); `Bundle.core` resolves embedded `SingleThreadCore_SingleThreadCore.bundle` in test host, precondition-fails if missing (`:15-30`) | not a test — helper, used by 9 suites (33 call sites) |
| `SingleThreadTests/SingleThreadTests.swift` | end-to-end localizable strings via `String.en(..., bundle: .main|.core)` (`:34-70`) | iOS |
| `SingleThreadTests/AppInfoTests.swift` | `versionDescription` localized via `StubBundle` (`:9-23`) + `String.en(bundle: .core)` (`:19,42`) | — |
| `SingleThreadTests/ReminderSkipTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `AppearanceModeTests.swift`, `SortOptionTests.swift`, `PrivacySettingsContentTests.swift`, `ReminderIntentsTests.swift`, `TextSizeTests.swift` | assert localized output via `String.en` (`bundle: .main` / `.core`) | iOS |
| `SingleThreadTests/StubBundle.swift` (8-29) | `final class StubBundle: Bundle` overriding `infoDictionary` / `object(forInfoDictionaryKey:)` | test fixture |
| `SingleThreadUITests/*` (XCTest) | UI flows + `testAccessibilityAudit`; **no** catalog references | iOS, `#if os(iOS)` in `SingleThreadUITestCase.swift` |
| `SingleThreadWatchTests/*`, `SingleThreadWatchUITests/*` | Watch view/viewmodel; **no** catalog references | watchOS — requires watch sim; watch UI uses standalone unpaired sim |
| Known pre-existing local-only failures: `EntitlementStoreTests` SKTestSession tests (`:43,63,77`) fail on macOS here (CI mac-tests green) — do not debug |

## Localization-relevant gotchas

- **All four `Localizable.xcstrings` declare no top-level schemaVersion**; top level is `sourceLanguage: "en"` + `strings`; `extractionState` is per-string, always `"manual"`; every stringUnit `state: "translated"`. JSON style differs (Watch uses spaces-around-colons; others compact).
- **Catalog test paths** (LocalizationTests.swift:166-172): `SingleThread/Resources/Localizable.xcstrings` (130 keys), `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` (30), `SingleThreadWatch/Resources/Localizable.xcstrings` (4), `SingleThreadWidget/Resources/Localizable.xcstrings` (5). Tests read the source tree, never build products.
- **InfoPlist.strings** live at `<Product>/{en,zh-Hans,es,ja,de,fr}.lproj/InfoPlist.strings` (18 files); App has 4 keys (NSMicrophoneUsageDescription, NSRemindersUsageDescription, NSSpeechRecognitionUsageDescription, CFBundleDisplayName), Watch/Widget have 2 (NSRemindersFullAccessUsageDescription, CFBundleDisplayName). Format: `"KEY" = "VALUE";`.
- **Shared keys** live in the Core catalog under `LocalizedString+Shared.swift` (`bundle: .module`) — convention is never to duplicate them in target catalogs, but `Reminder`, `Complete Reminder`, `Skip Reminder`, `Medium` ARE duplicated in target catalogs today.
- **Locales**: `knownRegions = (en, Base, zh-Hans, es, ja, de, fr)` (pbxproj:447-455); `developmentRegion = en` (pbxproj:445). Watch shows locale list `en/zh-Hans/es/ja/de/fr`.
- **Tooling**: `xcrun --find xcstringstool` (print/compile/sync/extract/generate-symbols/installloc); `xcodebuild -exportLocalizations|-importLocalizations -localizationPath <XLIFF path>`; `plutil -lint` for `.lproj` files; `jq` parses xcstrings. No existing Makefile/CI/scripts localization automation — LocalizationTests is the only consumer.
- **One xcodebuild test process at a time** (simulator contention). On Busy/RequestDenied: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`.
- **Unit-test naming**: SwiftFormat strips `test`/`testing` prefixes under `make format` — name tests `isEntitledFallsByDefault` style. UI tests keep `test…` (SwiftFormat-excluded).
- **Force-unwrapping banned outside test code** (test fixtures relax via `SingleThreadTests/.swiftlint.yml`).
- **`AppGroup.defaults` (UserDefaults suiteName:) is the only persisted-value channel shared with the watch** — never `UserDefaults.standard` (suites diverge silently on simulator).