# Conventions — SingleThread (shared appendix for Design/Structure/Plan)

Branch: `alanvardy-var-794-add-the-action-menu-to-macos-and-apple-watch`. Facts only, dense references; do not re-read the source tree for these.

## Canonical commands

- **Full CI-identical gate:** `./scripts/test.sh` (formats, lints, builds iOS+watch+macOS, Periphery, unit + UI tests on all three platforms). Modes: `--unit-only`, `--ui-only` (`scripts/test.sh:67-85`).
- **Makefile shortcuts:** `make build` / `make test` (= `--unit-only`, `Makefile:59-62`) / `make ui-test` (= `--ui-only`, `:64-67`) / `make check` (full, `:111-113`) / `make watch-test` / `make watch-ui-test` (`:91-109`) / `make mac-test` (unit only, `:26-27`) / `make lint` / `make format` / `make periphery` / `make coverage*` (`:39-57`).
- **Targeted suites (destination pinning required):** `xcodebuild -only-testing:SingleThreadTests` (Swift Testing) / `-only-testing:SingleThreadUITests` / `-only-testing:SingleThreadWatchUITests -only-testing:SingleThreadWatchTests`.
- **Destinations:** `SIM` = `platform=iOS Simulator,name=iPhone 17` (default; override with `SIM=…`), `WATCH_TEST_SIM` = `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`, `MAC_SIM` = `platform=macOS` (`scripts/test.sh:5-12`; `Makefile:1-8`). **A bare `name=` iOS destination is ambiguous when multiple runtimes exist — pin `,OS=<ver>` or `,id=<UDID>`** (resolved/pre-booted inside test.sh at `:31-49`; CI resolves name→UDID per matrix row `ci.yml:50-59`). watchOS CI creates a purpose-built standalone sim to avoid name ambiguity (`ci.yml:386-410`).

## Test-suite inventory

### SingleThreadTests (iOS+macOS unit, Swift Testing; `make test` / CI `unit-tests`, `mac-tests`)

| File | Covers | Platform gating |
|---|---|---|
| `SettingsViewTests.swift` | SettingsBindings round-trips (`:14-29`); root sections + captions (`:33-73`); per-subscreen rows incl. iOS "Show action buttons" row + caption (`:95-124`); macOS top-anchor assertions (`:123,:158,:189,:219,:273,:292,:330`) | per-test `#if os(iOS)` `:66,:78,:100,:112` / `#if os(macOS)` `:69,:123,…` |
| `SettingsViewModelTests.swift` | crash-guard: init, `allowsLandscapeChanged`, `showPreferenceChanged` (`:8-22`) | `#if os(iOS)` `:13`, `#if os(iOS)\|\|os(macOS)` `:18` |
| `BoolPreferenceStoreTests.swift` | fallback/round-trip/overwrite, suite-injection isolation, 6 key pairs (`:11-66`) | none |
| `BoolPreferenceKeyTests.swift` | rawValues, exhaustiveness, Sendable (`:7-30`) | none |
| `EnableActionButtonsSyncTests.swift` | `pushAll` includes key; receive persists→hook; absent-key no-op (`:17-53`) | whole-file `#if os(iOS)\|\|os(watchOS)` `:1,:55`; `@Suite(.serialized)` `:9-13` |
| `EnableActionButtonsMigrationTests.swift` | `.standard`→App Group one-shot migration (`:13-32`) | none; serialized `:7-8` |
| `ActionMenuGateTests.swift` | 2×2×2 truth table of `showsActionMenu` (`:8-22`) | none |
| `ActionButtonTests.swift` | `ContentViewModel.showsActionButtons` gate seam (`:19-73`; rationale `:6-13`) | whole-file `#if os(iOS)` `:8,:134` |
| `SkippedReminderSyncServiceTests.swift` | activation, snapshot shape, sends* gating, receive hooks, no-ops, relays, excluded lists, skip counts (`:40-470`) | whole-file `#if os(iOS)\|\|os(watchOS)` `:1,:660` |
| `AppGroupTests.swift` | suiteName, round-trip (`:6-15`) | none |

### SingleThreadWatchTests (watch unit)

`ShowEnableActionButtonsStateTests.swift` (persistence in `AppGroup.defaults`, `:16-54`), `ShowCompletionGlowStateTests.swift` (consumes `--ui-testing-glow-disabled`, `:51`), `WatchAppViewModelTests.swift` (VM stability, glow seam, `:17-34`), `WatchSyncPipelineTests.swift` (sync receive incl. enableActionButtons, `:521-561`), `WatchReminderViewRegressionTests.swift`, `ReminderStoreWatchTests.swift`.

### SingleThreadUITests (iOS UI, XCTest)

