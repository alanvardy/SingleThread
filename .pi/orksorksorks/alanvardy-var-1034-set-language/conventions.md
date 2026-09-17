# Conventions — build, test, lint, format

Facts for Structure/Plan phases; do not re-open Makefile/scripts/test.sh unless
something here is wrong. Repo root: the worktree (e.g.
/Users/vardy/dev/alanvardy-var-1034-set-language).

## Canonical commands

- **Full CI-identical gate**: `./scripts/test.sh` (formats, lints, builds,
  Periphery, unit + UI tests) — run ONCE via the `run-gate` skill (async gate
  subagent, managed worktree, multi-hour timeout). Never `nohup` it ad-hoc.
- **Makefile targets** (from `repo-facts` / Makefile):
  `build`, `test`, `ui-test`, `watch-build`, `watch-test`, `watch-ui-test`,
  `mac-build`, `mac-test`, `mac-run`, `mac-distribute`, `simverify`,
  `coverage`, `coverage-ui`, `coverage-all`, `periphery`, `lint`, `format`,
  `check`, `clean`, `reset-storekit`.
- **Destination pinning**: `SIM=<UDID> make test`. Precedence: explicit
  `SIM=` > this worktree's `.simulator_id` (currently
  `D4C34BCA-7C96-418E-BDD3-BB22738A69C7`) > shared default. Name-only
  "iPhone 17" is ambiguous when multiple runtimes exist and can match the
  leftover "Gate iPhone 17" sim. CI runs iPhone 17 + iPad (A16) in parallel
  matrix jobs; watch UI tests pin an unpaired watch sim via
  `WATCH_TEST_SIM='platform=watchOS Simulator,id=<UDID>'`.
- **One test** (red-first safe): `scripts/test-one.sh <Target/Suite/case>` —
  exits non-zero when the run matched zero cases (a zero-match
  `-only-testing:` prints TEST SUCCEEDED and exits 0). Targeted suites:
  `xcodebuild -only-testing:SingleThreadTests` (Swift Testing) /
  `-only-testing:SingleThreadUITests` (XCTest).
- **In-line quick loop**: `make format` then `make lint` before the gate.
- **Periphery**: `make periphery`; reads a stale build index after branch
  switches — clean `DerivedData/` and rerun first. Local Xcode 27 vs CI 26.6
  divergence on `$`-projection-only `@State` — CI is authoritative.

## Test-suite inventory

Unit tests are **Swift Testing** (`import Testing`, `@Test`); UI tests are
XCTest. Unit-test names must NOT start with `test`/`testing` (SwiftFormat
strips and renames them); UI-test (XCTest) names keep `test…`.

