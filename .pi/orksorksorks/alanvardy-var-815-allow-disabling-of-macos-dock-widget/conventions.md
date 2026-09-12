# Conventions — canonical commands, test inventory, gotchas

Factual appendix for Design/Structure/Plan. Backed by research reports and project `AGENTS.md` (repo-root, authoritative for this branch).

## Canonical build/test/lint/format commands

- **Full gate (CI-identical)**: `./scripts/test.sh` — full pipeline: format → lint (+fix) → iOS build → watch build → Periphery → UI tests → watch UI/unit → macOS unit (scripts/test.sh:118). Modes: `--unit-only`, `--ui-only` (scripts/test.sh:114-128). `Makefile` aliases: `make check` (Makefile:112), `make test` (:87), `make ui-test` (:90), `make watch-test` (:104), `make watch-ui-test` (:96), `make mac-test` (:35), `make build` (:26), `make watch-build` (:29), `make mac-build` (:32), `make lint` (:118), `make format` (:122), `make periphery` (:126), `make simverify` (:93).
- **Fast pre-gate loop**: `make format` then `make lint` in-line before launching the slow gate (AGENTS.md "Before Committing").
- **Single test**: `scripts/test-one.sh <Target/Suite/case>` — exits non-zero on a zero-match `-only-testing:` (a zero-match run prints `** TEST SUCCEEDED **` and exits 0, silently passing a red-first check). Pin destination via `SIM=`.
- **Gate staging**: phase subagents may run a build + targeted `-only-testing:` suites only; `./scripts/test.sh` runs **once** after phases commit via the `run-gate` skill (async gate subagent, managed worktree) — never an ad-hoc `nohup`.

## Platform / destination pinning