Whole bundle run by `scripts/test.sh`/`make ui-test`; CI splits: LaunchTests + AppearanceLaunchTests (ci.yml fragment A), SingleThreadUITestsFlows (B), SingleThreadUITests + ActionButtonsUITests (C) (`ci.yml:16-18`). **Not in any CI fragment:** `ActionMenuUITests`, `SkipNudgeUITests`, `NotificationsUITests`, `NotificationSchedulingUITests`, `NotificationsSettingsUITests` (local gates only). Includes `testAccessibilityAudit()` in `SingleThreadUITests.swift` and a compiled macOS `#else` audit branch (`:62-65`) that nothing ever runs on `platform=macOS`.

### SingleThreadWatchUITests (watch UI, XCTest)

3 files: `SingleThreadWatchUITests.swift` (dialog + a11y audit), `SingleThreadWatchUITestsFlows.swift` (14 tests), `SingleThreadWatchUITestsLaunchTests.swift`. All launch with `["--ui-testing"]` plus flags.

### Launch-argument seams (watch: `--ui-testing*` only; `--seed` is iOS-only — `UITestingSeed.swift:46-49`)

| Seam | Effect (all in `WatchAppViewModel.swift` unless noted) |
|---|---|
| `--ui-testing` | `InMemoryEventStore` + one deterministic reminder, no TCC (`:14-19,:106-167`); forces action-menu OFF unless flag below present (`:61-68`) |
| `--ui-testing-action-menu` | `ShowEnableActionButtonsState.apply(true)` (`:61-68`) |
| `--ui-testing-gated` | seeds `completionCount` at freemium cap → upgrade prompt (`:21-27`) |
| `--ui-testing-glow` / `-glow-disabled` | forces glow state; `-glow` extends duration to 2.0 s (`:45-59`; view consults it `WatchReminderView.swift:74`) |
| `--ui-testing-priority <n>` | sample reminder priority (`:114-123`) |
| `--ui-testing-skip-count <n>` | pre-seeds `AppGroup.defaults["skipCounts"]` (`:124-133`) |
| `--ui-testing-excluded-list <l>` / `-live-excluded <l>` | titled `EKCalendar`; `-live-excluded` delivers a delayed real `didReceiveApplicationContext` 5 s later (`:135-158,:279-291`) |

## Build/verify gotchas surfaced by research

- **One xcodebuild test process at a time** (simulator contention); on `Busy`/`RequestDenied` failures shut down sims and kill orphan `xcodebuild`/`xctest`. Watch UI tests need a paired sim (`xcrun simctl pair`).
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf`; release uses `dwarf-with-dsym`. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide — warnings fail everywhere (per-target overrides only in pbxproj, never CLI flags).
- **Lint/format:** `make format` = SwiftFormat (iOS + watch + core; **UI tests excluded** via `--exclude SingleThreadUITests`); `make lint` = SwiftLint `--strict`. Unit-test names must NOT start with `test`/`testing` (SwiftFormat strips them, phantom renames); UI-test names keep `test…`.
- **Watch UI-test local fix:** `scripts/test.sh` embeds `lib_TestingInterop.dylib` locally (`:257-270`); CI relies on its own runtime.
- **Deployment-target guard:** every test.sh mode verifies pbxproj deployment literals (iOS 18.7 ×8, macOS/watchOS 26.5 ×12) + Package.swift floors (`:104-192`).
- **App Group discipline:** every watch-shared value must round-trip through `AppGroup.defaults` (`UserDefaults(suiteName:)`), never `.standard` — on simulator the suite always exists so the two silently diverge; on real watchOS the suite is unavailable and falls back to `.standard` (`AppGroup.swift:12-17`).
- **Concurrency:** iOS/watch app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (do not wrap in `Task { @MainActor in }`); `SingleThreadCore`/widget/tests do not — annotate `@MainActor` explicitly there. Swift 6 language mode.
- **Force-unwrapping banned outside test code** (relaxed in `SingleThreadTests/.swiftlint.yml`); variable names ≥3 chars (exceptions `id,e,d,rt,to,gvm`).
- **Periphery:** `make periphery` = `periphery scan --strict` on the index store (`.periphery.yml`).
- **New `.swift` files** are auto-discovered (synchronized file groups, `objectVersion = 77`) — no pbxproj edits. New test *targets* require pbxproj + scheme + `scripts/test.sh` + CI wiring — flag in Design.
- Local `xcrun simctl` device list check: `xcrun simctl list devices available | grep -iE 'iphone|ipad'`; pin `SIM` if ambiguous.
- **CI specifics:** Xcode 26.6 pinned (`ci.yml:45-47`); unit jobs disable parallel simulator clones (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`) while local test.sh enables `-parallel-testing-enabled YES` for iOS units (`scripts/test.sh:239-246`); CI jobs split UI into 3 groups to stay under timeouts. `scripts/count_tests.sh` (~516 iOS / ~36 watch / ~24 iOS UI / ~11 watch UI) are estimates.
- **No macOS UI-test run exists** in test.sh, ci.yml, or Makefile — macOS gets only unit tests (`scripts/test.sh:286-296`; `ci.yml:293-313`; `Makefile:26-27`), always `CODE_SIGNING_ALLOWED=NO`.