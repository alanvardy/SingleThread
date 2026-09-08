# Conventions — Shared Factual Appendix

Reference for Design/Structure/Plan. Everything here was verified from repo files; paths relative to repo root.

## 1. Canonical commands

### Makefile targets (root `Makefile`)
| Target | Command it runs | Notes |
|---|---|---|
| `make build` | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath 'DerivedData' build-for-testing` | `Makefile:17-18` |
| `make watch-build` | generic watchOS Simulator build | `Makefile:20-21` |
| `make mac-build` / `mac-test` / `mac-run` | `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` | `Makefile:23-27,29-...` |
| `make test` | `./scripts/test.sh --unit-only` | `Makefile:75-76` |
| `make ui-test` | `./scripts/test.sh --ui-only` | `Makefile:78-79` |
| `make watch-ui-test` / `watch-test` | concrete `WATCH_TEST_SIM` (Apple Watch Series 11 46mm default) | `Makefile:84-98` |
| `make check` | full `./scripts/test.sh` (CI-identical gate) | `Makefile:100-101` |
| `make lint` | swiftformat --lint + swiftlint lint --strict over all 8 dirs | `Makefile:106-108` |
| `make format` | swiftformat + swiftlint --fix | `Makefile:110-112` |
| `make periphery` | `periphery scan --strict -- -destination "$SIM"` | `Makefile:114-115` |
| `make coverage` / `coverage-ui` / `coverage-all` | xcodebuild + `xcrun xccov view` result bundles | `Makefile:38-73` |
| `make simverify` | `./scripts/simverify.sh` (boot + appearance-gate UI runs) | `Makefile:81-82` |

`SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); **pin with `SIM='platform=iOS Simulator,id=<UDID>'`** — a bare `name=` is ambiguous when multiple runtimes exist and the build hangs. `WATCH_SIM` = generic (builds), `WATCH_TEST_SIM` = concrete device (XCTests require a concrete destination) (`Makefile:2-5`, `scripts/test.sh:8-11`).

### `./scripts/test.sh` (CI-identical; the real gate)
- Modes: `full` (no arg), `--unit-only`, `--ui-only` (`scripts/test.sh:78-88`).
- Full pipeline order: format → SwiftFormat lint → SwiftLint `--strict` → iOS `build-for-testing` → watch build → Periphery (`--skip-build --index-store-path DerivedData/...`) → iOS unit tests (parallel YES, `-maximum-test-execution-time-allowance 900`, `:234`) → iOS UI tests → watch build-for-testing → watch UI tests → watch unit tests → macOS unit tests (`platform=macOS`, `CODE_SIGNING_ALLOWED=NO`) (`:196-283`).
- Pre-flight: **resolves name-only SIM to a concrete UDID** (`resolve_sim_udid`, `scripts/test.sh:25-30`) and **pre-boots** the sim (`preboot_sim`, `:32-39`; matches CI `ci.yml:107-112`). **Prunes stale XCTest runtimes** in `~/Library/Developer/XCTestDevices` older than `RUNTIME_AGE_HOURS` (default 1) before each run (`cleanup_xctest_runtimes` `:54-...`, call `:104`).
- **Deployment-target guard**: `verify_deployment_target` enforces iOS 18.7 / macOS+watchOS 26.5 across all pbxproj literals (20 expected) and Package.swift floors (3 expected) — a new/changed target with the wrong literal fails the gate (`scripts/test.sh:119-193`).
- **Local-only watch quirk**: embeds Xcode's `lib_TestingInterop.dylib` into the watch UI test runner — this machine's watchOS simruntime is missing it and the runner crashes at launch; CI's runtime has it (no-op there) (`scripts/test.sh:257-269`).

### Tool versions (`.mise.toml`)
`swiftlint 0.65.0`, `swiftformat 0.62.1`, `periphery 3.8.0`.