| Path (under repo root) | Target | Covers | Gating |
|---|---|---|---|
| `SingleThreadTests/SettingsViewTests.swift` | iOS/macOS unit | SettingsBindings round-trips, injected-bindings view construction, InterfaceSettingsView differential ctor, a11y ids | 14 `#if os(` gates |
| `SingleThreadTests/SettingsViewModelTests.swift` | unit | @MainActor crash-guard smoke tests | `#if os(iOS)` / `#if os(iOS) \|\| os(macOS)` |
| `SingleThreadTests/LocalizationTests.swift` | unit | Catalog JSON parse (via `#filePath`), 6 languages, plural variations, InfoPlist.strings | none (catalog-level) |
| `SingleThreadTests/LocalizationTestHelpers.swift` | unit helper | `String.en` pinned-locale (`locale: Locale(identifier: "en")`), `Bundle.core` | — |
| `SingleThreadTests/BoolPreferenceStoreTests.swift` | unit | Store round-trips, UUID keys, isolated-suite injection | — |
| `SingleThreadTests/AppGroupTests.swift` | unit | `AppGroup.defaults` round-trip | — |
| `SingleThreadTests/UITestingSeedTests.swift` | unit | `--seed` JSON parsing / schema | — |
| `SingleThreadTests/ShowDateTests.swift` | unit | showDate/FormatStyleStorage | — |
| `SingleThreadTests/ReminderIntentsTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `ReminderSkipTests.swift`, `AppearanceModeTests.swift`, `AppInfoTests.swift`, `PrivacySettingsContentTests.swift`, `BackgroundCardTests.swift`, `SingleThreadTests.swift` | unit | localized-string call sites use `.en` helper | — |
| `SingleThreadTests/EntitlementStoreTests.swift` | unit (macOS) | StoreKit entitlement | 3 tests fail locally-only (see gotchas) |
| `SingleThreadUITests/SingleThreadUITests.swift` | UI (XCTest) | a11y audit `testAccessibilityAudit()`, `--ui-testing`/`--seed` drives | iOS |
| `SingleThreadWatchUITests/` | UI (XCTest) | watch a11y audit, `--ui-testing` | watchOS, paired sim |
| `SingleThreadWatchTests/` | unit | watch logic | watchOS |
| `SingleThreadCore/` (SPM package) | — | own tests run via app test host | `SWIFT_DEFAULT_ACTOR_ISOLATION` NOT set — annotate `@MainActor` explicitly |

## Build/verify gotchas

- **One xcodebuild test process at a time.** On Busy/RequestDenied: shut down
  sims, kill orphaned xcodebuild/xctest (simulator-pairing skill). After two
  local UI-stage contention failures, stop — CI is authoritative.
- **App Group rule**: every value shared with the watch must round-trip through
  `AppGroup.defaults` (`UserDefaults(suiteName:)`), never `UserDefaults.standard`
  — the suite always exists on simulator, so the two diverge silently. This
  includes `--ui-testing`/`--seed` seams. On watchOS the suite is unregistered →
  falls back to `.standard` (by design).
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS app +
  watch app targets only (not Core/widget/tests) — async functions there are
  already `@MainActor`; don't wrap in `Task { @MainActor in }`. Core/tests
  annotate explicitly. Swift 6 language mode, `SWIFT_APPROACHABLE_CONCURRENCY`.
- **Warnings are errors**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`; SwiftLint
  `--strict` (every warning an error). Debug builds use
  `DEBUG_INFORMATION_FORMAT = dwarf`.
- **SwiftFormat** (`.swiftformat`): enables `organizeDeclarations`,
  `blankLinesAroundMark`, `preferSwiftTesting`; disables `trailingCommas`,
  `trailingClosures`, `isEmpty`. Runs with `--exclude SingleThreadUITests`;
  watch UI tests are included but keep `test…` names.
- **SwiftLint**: identifier names ≥ 3 chars (exceptions `id`, `e`, `d`, `rt`,
  `to`, `gvm`); force-unwrapping banned outside tests
  (`SingleThreadTests/.swiftlint.yml` relaxes for fixtures); a11y rules
  (`accessibility_label_for_image`, `accessibility_trait_for_button`).
- **New files**: a new `.swift` file needs no pbxproj edit (synchronized
  groups); a new *test target* does (pbxproj ids, scheme TestAction,
  `-only-testing` entry in `scripts/test.sh`, CI matrix).
- **Previews/tests**: inject pre-populated `ReminderStore` or
  `loadsReminders: false`; never a real `EKEventStore`. Deterministic iOS UI
  tests use `--seed '<json>'` (InMemoryEventStore) or `--ui-testing`.
- **Pre-existing local-only failures** (don't debug): three macOS
  `EntitlementStoreTests` — `isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` (CI mac-tests
  green). Never `git stash` to baseline — use `git show origin/main:<path>`
  or a throwaway worktree.
- **Local a11y audit extra strictness** (`.hitRegion`, `.dynamicType`) can
  fail locally but pass CI; caption-sized buttons need `.padding` on the label
  (`.frame(minHeight: 44)` does not expand the a11y label frame).
- **UI tests are the exception, not the default** — each must earn its place;
  say why in the PR.
- `.simulator_id` current value: `D4C34BCA-7C96-418E-BDD3-BB22738A69C7`.
  Available devices: `xcrun simctl list devices available | grep -iE
  'iphone|ipad'`.