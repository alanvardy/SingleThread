# Conventions — Shared Factual Appendix

For Structure/Plan: canonical commands, the test-suite inventory, and build/verify gotchas. Do not re-read the source tree for these facts.

## 1. Canonical commands

### Makefile targets (`Makefile`)
| Target | Command | Notes |
|---|---|---|
| `make build` | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug build-for-testing` (Makefile:17-18) | `SIM` defaults to `platform=iOS Simulator,name=iPhone 17` (Makefile:1); `export SIM` (:13); override with `SIM="platform=iOS Simulator,id=<UDID>"` |
| `make test` | `./scripts/test.sh --unit-only` (:75-76) | iOS unit tests only |
| `make ui-test` | `./scripts/test.sh --ui-only` (:78-79) | iOS UI tests only |
| `make check` | `./scripts/test.sh` (:100-101) | full pipeline (format, lint, build, watch build, periphery, unit + UI tests, watch tests, macOS unit tests) — CI-identical |
| `make lint` | `swiftformat --lint` all dirs + `swiftlint lint --strict` (:106-108) | `--strict` makes warnings errors |
| `make format` | `swiftformat` all dirs + `swiftlint --fix` (:110-112) | covers SingleThread Core Watch Widget + all 4 test dirs |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` (:114-115) | |
| `make watch-test` / `make watch-ui-test` | `xcodebuild -scheme SingleThreadWatch … -only-testing:SingleThreadWatchTests / SingleThreadWatchUITests` (:84-98) | uses `WATCH_TEST_SIM` = `name=Apple Watch Series 11 (46mm)` (:7) |
| `make mac-test` | macOS scheme, `CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` (:26-28) | |
| `make coverage` / `coverage-ui` / `coverage-all` | `-enableCodeCoverage YES` + `xcrun xccov view --report` (:37-73) | |

### `scripts/test.sh` (`scripts/test.sh`)
- Modes: `full` (no arg) / `--unit-only` / `--ui-only` (`MODE="${1:-full}"`, :87-90).
- Prologue: resolves a name-only `SIM` to its concrete UDID and **pre-boots** it (`resolve_sim_udid` :25-31, `preboot_sim` :32-37, call :41-47); prunes stale `~/Library/Developer/XCTestDevices` runtimes older than `RUNTIME_AGE_HOURS` (default 1, :19, :50-79).
- **Deployment-target guard runs before anything else** (`verify_deployment_target` :118-193): every `IPHONEOS_DEPLOYMENT_TARGET` literal must be `18.7` (8 targets), every `MACOSX_`/`WATCHOS_` literal `26.5` (12), count check `EXPECTED_TARGET_LITERALS=20`; `Package.swift` floors `.iOS("18.7")`/`.watchOS("26.5")`/`.macOS("26.5")` — `EXPECTED_PACKAGE_LITERALS=3`.
- Full pipeline (:202-298): SwiftFormat apply + lint, SwiftLint `--strict`, iOS build-for-testing, watch build (generic), Periphery (index-store from DerivedData, `--skip-build`), iOS unit tests (`-parallel-testing-enabled YES`, :230-237), iOS UI tests (serial), watch UI tests + watch unit tests (concrete `WATCH_TEST_SIM`), macOS unit tests (`CODE_SIGNING_ALLOWED=NO`).
- Local-only watch fix: embeds `lib_TestingInterop.dylib` from the Xcode watchsimulator platform into the watch UI test runner if the local simruntime lacks it (:255-268).

### CI (`.github/workflows/ci.yml`)
- `unit-tests`, `ui-tests-{flows,launch-appearance,audits}`, `mac-tests`, `lint`, `watch-ui-tests` jobs; iOS jobs **matrix over `iPhone 17` and `iPad (A16)`** (ci.yml:25-26).
- UI tests split into 3 disjoint `-only-testing` groups via env vars (UI_GROUP_A/B/C, ci.yml:15-19).
- All xcodebuild test steps: `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` (comments: clone contention/timed-out lockdown on virtualized runners) and `-retry-tests-on-failure` (UI jobs).
- Watch UI job **creates a fresh standalone watch simulator** "CI Watch S11" because the image's paired watches make name-only destinations ambiguous (ci.yml watch-ui-tests job).
- `lint` job: `mise install` from `.mise.toml` then `swiftformat --lint` + `swiftlint lint --strict` + watch build + `periphery scan --strict -- -destination "platform=iOS Simulator,name=iPhone 17"`.

## 2. Test-suite inventory

Schemes: `SingleThread` tests only `SingleThreadTests` + `SingleThreadUITests`; `SingleThreadWatch` tests only `SingleThreadWatchUITests` + `SingleThreadWatchTests` (per `xcshareddata/xcschemes/*.xcscheme`). **No widget test target exists.**