- **iOS sims**: `iPhone 17` (default) and `iPad (A16)`; CI runs both in a matrix (`.github/workflows/ci.yml:15-18`). `SIM=platform=iOS Simulator,name=<device>` form (ci.yml:18).
- **Name-only `iPhone 17` is ambiguous** with multiple runtimes; a leftover `Gate iPhone 17` sim can be picked by an unanchored match. Precedence: explicit `SIM=` > worktree `.simulator_id` (scripts/test.sh:52 resolves it) > shared default. Bare `name=` hangs.
- **macOS unit tests** run natively: `-destination "platform=macOS"` (ci.yml:168,179; Makefile:35).
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied` shut down sims and kill orphaned `xcodebuild`/`xctest` (simulator-pairing skill; watch UI tests use an unpaired watch sim).
- **Deployment-target guard**: `verify_deployment_target()` (scripts/test.sh:143, invoked :217) enforces 20 pbxproj `*_DEPLOYMENT_TARGET` literals (iOS 18.7; macOS/watchOS 26.5) + 3 `Package.swift` floor literals (scripts/test.sh:131-141). Changing floors requires updating the literal counts.

## SwiftFormat / SwiftLint

- `.swiftformat`: enable `organizeDeclarations`, `blankLinesAroundMark`, `preferSwiftTesting`; disable `trailingCommas`, `trailingClosures`, `isEmpty`; **`--exclude SingleThreadUITests`** (iOS UI tests excluded; watch UI tests are not but keep `test…` names because they are XCTest).
- SwiftLint `--strict` in CI (`swiftlint lint --strict`, scripts/test.sh:231): every warning is an error. `identifier_name` ≥ 3 chars (exceptions `id`, `e`, `d`, `rt`, `to`, `gvm`); force-unwrapping banned outside tests (test fixtures relax via `SingleThreadTests/.swiftlint.yml`).
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat strips the prefix, silently renaming the test (phantom "file reverted" diffs). XCTest (UI) names keep `test…`.
- Periphery: `periphery scan --strict` (Makefile:126; scripts/test.sh:251 with `--skip-build` on the stale `DerivedData/Index.noindex` index — clean `DerivedData/` after branch switches; `make periphery` reads a stale build index).

## Test-suite inventory (platform gating noted)

**Unit — Swift Testing (`#expect`/`@Test`), `SingleThreadTests/`** (iOS sim; macOS-host run via `platform=macOS` destination; some suites whole-file gated):
- Settings bindings/rows: `SettingsViewTests.swift` (bag round-trips :13-43; row content :45-338; macOS enableActionButtons :353+, AppGroup round-trip :361+), `SettingsViewModelTests.swift`, `SettingsCaptionTests.swift`, `SettingsSubscreenLayoutTests.swift`, `PrivacySettingsContentTests.swift`, `MenuBarExtraOptionsTests.swift` (whole file `#if os(macOS)` :1).
- Toggle suites: `MicrophoneToggleTests.swift` (iOS-gated blocks :196,234), `ShowAlarmsTests.swift`, `ShowDateTests.swift`, `ShowRecurrenceTests.swift`, `SortOptionTests.swift`, `TextSizeTests.swift`, `NotificationPreferenceTests.swift`, `OrientationPreferenceTests.swift`.
- Persistence: `AppGroupTests.swift`, `BoolPreferenceStoreTests.swift`, `BoolPreferenceKeyTests.swift`, `PreferenceHolderTests.swift`, `UITestingSeedTests.swift`, `EnableActionButtonsMigrationTests.swift`, `UndoStoreTests.swift`, `SkipCountStoreTests.swift`, `CompletionCounterStoreTests.swift`, `DailyCompletionStoreTests.swift`, `PendingCompletionStoreTests.swift`, `ExcludedListStoreTests.swift`.
- Sync (iOS + watch, whole-file `#if os(iOS) || os(watchOS)`): `EnableActionButtonsSyncTests.swift`, `SkippedReminderSyncServiceTests.swift`, `RescheduleSyncTests.swift`, `EntitlementSyncTests.swift`; fixtures `TestFixtures.swift` (:63 gated).
- Gate/effects: `ActionMenuGateTests.swift`, `ActionButtonTests.swift` (whole-file iOS :8), `ReminderStoreGateTests.swift`, `ResumptionGateTests.swift`.
- Misc app suites: `AppDelegateTests.swift` (iOS whole-file), `AppearanceModeTests.swift` (:5/:8 iOS/macOS split), `BackgroundCardTests.swift` (iOS), `MacOSActionButtonChromeTests.swift` (macOS whole-file :1), `SingleThreadTests.swift` (inline `#if os` expectations :44-129), `ReminderStoreTests.swift`, `ContentViewModelTests.swift`, `ReminderSkipTests.swift`, etc.
- **Known local-only macOS failures** (annotate, don't debug): `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary — CI mac-tests green on fresh runners.

**UI — XCTest, `SingleThreadUITests/`** (iOS sim): `SingleThreadUITests.swift` — `testLaunchAndRenderSmoke` (CI `ui-tests-smoke` job, ci.yml:124-139), `testAccessibilityAudit()`/`performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` iOS :56-75 (local runs add `.hitRegion`/`.dynamicType` strictness beyond CI — a local hit-region failure can be local-only), `--ui-testing` launch args :27-52.

**Watch unit — Swift Testing, `SingleThreadWatchTests/`**: `WatchSyncPipelineTests.swift`, `ShowEnableActionButtonsStateTests.swift`, plus watch suites in ci.yml (`watch-ui-tests` job creates its own watch sim).

**Watch UI — XCTest, `SingleThreadWatchUITests/`**: `SingleThreadWatchUITests.swift:24` a11y audit.

**CI jobs** (`.github/workflows/ci.yml`, branch `main` only): `unit-tests` (matrix iPhone 17/iPad A16, iOS sim serialize, `-only-testing:SingleThreadTests`), `ui-tests-smoke` (single smoke test), `mac-tests` (`platform=macOS`, `-only-testing:SingleThreadTests`), `lint` (swiftformat/swiftlint, watch build, periphery), `watch-ui-tests`, `secret-scan` (gitleaks). Runs-on `macos-26`.

## Settings/persistence conventions (how to extend facts, not advice)

- Persisted key storage: `@AppStorage(key)` defaults to `UserDefaults.standard`; `@AppStorage(key, store: AppGroup.defaults)` for watch-synced keys (`ContentView.swift:95-96`). **Every value shared with the watch must live in the App Group suite** (`AppGroup.defaults`, `UserDefaults(suiteName: "group.app.alanvardy.SingleThread")` — AppGroup.swift:12,17-21), never `UserDefaults.standard` alone; on simulators the suite always exists so the two diverge silently.
- Registration: `AppViewModel.registerDefaults()` (AppViewModel.swift:109-131: `UserDefaults.standard.register(defaults:)` + one-time standard→AppGroup migration pattern :122-126); `UserDefaults.didChangeNotification` observation drives both PreferenceHolder (PreferenceHolder.swift:15) and sync push-on-change (AppViewModel.swift:449-460, :484).
- Key constants: `PayloadKey` in `SkippedReminderSyncService.swift:530` (push :230, receive :372-375, `session.updateApplicationContext` :243-248). `UITestingSeed.persistedKeys` (UITestingSeed.swift:114) lists keys reset by `--seed`/`--ui-testing`.
- `--seed '<json>'` (InMemoryEventStore, deterministic) and `--ui-testing` (AppViewModel.swift:220-244) are the standard seams for deterministic iOS/persisted-state tests; watch uses `--ui-testing` too.
- `UserDefaults`/App Group is **not `Sendable`** — verify concurrency claims for shared types against the compiler.

## Misc gotchas

- `DELETEME` marker committed at branch bootstrap must be `git rm DELETEME` before merge (not gitignored; commit subject is the ticket title).
- Debug builds use `DEBUG_INFORMATION_FORMAT = dwarf` (fast incremental); release switches to `dwarf-with-dsym`. All changes are Debug-gated.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS app + watch app targets — async fns there default `@MainActor`; `SingleThreadCore`/widget/test targets do **not** enable it (annotate explicitly). Swift 6 mode (`SWIFT_VERSION = 6.0`), `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide.
- New test suites need pbxproj wiring + `-only-testing` entries in `scripts/test.sh` + `Makefile` test target where needed; new `.swift` files need no pbxproj edit (synchronized groups).
- Never push to main; merge PRs with `gh pr merge <n> --rebase --delete-branch`; never `git worktree remove` the dir you're in; `hx` panics without a TTY — use `git commit -m`.