### CI (`.github/workflows/ci.yml`)
- Jobs: `unit-tests`, `ui-tests-flows`, `ui-tests-launch-appearance`, `ui-tests-audits` (each matrixed over **iPhone 17 + iPad (A16)**, `ci.yml:25,93,154,213`), `mac-tests`, `lint`, `watch-ui-tests`.
- iOS UI classes split into disjoint `-only-testing:` groups A/B/C via env vars (`ci.yml:11-17`).
- **Parallel test simulator clones are DISABLED in CI** (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`) with comments explaining clone-timeout/SIGTRAP races on GitHub runners; local `test.sh` uses `-parallel-testing-enabled YES` for unit tests only. `-retry-tests-on-failure` on UI jobs.
- watch-ui-tests **creates a fresh unpaired watch simulator** ("CI Watch S11") because name-only destinations are ambiguous on GitHub images (`ci.yml:270-279`).

## 2. Host-side (developer machine) gotchas
- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied` failures: `xcrun simctl shutdown all` + kill orphaned xcodebuild/xctest. Watch UI tests need a paired sim: `xcrun simctl pair <watchUDID> <phoneUDID>`.
- **Destination pinning**: always `,OS=<ver>` or `,id=<UDID>` on iOS/watch destinations (see AGENTS.md). `scripts/run-devices.sh` = devicectl install/launch for real devices.
- **The command tool runs fish** — no heredocs/loops/`$()`-at-start; write `/tmp/x.sh` and `bash /tmp/x.sh` when a script body is needed.

## 3. Lint / format / build settings
- **SwiftFormat** (`.swiftformat`): `--swiftversion 6.0`, indent 4; enables `blankLinesAroundMark`, `organizeDeclarations`, `preferSwiftTesting`; disables `andOperator`, `isEmpty`, `trailingClosures`, `trailingCommas`, `wrapMultilineStatementBraces`; **`--exclude SingleThreadUITests`** (UI XCTest files are never reformatted).
- **SwiftLint `--strict`** in CI → every warning is an error. Budgets (`.swiftlint.yml`): line_length 120/150, type_body_length 500/600, file_length 650/800, cyclomatic_complexity 12/15. **35 opt-in rules enabled** incl. accessibility label/trait rules. `identifier_name` ≥ 3 chars (exceptions `id`, `e`, `d`, `rt`, `to`, `gvm`).
- **Xcode build settings** (`project.pbxproj`): `SWIFT_VERSION = 6.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the iOS and watch app targets (NOT Core/widget/tests — annotate `@MainActor` explicitly there), `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide, `DEBUG_INFORMATION_FORMAT = dwarf` for Debug. Scope per-target overrides in the pbxproj, never via CLI flags.
- **Periphery** (`.periphery.yml`): scans the `SingleThread` scheme; `retain_swift_ui_previews: true`; UI tests excluded from reports.
- **Unit-test naming**: Swift Testing (`import Testing`, `@Test`) — do NOT start names with `test`/`testing` (SwiftFormat `preferSwiftTesting` strips prefixes and silently renames). UI tests (XCTest) keep `test…` and are SwiftFormat-excluded.
- **Force-unwrapping banned outside tests**; relaxed in `SingleThreadTests/.swiftlint.yml`.

## 4. Test-suite inventory

### iOS/macOS unit suite — `SingleThreadTests/` (Swift Testing, 516 `@Test` per `scripts/count_tests.sh:10`; runs on iOS AND macOS; macOS run = `mac-test`/CI `mac-tests`)
| File | Covers | Gating |
|---|---|---|
| `ReminderStoreTests.swift` | skip set gen/race/reload, complete, nudge threshold suite (`ReminderStoreSkipCountTests` `:505+`), lifecycle guards, hasHidden, allSkipped | `#if !os(watchOS)` blocks at `:672, :718, :883, :1004`; nudge tests `#if os(iOS) \|\| os(watchOS)` `:557` |
| `EventKitStoringTests.swift` | FakeEventStore write path: complete/delete/reschedule, error → silent, prune-on-delete | `#if !os(watchOS)` `:96, :146, :369` |
| `ReminderStoreGateTests.swift` | canMutate 4-combination table, gated no-ops for all mutations | `@Suite(.serialized)` `:11` |
| `ActionButtonTests.swift` | enableActionButtons gate (on/off/no-reminder/all-skipped) | **whole-file `#if os(iOS)`** `:8` |
| `SkipCountStoreTests.swift`, `ReminderSkipTests.swift` | threshold logic, skip-set logic | — |
| `ShowDate/ShowList/ShowRecurrence/ShowAlarms/ShowCompletionGlowPreferenceTests.swift` | default-on/off + round-trip | — |
| `UITestingSeedTests.swift` | seed JSON schema parse matrix, reset-clears | — |
| `SkippedReminderSyncServiceTests.swift` | send/receive payload keys, complete/delete relays | `#if os(iOS) \|\| os(watchOS)` |
| `EntitlementSyncTests.swift` | entitlement → watch push | `#if os(iOS) \|\| os(watchOS)` |
| `SettingsViewModelTests.swift`, `SettingsViewTests.swift`, `InterfaceSettingsView` pieces | allowsLandscape, showPreferenceChanged, bag | `#if os(iOS)` blocks inside |
| `AppDelegateTests.swift`, `AppearanceModeTests.swift`, `BackgroundCardTests.swift`, `MicrophoneToggleTests.swift` | platform pieces | whole-file or block `#if os(iOS)` / `#if os(macOS)` |
| `AppGroupTests.swift`, `CompletionCounterStoreTests.swift`, `EntitlementStoreTests.swift`, `UndoStoreTests.swift`, `PendingCompletionStoreTests.swift`, `ExcludedListStoreTests.swift`, `BackgroundImageStoreTests.swift`, `BackgroundFadeTests.swift`, `CompletionGlowTests.swift`, `CardPlateTests.swift`, `CardPlateModifierTests.swift`, `CodeSpanFormatterTests.swift`, `ColorCrossPlatformTests.swift`, `ContentViewModelTests.swift`, `Dictation*`/`TranscriptionAccumulatorTests.swift`, `ListContentTests.swift`, `LocalizationTests.swift`, `MinimumDisplayDurationTests.swift`, `PendingCompletionLogicTests.swift`, `PrivacySettingsContentTests.swift`, `ReminderDeepLinkTests.swift`, `ReminderDisplayTests.swift`, `ReminderIntentsTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `ResumptionGateTests.swift`, `SettingsCaptionTests.swift`, `SortOptionTests.swift`, `SwipePromptTests.swift`, `TextSizeTests.swift`, `URLOpeningTests.swift`, `AboutViewTests.swift`, `AppInfoTests.swift`, `BackgroundPhotoLayerTests.swift`, `StubBundle.swift`, `LocalizationTestHelpers.swift`, `BackgroundTestFixtures.swift` | per-name coverage | some `@Suite(.serialized)` (e.g. `BackgroundImageStoreTests.swift:8`) |

Serialized suites (`@Suite(.serialized)`) exist wherever tests write shared real UserDefaults keys (e.g. `ReminderStoreGateTests:11`, `EventKitStoringTests:148`, `ReminderStoreTests:15`, `Show*` state tests on watch) — parallel execution races on shared `.standard` keys.

### watch unit suite — `SingleThreadWatchTests/` (36 `@Test`; runs on watchOS)
| File | Covers |
|---|---|
| `ReminderStoreWatchTests.swift` | watch complete → pending-completion insertion (serialized; `:30-108`) |
| `ShowCompletionGlowStateTests.swift` | state-holder semantics + `--ui-testing-glow`/`-disabled` flags (`:46-61`, serialized) |
| `WatchAppViewModelTests.swift` | stable reminderViewModel instance; glow 2.0 s seam |
| `WatchReminderViewRegressionTests.swift` | view regressions |
| `WatchSyncPipelineTests.swift` | push omits phone-only keys (`:38, :358`), receive applies every present key (`:63-121`), preference survives relaunch (`:164`), absent keys no-op (`:121-...`) |

### iOS UI suite — `SingleThreadUITests/` (XCTest; iOS only; SwiftFormat-excluded)
| File | Covers |
|---|---|
| `SingleThreadUITestCase.swift` | base: `launchApp` `:16-21`, `launchSeeded` `:23-25`, `flipToggle` `:28-42`, `assertTogglePersists` `:45-60`, `statusLabel` `:62-75` |
| `SingleThreadUITestsFlows.swift` | skip (swipe), complete, delete (context menu), toggle persistence (bg/pin `:289-361`, reminder toggles `:425-465`, swipe prompt `:552-594`, undo `:632-663`), freemium gate states |
| `SingleThreadUITests.swift` / `SingleThreadUITestsLaunchTests.swift` / `SingleThreadUITestsAppearanceLaunchTests.swift` | launch/appearance gates, a11y audit (`testAccessibilityAudit`) |
| `ActionButtonsUITests.swift` | cluster renders + skip advances `:21-41`, a11y audit `:43-63` |
| `SkipNudgeUITests.swift` | banner→delete `:26-51`, reschedule `:55-84`, view-in-reminders URL `:88-137` |
| `NotificationsSettingsUITests.swift` / `NotificationsUITests.swift` / `NotificationSchedulingUITests.swift` | notification toggle, scheduling statuses |

### watch UI suite — `SingleThreadWatchUITests/` (XCTest; watchOS only)
`SingleThreadWatchUITests.swift` (dialog-by-label, a11y audit), `SingleThreadWatchUITestsFlows.swift` (launchApp default `["--ui-testing"]` `:190-195`; skip `:77-88`, nudge `:92-120`, delete `:124-138`, gated `:158-175`, glow `:177-211`), `SingleThreadWatchUITestsLaunchTests.swift`.

### Metrics (`scripts/count_tests.sh`)
516 iOS unit `@Test`, 36 watch unit `@Test` (552 total); 962 `#expect` + 46 `#require`; 24 iOS + 11 watch `.launch()`.

## 5. Launch-arg seams (test-only; see research.md Q2/Q6 for full refs)
- **iOS**: `--seed '<json>'` (in-memory store + AppGroup persistence, **forces `enableActionButtons=true`** after reset), `--ui-testing` (Buy-groceries store, also forces the toggle), `--reset-glow-preference`, `--reset-swipe-preference`, `--ui-testing-glow`, `--ui-testing-notifications`, `--url-opener-spy`. Both seams reset persisted state so defaults apply on first render.
- **Watch**: `--ui-testing`, `--ui-testing-gated`, `--ui-testing-glow` / `--ui-testing-glow-disabled`, `--ui-testing-priority <n>`, `--ui-testing-skip-count <n>`, `--ui-testing-excluded-list "<l>"`, `--ui-testing-live-excluded "<l>"`.

## 6. Key identity & persistence facts
- Person/user-facing preference keys (`showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders`, `sortOption`) live in `AppGroup.defaults`; repeated per-target typing via `@AppStorage(store:)` + Core `XPreference` structs. `UITestingSeed.resetPersistedState` (`UITestingSeed.swift:31-50, :60-92`) lists every persisted key — new persisted state should be added there or seeded launches will leak it.
- Watch applies received prefs into `.standard` (== AppGroup by fallback, `AppGroup.swift:20-22`).
- Store mutations use `calendarItemIdentifier` as identity everywhere; skip counts are per-identifier under `"skipCounts"`.

## 7. Coding conventions that affect structure
- One SwiftUI view per file; `ContentView` (716 lines) is split into `ContentView+iOS.swift` / `+Settings.swift` / `+Previews.swift` with header comments citing the `file_length`/`type_body_length` budgets (`ContentView.swift:1-8`).
- Shared multi-target strings only via `SharedStrings` (`LocalizedString+Shared.swift:3-7`); a11y ids follow `<action>Button` / `nudge<Action>Button` / `settings<Thing>Row` / `<feature>Toggle` / `<thing>Picker` patterns (see research.md Q7).
- New test suites must be added to `Makefile`'s `test` target and/or `scripts/test.sh` if they need explicit `-only-testing:` filters, and to CI matrix groups for iOS UI classes.