### iOS unit tests — `SingleThreadTests/` (Swift Testing, `@Test`; scheme SingleThread; also run on macOS via test.sh/CI mac job)
| File | Covers | Notable tests |
|---|---|---|
| `ReminderIntentsTests.swift` | intent configuration only (never executes `perform()`) | `completeIntentIsConfigured` :11, `skipIntentIsConfigured` :25 — `isDiscoverable == false`, title via `.main` catalog |
| `ReminderStoreTests.swift` | ReminderStore core + 3 sub-suites | suites :17,:508,:688,:790; visible filtering :20/:51/:77; skip+refetch+generation gate :246-344; complete :369/:404; loadsReminders guard :418; hasHidden/allSkipped :441/:471; undo :512-610; pending-completion :692-768; makeReminder :797+ |
| `EventKitStoringTests.swift` | ReminderStore against `EventKitStoring` fake | save/reload & silent-error paths :151-259; skip-prune-on-delete :274 (real keyed store); access state machine :318-386; window predicate :389-413; `loadsReminders: false` :421; `testStore` helper :483 |
| `ReminderStoreGateTests.swift` | freemium gate | canMutate matrix :18-36; gated complete/skip/delete :44/:82/:131 |
| `UITestingSeedTests.swift` | `--seed` parser + reset | serialize suite :10; parsing :12-123; end-to-end store render :131; resetPersistedState :147+ |
| `SkippedReminderSyncServiceTests.swift` | WCSession seam (FakeSession :15) | push shape :52/:77; receive replace/clear/malformed :110-235; sort :248/:264; complete/delete relays :282-339; excluded :352-398; show-* keys + gating :433-552 |
| `EntitlementSyncTests.swift` | isEntitled/completionCount wire keys | :18,:39,:59,:79,:94,:113 |
| `AppGroupTests.swift`, `ExcludedListStoreTests.swift`, `PendingCompletionStoreTests.swift`, `CompletionCounterStoreTests.swift` | App Group store round-trips | suiteName :9 (asserts `group.app.alanvardy.SingleThread`); replace-not-union :19; suite isolation |
| `SortOptionTests.swift`, `ReminderSkipTests.swift`, `ReminderPriorityTests.swift`, `ReminderSortTests.swift`, `ReminderNotesFormatterTests.swift` | sort/skip logic + formatting | |
| `Show*PreferenceTests.swift` ×5 + `ShowAlarmsTests`/`ShowDateTests`/`ShowRecurrenceTests` | preference defaults/round-trips + row rendering | absent-key defaults (date/recurrence/alarms/glow = enabled, list = disabled) |
| `LocalizationTests.swift` | localizable catalogs incl. **widget** | :171-236 validate `SingleThreadWidget/Resources/Localizable.xcstrings` + widget InfoPlist.strings keys |
| `SettingsViewModelTests.swift` | settings view model (comment at :7: WidgetCenter reload is delegation w/o observable state) | |

### Watch unit tests — `SingleThreadWatchTests/` (Swift Testing; scheme SingleThreadWatch; runs on watchOS sim)
| File | Covers | Notable tests |
|---|---|---|
| `WatchSyncPipelineTests.swift` | watch-side service behavior | watch push omits show-* :38/:308; receive applies/absent-no-op :63/:114/:236/:286; survives relaunch :157; excluded refresh :171; per-key show flags :204/:264/:331 |
| `WatchAppViewModelTests.swift` | launch-arg seams | stable view model :11; `--ui-testing-glow` → 2.0 s glow duration :21 |
| `ReminderStoreWatchTests.swift` | watch PendingCompletionStore | persist/hide/no-op/preserve :31-89 |
| `WatchReminderViewRegressionTests.swift` | watch view smoke | renders every field without crashing :31 |

### iOS UI tests — `SingleThreadUITests/` (XCTest; scheme SingleThread)
- `SingleThreadUITestCase.swift` — helpers: `launchApp(arguments:)` :13, `launchSeeded(json:extra:)` :21, `flipToggle` :28, `assertTogglePersists` :45.
- `SingleThreadUITestsFlows.swift` — `--seed`-driven flows: seeded list, empty/nothing-due (hasHidden), skip advances priorities, all-done, cross-device completion, swipe-complete, context-menu delete, settings, about modal, background/pin persistence (relaunch uses `--ui-testing` deliberately — `resetPersistedState` would wipe the keys), code blocks, glow enable/disable (`--ui-testing-glow`), undo, upgrade/gating (completionCount 100), purchase/restore. Refs: :23-704 across the file.
- `ActionButtonsUITests.swift` — `--ui-testing`: Complete/Skip cluster + skip→All Done (:20), a11y audit (:46).
- `SingleThreadUITests.swift` — accessibility audit (:27, `--reset-swipe-preference`).
- `SingleThreadUITestsLaunchTests.swift` / `SingleThreadUITestsAppearanceLaunchTests.swift` — launch/appearance without Reminders TCC prompt (`--no-reminders`).
- `NotificationSchedulingUITests.swift`, `NotificationsUITests.swift`, `NotificationsSettingsUITests.swift` — `--ui-testing-notifications` seam strings; springboard bundle id for the Allow prompt (`NotificationsUITests.swift:32`).

### Watch UI tests — `SingleThreadWatchUITests/` (XCTest; scheme SingleThreadWatch; every launch uses `--ui-testing`)
- `SingleThreadWatchUITests.swift` — confirmation dialog (:9), a11y audit (:30).
- `SingleThreadWatchUITestsFlows.swift` — card title/notes (:13), priority (`--ui-testing-priority 7`, :25), excluded list (`--ui-testing-excluded-list Work`, :39), live exclusion (:58), complete (:76), skip→All Done (:92), delete (:108), refresh (:127), upgrade gating (`--ui-testing-gated`, :146), glow hold (:166).
- `SingleThreadWatchUITestsLaunchTests.swift` — launch :15.

### Launch-arg seams (single source of truth)
- `--seed '<json>'` → `UITestingSeed.fromLaunchArguments` (`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:44-56`, `materialize` :131-157, `resetPersistedState` :58-96 wipes 24 keys from both suites) → `AppViewModel.seededStore` (`SingleThread/AppViewModel.swift:290-329`, `InMemoryEventStore` + `EntitlementStore(testingWith…)`).
- `--ui-testing` (iOS) → `AppViewModel.swift:245-272` (single "Buy groceries", `loadsReminders: false`, `.fullAccess`, action buttons on). `--ui-testing-glow` :209-212; `--reset-glow-preference`/`--reset-swipe-preference` :246-251.
- `--ui-testing*` (watch) → `SingleThreadWatch/WatchAppViewModel.swift:12-18` (`uiTestingStore` :96-138), `--ui-testing-gated` seeds completionCount at cap :26-27, glow seams :48-55, live-excluded delayed context delivery :234-245.
- `InMemoryEventStore` (`InMemoryEventStore.swift:13`) — `EventKitStoring` with `allReminders` array, `.fullAccess`, fetch filters `!isCompleted`, `makeReminder` :103-121 backed by process-wide scratch store `sharedStore` :126 (avoids EventKit connection-cap issues), `deliverCompletionOffMain` init flag :17/:65-78.

## 3. Build/verify gotchas
- **Destination pinning**: `name=iPhone 17` alone is ambiguous (4 runtimes on this machine) and hangs a bare xcodebuild; `scripts/test.sh` (and CI) resolve the UDID and pre-boot (:25-47; ci.yml pre-boot steps). Local ad-hoc xcodebuild must pass `,OS=<ver>` or `,id=<UDID>`.
- **One xcodebuild test process at a time locally** (simulator contention). On `Busy`/`RequestDenied`: prune `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`.
- **XCTest runtimes accumulate** ~3 GB per UI run in `~/Library/Developer/XCTestDevices`; test.sh prunes >1 h old automatically (scripts/test.sh:50-79, `RUNTIME_AGE_HOURS`).
- **Watch UI tests need a concrete standalone watch sim** (name-only ambiguous when paired simulators exist): `WATCH_TEST_SIM` (Makefile:7); CI creates "CI Watch S11". Local watchOS 26.5 runtime may miss `lib_TestingInterop.dylib` — test.sh patches the runner (:255-268).
- **Warning-as-error policy**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; **SingleThreadTests overrides to NO** (StoreKitTest headers contain an iOS-18-deprecated symbol that otherwise blocks PCM emission). Never pass `SWIFT_TREAT_WARNINGS_AS_ERRORS` via CLI.
- **Actor isolation asymmetry**: app + watch app targets default `@MainActor` (`project.pbxproj:777/:827, :961/:989`); widget target and all test targets do **not**. In widget/Core code annotate `@MainActor` explicitly (widget `makeEntry` `NextThingWidget.swift:61`; intents `ReminderIntents.swift:17,40`; `ReminderStore` itself `ReminderStore.swift:9`). Swing 6 / approachable-concurrency everywhere.
- **Deployment floors**: iOS 18.7 / macOS 26.5 / watchOS 26.5; `scripts/test.sh` fails the run if any pbxproj/package literal drifts (scripts/test.sh:118-193; watchOS has no 18.x line — that is why watch/mac floors stay 26.5).
- **App Group discipline**: every cross-process value (incl. `--seed`/`--ui-testing` seams and their resets) must round-trip `AppGroup.defaults` (the suite), never `UserDefaults.standard` — on simulator both exist and diverge silently; watchOS falls back to `.standard` by design (`AppGroup.swift:16-18`).
- **Unit-test naming**: SwiftFormat strips `test`/`testing` prefixes from Swift-Testing function names (silent rename) — use descriptive names instead (e.g. `visibleRemindersFiltersSkippedAndEmpty`).
- **SwiftFormat/SwiftLint**: run `make format` then `make lint` before committing; CI enforces both plus Periphery (`--strict`).
- **`--seed` wipes persisted state** (`UITestingSeed.resetPersistedState`, UITestingSeed.swift:58-96) — UI tests that must survive relaunch use `--ui-testing` (plus `--reset-glow-preference`) instead of `--seed` (SingleThreadUITestsFlows.swift:262, :386).
- **UI tests avoid the Reminders TCC prompt** via `--seed`/`--ui-testing`/`--no-reminders`; the only springboard interaction is the notification "Allow" prompt (NotificationsUITests.swift:32).
- **Coverage**: `make coverage` (unit), `coverage-ui`, `coverage-all`; result bundles under `build/*.xcresult` (Makefile:8-10, :37-73).