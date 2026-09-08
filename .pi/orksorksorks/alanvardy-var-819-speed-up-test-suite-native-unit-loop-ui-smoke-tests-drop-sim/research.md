# Research Findings

## Q1: `scripts/test.sh full` pipeline — phases, destinations, dependencies, slicing

### Findings
- Config block `scripts/test.sh:4-20`: `SIM` (iOS Sim, name=iPhone 17, env-overridable, `:5`), `WATCH_SIM` (generic watch, build only, `:6`), `WATCH_TEST_SIM` (concrete `Apple Watch Series 11 (46mm)`, run phases, `:11`; comment `:7-10` — xcodebuild needs a concrete device to run XCTests), `MAC_SIM="platform=macOS"` (`:12`, not env-overridable), `SCHEME`/`WATCH_SCHEME` (`:13-14`), `DERIVED_DATA="DerivedData"` (`:15`) shared by every invocation.
- iOS sim pre-boot `:22-48`: `resolve_sim_udid()` (`:26-29`) + `preboot_sim()` (`:33-35`, `simctl boot` + `bootstatus -b`); comment `:31-32` matches CI pre-boot. Name resolved to `id=` `:40-45`.
- Runtime cleanup `cleanup_xctest_runtimes()` `:52-83`, invoked at `:104` right after mode dispatch — prunes stale ~3 GB XCTest runtimes in `$HOME/Library/Developer/XCTestDevices` older than `RUNTIME_AGE_HOURS` (default 1 h, `:19`).
- Mode dispatch `:85-99`: `MODE="${1:-full}"`; `--unit-only`→`UNIT_ONLY=1` (`:89`), `--ui-only`→`UI_ONLY=1` (`:90`), `full`→both `0` (`:91`); unknown arg→usage + exit 1 (`:93-98`).
- Deployment-target guard `verify_deployment_target` `:110-192`, runs in ALL modes (`:194`): `IPHONEOS=18.7`, others 26.5 (`:110-113`); checks pbxproj literals (`:120-137`) and Package.swift floors (`:139-150`), plus literal-count drift (`:152-153`).

**Full pipeline order** `:196-295` (guard `:196`, `set -euo pipefail` `:2` aborts on first failure):
| Phase | lines | Scheme | Dest | Action/filters |
|---|---|---|---|---|
| format | 197-200 | — | — | `swiftformat` + `swiftlint --fix` (mutates) |
| fmt check | 202-204 | — | — | `swiftformat --lint` |
| swiftlint | 206-207 | — | — | `swiftlint lint --strict` |
| iOS build | 210-216 | SingleThread | `$SIM` | Debug `build-for-testing` (unfiltered) |
| watch build | 218-224 | SingleThreadWatch | `$WATCH_SIM` generic | Debug `build` |
| periphery | 227 | — | — | `--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` |
| **iOS unit** | 230-237 | SingleThread | `$SIM` | `test-without-building -only-testing:SingleThreadTests -parallel-testing-enabled YES -maximum-test-execution-time-allowance 900` |
| iOS UI | 240-245 | SingleThread | `$SIM` | `test-without-building -only-testing:SingleThreadUITests` |
| watch build+test | 248-255 | SingleThreadWatch | `$WATCH_TEST_SIM` | Debug `build-for-testing -only-testing:SingleThreadWatchUITests -only-testing:SingleThreadWatchTests` (both in one invocation) |
| watch dylib fix | 257-267 | — | — | `cp` `lib_TestingInterop.dylib` into runner Frameworks (local-only no-op) |
| watch UI run | 269-274 | SingleThreadWatch | `$WATCH_TEST_SIM` | `test-without-building -only-testing:SingleThreadWatchUITests` |
| watch unit run | 277-282 | SingleThreadWatch | `$WATCH_TEST_SIM` | `test-without-building -only-testing:SingleThreadWatchTests` |
| **macOS unit** | 285-291 | SingleThread | `$MAC_SIM` | Debug + `CODE_SIGNING_ALLOWED=NO` `test -only-testing:SingleThreadTests` (self-building) |

- **iOS-Sim unit pass (phase 7) runs 6 phases BEFORE the macOS-native unit pass (phase 13, last)**: in between are iOS UI, watch build, dylib fix, watch UI, watch unit. Same `-only-testing:SingleThreadTests` set on both.
- Shared dependencies: one pre-booted iOS sim serves build (4) + iOS unit (7) + iOS UI (8) via `test-without-building`; all phases share `$DERIVED_DATA`; periphery consumes the index from builds 4+5; phase 9's products are what phase 10 patches and 11/12 run; phase 13 builds itself with `CODE_SIGNING_ALLOWED=NO` (its own products, independent of 4/7/8).
- **Slicing**: `--unit-only` `:300-317` = iOS Sim build-for-testing `-only-testing:SingleThreadTests` (`:301-307`) + test-without-building (`:309-315`); **never runs macOS unit, watch, lint, or periphery**. `--ui-only` `:322-341` = same pair with `-only-testing:SingleThreadUITests` (`:323-329`, `:331-337`). Both reuse the full-mode invocation shape but move the filter onto the build. Pre-boot, runtime cleanup, and deploy-target guard run in every mode.
- Makefile mirrors: `test`→`--unit-only` (`Makefile:78-79`), `ui-test`→`--ui-only` (`:81-82`), `check`→full (`:103-104`); `mac-test`/`watch-test`/`watch-ui-test`/`simverify` are independent raw invocations (`:26`, `:87-101`, `:84`).

## Q2: `SingleThreadTests` — iOS Simulator vs macOS native execution

### Findings
- Single native unit target `project.pbxproj:269-290` with `SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx"` (`:775,:825,:850,:879,:907,:931`); the same 77 `.swift` files compile/run on both iOS Sim and native macOS. Executed at iOS-sim (`scripts/test.sh:230-237`), macOS (`:285-291`), CI unit-tests (`ci.yml:78`), CI mac-tests (`ci.yml:309-311`).
- **Counts**: "520" = raw `@Test` annotation count across `SingleThreadTests/` (496 plain + 24 `@Test(arguments:)`), stable at HEAD and HEAD~1. "564" = historical xcodebuild-*executed* count from `var-790/implement.md:15,19`; at VAR-790 commits the raw annotation count was ~499-504, so 564 includes parameterized-case expansion + churn. `SingleThreadWatchTests` has 44 `@Test` across 7 files.
- **All platform gating is compile-time `#if os(...)`; no runtime skip.** Compiled-out-on-macOS files (57 `@Test`): `AppDelegateTests.swift:1` (UIKit), `BackgroundCardTests.swift:8` (Speech), and `#if os(iOS)||os(watchOS)` WatchConnectivity files `EntitlementSyncTests.swift:1`, `RescheduleSyncTests.swift:1`, `SkippedReminderSyncServiceTests.swift:1`, `EnableActionButtonsSyncTests.swift:1`. macOS-only (5 `@Test`): `MacOSActionButtonChromeTests.swift:1`, `MenuBarExtraOptionsTests.swift:1`. In-file gates: `AppearanceModeTests.swift:18-27` (iOS UIKit) / `:31-40` (macOS AppKit), `MicrophoneToggleTests.swift:232,270`, `SettingsViewTests.swift` multiple, `SettingsSubscreenLayoutTests.swift:13,25`, `AboutViewTests.swift:26`, `ReminderStoreTests.swift:557,673`. Net per-destination source sets: iOS ≈515, macOS ≈468; ~458 universal tests run on BOTH (macOS pass is largely a duplicate re-run).
- **EventKit available on both** (real store differs): real `EKEventStore()` fixtures at `EventKitStoringTests.swift:141,557,562,570`, `ReminderStoreTests.swift:1109,1122`, `ReminderStoreGateTests.swift:168`. On sim these hit an empty sim store; on macOS the real host Reminders/Calendar store (TCC-gated). `MakeReminderTests.makeReminderSetsDefaultCalendar` (`ReminderStoreTests.swift:1108-1115`) is the test depending on real store behavior; everything else uses `InMemoryEventStore`/`FakeEventStore` reporting `.fullAccess`. No test calls `requestFullAccessToReminders()` on a real store → no TCC prompt fires on either destination.
- **Sharpest divergence — StoreKit/entitlement**: `EntitlementStoreTests.swift` (8 `@Test`); `hostStoreKitIsClean` `:91-106` iterates real `Transaction.currentEntitlements`; doc `:86-89` — macOS unsigned run (`CODE_SIGNING_ALLOWED=NO`) reads the real per-user host store, so a dev who has purchased sees non-empty entitlements and it fails until cleared. `SKTestSession.buyProduct` broken via `xcodebuild test` on Xcode 26.6 (`:36`, FB22237318).
- **Other one-destination behaviors**: App Group suite (`AppGroup.swift:11`, fallback `.standard` `:15-16`) is provisioned on sim but may fall back on the unsigned macOS bundle; WatchConnectivity (48 `@Test`) never compiles on macOS; UIKit/UIWindow tests run only on sim; macOS-only chrome tests run only natively. `CODE_SIGNING_ALLOWED=NO` only on macOS passes (`test.sh:291`, `Makefile`, `ci.yml:299,309`). Notification-delivery timing differs (`EventStoreChangedObserverTests.swift:52-54`).
- Core seam: `EventKitStoring.swift` (`ReminderStore.swift:24,546`); `#if !os(watchOS)` carve-outs on `makeReminder`/`save`/`remove`/`refreshSourcesIfNecessary` (`EventKitStoring.swift:31-40,45-61`).

## Q3: platform-conditional execution facilities actually available

### Findings
- Versions: Swift 6.0 (`.swift-version:1`; `SWIFT_VERSION` 6.0 in all 14 build configs `project.pbxproj:780,830,858,887,911,935,963,991,1023,1054,1074,1096,1120,1144`; `SingleThreadCore/Package.swift:1`); installed toolchain Xcode 26.6 / Swift 6.3.3. `.mise.toml:1-4` pins only lint/format/periphery — no Swift toolchain pin.
- **`@available(on:)`/`@available(platform:)` — ABSENT** (repo-wide grep, zero matches).
- **Swift Testing skip traits (`@Test(.enabled(if:))`, `.disabled`, `.skip`) — ABSENT**; `XCTSkip`/`try XCTSkip` — ABSENT. Only `.enabled(`/`.disabled(` tokens are comment text about the app's `SingleThreadButtonModifier` (`SingleThreadTests.swift:89,92,112,132`). "skip" occurrences are all business-domain (reminder skip) logic.
- **Only two facilities exist**: compile-time `#if os(...)` (extensive) and `-only-testing:` invocation filters (extensive). No `-skip-testing`, no `-test-names`.
- **No existing precedent of a skipped/available-gated test anywhere.**
- `#if os(...)` + `-only-testing` interaction: `-only-testing:SingleThreadTests` selects the target by name; the compiler first applies `#if os(...)` for the active destination, so the runtime selector never sees members compiled out. In this target `os(watchOS)` is always false (platform set `pbxproj:850`), so `#if os(iOS)||os(watchOS)` gates reduce to `os(iOS)` (compile iOS-only); `#if !os(watchOS)` is always true here. Same filter → two different compiled populations at the two destinations.

## Q4: UI test targets — full surface

### Findings
- iOS `SingleThreadUITests/` = 9 files, **23 test methods** (+2 empty classes `ActionMenuUITests.swift`, `NotificationSchedulingUITests.swift`); watch `SingleThreadWatchUITests/` = 3 files, **15 test methods**. Counts confirmed by grep.
- **iOS classes & methods** (file:line — all `runsForEachTargetApplicationUIConfiguration = false` unless noted):
  - `SingleThreadUITests.swift:27` `testAccessibilityAudit` (a11y, CI carve-out).
  - `SingleThreadUITestsLaunchTests.swift:26` `testLaunch` (screenshot only).
  - `SingleThreadUITestsAppearanceLaunchTests.swift` (3, `--no-reminders`): `:33 testColdLaunchAppearance`, `:60 testRuntimeAppearanceToggle`, `:94 testDeviceFollowingClearsOverride`.
  - `SingleThreadUITestsFlows.swift` (12, default runsForEach true): `:19,30,39,56,95,135,200,225,259,305,317,344`.
  - `ActionButtonsUITests.swift` (2): `:20`, `:54 testActionButtonsAccessibilityAudit`.
  - `NotificationsSettingsUITests.swift` (2): `:6`, `:23`.
  - `NotificationsUITests.swift` (1, `#if os(iOS)` file): `:7 testAccessibilityAudit`.
  - `SkipNudgeUITests.swift` (1): `:27 testNudgedCardDoesNotSpanRowOnIPad` (iPad `frame.width < rowWidth − 80` geometry).
  - Empty: `ActionMenuUITests.swift`, `NotificationSchedulingUITests.swift`.
- **Watch `SingleThreadWatchUITests/`** (all default runsForEach true):
  - `SingleThreadWatchUITests.swift:9 testAccessibilityAudit`.
  - `SingleThreadWatchUITestsFlows.swift` (13): `:13,25,39,58,76,92,110,134,159,189,224,243,263`; private `launchApp()` helper `:298-304`.
  - `SingleThreadWatchUITestsLaunchTests.swift:15 testLaunch` — `runsForEachTargetApplicationUIConfiguration = true` (`:6-7`, the only explicit `true` in the repo).
- **`runsForEachTargetApplicationUIConfiguration`**: iOS forces `false` on the 4 standalone classes (SingleThreadUITests, LaunchTests, AppearanceLaunchTests, ActionButtons) `:18-19,:17-18,:17-18,:11-12`; everything else inherits XCTestCase default `true`. Watch uses `true` everywhere (one explicit `:6-7`, two implicit).
- **`performAccessibilityAudit` call sites & CI carve-out** (`SingleThreadUITests.swift`): `:53` `if CI=="true"` → CI runs only `[.sufficientElementDescription, .trait]` (`:54-56`); local iOS adds `.dynamicType, .hitRegion` (`:58-60`); macOS `#else` default audit (`:64`). Comment `:44` — `contrast`/`textClipped` deliberately skipped (false positives); `:46-52` — full traversal can hang on virtualized runners; `.dynamicType`/`.hitRegion` claimed covered by unit suites. Other call sites with **no carve-out**: `ActionButtonsUITests.swift:71,75`, `NotificationsUITests.swift:14`, `SingleThreadWatchUITests.swift:18`.
- **Unit-test mirroring via `--seed`/`--ui-testing`** (behavior-level): `UITestingSeedTests.swift` (seed parsing/reset), `ReminderDisplayTests.swift:13,51,55,93,98` (title/notes, priority), `SwipePromptTests.swift:33,42,36` (Dismiss label, hidden), `ActionButtonTests.swift` (visibility gating), `CompletionGlowTests.swift` (glow state), `SkipCountStoreTests.swift` (nudge threshold), `EntitlementStoreTests.swift` (freemium gate), `ExcludedListStoreTests.swift`, `NotificationPreferenceTests`/`NotificationSchedulerTests`, `AppearanceModeTests` (cited by AppearanceLaunchTests comment `:16-17`), `TextSizeTests` (dynamicType), `CodeSpanFormatterTests`, `BackgroundCardTests`/`BackgroundImageStoreTests`, `AboutViewTests.swift:18-22,36-37`, `PendingCompletionLogicTests.swift:13`, `RescheduleSheetTests`. **Not mirrored (UI-only)**: a11y identifiers/geometry (`emptyStateTitle`, `Nothing due`, `skipNudgeBanner`, `completionGlowOverlay`, `upgradePrompt`, iPad `frame.width<rowWidth−80`), screenshot/launch presence.

## Q5: `.github/workflows/ci.yml` map

### Findings
- `.github/` contains only `workflows/ci.yml`. Trigger: push to `main` (`:3-5`); concurrency cancel-in-progress (`:7-9`). Env group split (top-level `env:`, `:11-17`):
  - A = `LaunchTests` + `AppearanceLaunchTests` (`:14`); B = `Flows` (`:15`); C = `SingleThreadUITests` + `ActionButtonsUITests` (`:16`). Comment claims these cover "all 5 iOS UI classes" exactly once.
- **7 jobs** (all `macos-26`): `unit-tests` `:19-91`, `ui-tests-flows` `:93-161`, `ui-tests-launch-appearance` `:163-231`, `ui-tests-audits` `:233-301`, `mac-tests` `:303-357`, `lint` `:355-411`, `watch-ui-tests` `:405-472`.
- **Device matrices**: 4 iOS jobs each run `matrix.device: ["iPhone 17","iPad (A16)"]` (8 iOS legs total). `mac-tests`/`lint`/`watch-ui-tests` no matrix. `mac-tests` = native `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` (`:329-348`).
- **Simulator booting**: each iOS job pre-boots its own matrix sim by UDID (unit `:51-55`, flows `:125-129`, launch-appearance `:195-199`, audits `:265-269`). `watch-ui-tests` **creates** a fresh standalone unpaired "CI Watch S11" (Apple Watch Series 11 46mm) from newest watchOS runtime (`:429-440`) then boots it (`:442-445`), targeting `id=$WATCH_UDID` (`:449,460,469`). `lint` boots no sim (generic watch build `:395`, periphery name dest `:402`).
- **`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`**: present in all 4 iOS test steps (`:78-79,:151-152,:221-222,:291-292`); **absent** from the watch job. Rationale comment `:69-73` (EventKit/EKReminder SIGTRAP under clone contention) and `:143-148` (lockdown 120 s timeout). `-maximum-test-execution-time-allowance 900` in unit+3 UI+watch-UI (`:76,:149,:219,:289,:462`). `-retry-tests-on-failure` in the 3 iOS UI jobs + watch-UI (`:150,:220,:290,:463`), not unit/mac/watch-unit.
- **Artifacts**: upload `if: failure()` only for `unit-tests` (`:88-91`, `TestResults.xcresult`) and `mac-tests` (`:350-353`, `TestResults-mac.xcresult`); UI/watch jobs upload nothing. `-resultBundlePath` only in those two jobs.
- **CI never calls `scripts/test.sh`** — raw xcodebuild per job: unit-tests 2 (`:59,:71`), ui-tests-flows 2 (`:135,:143`), launch-appearance 2 (`:205,:213`), audits 2 (`:275,:283`), mac-tests 2 (`:332,:341`), lint 2 (`:395,:402`), watch 3 (`:449,:460,:469`). Common env overrides: `DEVELOPMENT_TEAM=` empty (`:36-37` etc.), `actions/cache@v4` on DerivedData (per-job keys), `maxim-lobanov/setup-xcode@v1` `26.6`.

## Q6: launch seams — argument to rendered UI

### Findings
- Chain: XCTest sets `XCUIApplication.launchArguments` → `app.launch()` installs/foregrounds → app reads `ProcessInfo.processInfo.arguments` → root view model builds store → view renders. No custom transport.
- **iOS `AppViewModel.makeStore` (`SingleThread/AppViewModel.swift:203`)**: 1) `--seed` wins (`:204-207`, `usesInMemory=true`); 2) iOS-only `--ui-testing` branch (`#if os(iOS)`, `:212-257`): resets glow/swipe prefs (`:216-220`), sets `enableActionButtons` (`:222`), builds `InMemoryEventStore` empty + `makeReminder("Buy groceries","Don't forget the milk", priority 5)` (`:227-235`), returns `ReminderStore(loadsReminders:false, … .fullAccess, EntitlementStore(testingWithEntitled:false))` (`:239-255`) — **`usesInMemory=false` for plain `--ui-testing`** (only `--seed` returns true), so `setupSyncService`'s guard `:360` does NOT skip on `--ui-testing`. 3) fall-through (`:259-261`): `loads = !(--ui-testing) && !(--no-reminders)`, real `EKEventStore` (macOS has no in-memory seeding — `#if os(iOS)`).
- **`seededStore` (`:274-335`)**: `UITestingSeed.resetPersistedState()` (`:275`), `InMemoryEventStore(reminders, calendars, defaultCalendar)` (`:276-279`), seeds `completionCount`/`skipCounts`/`enableActionButtons` into `AppGroup.defaults` (`:287,291,295`), entitlement via `EntitlementStore(testingWithEntitlementUnresolved:)`/`testingWithEntitled:` (`:296-301`), excluded lists (`:330-332`).
- **`UITestingSeed` (`SingleThreadCore/.../UITestingSeed.swift`)**: struct `:32` fields `:34-42`; `fromLaunchArguments` `:47-54` (parse `--seed` JSON, nil on malformed — unit-proven `UITestingSeedTests.swift:124-127`); `resetPersistedState` removes 24 keys `:58-96`; `SeedPayload: Codable` `:100-134` with `decodeIfPresent` defaults; `materialize()` `:138-164` creates scratch `EKEventStore`, EKCalendar/EKReminder, resolves title→identifier skip counts.
- **`InMemoryEventStore` (`SingleThreadCore/.../InMemoryEventStore.swift`)**: `EventKitStoring` impl `:13`; `.fullAccess` `:42-44`, `requestFullAccess→true` `:50-52`; `#if !os(watchOS)` for `save`/`remove`/`makeReminder` (`:76-103`) on a process-wide `sharedStore` (`:124-126`); watch build compiles those out.
- **Watch `WatchAppViewModel` (`SingleThreadWatch/WatchAppViewModel.swift`)**: `:14` `isUITesting = arguments.contains("--ui-testing")`; **no `--seed` path** (watch is always the fixed single reminder). `uiTestingStore` `:108-166` builds `EKReminder(title:"Buy groceries", priority 5, notes:"Don't forget the milk")` (`:109-112`) + flag overrides: `--ui-testing-priority` (`:117-121`), `--ui-testing-skip-count` (`:124-129`), `--ui-testing-excluded-list`/`--ui-testing-live-excluded` (`:135-157`); plain → `InMemoryEventStore(reminders:[reminder])` + `ReminderStore(loadsReminders:false, .fullAccess)` (`:159-165`). Glow/action-menu/gated flags `:21-27,50-68`; `--ui-testing-live-excluded` schedules a 5 s WCSession delivery `:288-296`.
- **Launch helpers**: iOS `SingleThreadUITestCase.swift:13` `launchApp(arguments:)`; `:21` `launchSeeded(json,extra)` = `["--seed",json,"--ui-testing-noop-settle","--ui-testing-reduced-glow"]+extra`; `:49` `assertTogglePersists` (relaunch plain `--ui-testing`); `:65` `statusLabel`. Watch private `launchApp()` `SingleThreadWatchUITestsFlows.swift:298-304`.
- **What plain `--ui-testing` renders (smoke surface)** — iOS: `ContentView.swift:171-174` (loadsReminders false → list, no TCC gate), card shows priority marker `"!!"` (`ReminderCardView.swift:90-96`), title "Buy groceries", notes "Don't forget the milk" (`:131-137`, id `notesText`), swipe prompt + "Dismiss swipe prompt" (`:47,172-205`), action cluster complete/skip/mic (`ContentView.swift:675-676`, `:510-518`). Watch: `WatchReminderView.swift:49-53,89-129` card with `"!!"` ("Medium priority" a11y) `:299-305`, title/notes `:313-319`, `completeButton`/`skipButton` (`:139,:154`); action-menu OFF by default (`:66-68`).
- **Launch-path differences iOS vs watch**: iOS pre-booted sim + plain install via `XCUIApplication.launch()`; watch needs concrete device (`scripts/test.sh:11`) + local pairing (`simulator-pairing` skill) / CI creates standalone unpaired sim (`ci.yml:429-440`). Watch runner needs `lib_TestingInterop.dylib` copied in locally (`scripts/test.sh:256-268`; CI's runtime ships it). `--seed` is iOS-only; watch uses only `--ui-testing` + flag family. UI-test targets have no `BUNDLE_LOADER`/`TEST_HOST` (`pbxproj:897/921,1067/1089`) — app installed/launched via runner, unlike unit targets which do (`:838/860,1106/1122`).

## Cross-Cutting Observations
- **Two platform-gating mechanisms, cleanly layered**: compile-time `#if os(...)` (the ONLY platform gate in the repo) decides membership; `-only-testing:` (target/class-level) decides runtime selection. Swift Testing/XCTest runtime skip APIs are entirely unused — no precedent exists.
- **The macOS native unit pass is a duplicate re-run** of ~458 universal tests plus the 5 macOS-only ones (Q2), running last in `test.sh` full and as a separate CI job; it is the most host-state-dependent (host EK store, real StoreKit entitlements) and non-hermetic.
- **iOS Simulator is the only multi-destination target** (`SingleThreadTests` compiles for both iOS sim and macOS); watch and UI targets are single-destination.
- **CI and `test.sh` are two independent pipelines** — CI uses raw xcodebuild per job with per-job sim boot + concurrency constraints; `test.sh` is a single sequential script. `Makefile` `test`/`ui-test`/`check` wrap `test.sh` modes.
- **CI's iOS UI env groups (A/B/C) reference only 5 classes**; `NotificationsSettingsUITests`, `NotificationsUITests`, and `SkipNudgeUITests` (4 methods) are NOT in any `-only-testing` group (verified against `ci.yml:14-16`), so they only run locally via `scripts/test.sh --ui-only`, never on CI.
- **Flakiness notes already codified**: `.dynamicType`/`.hitRegion` a11y dropped on CI, `contrast`/`textClipped` always skipped; SIGTRAP/EventKit clone-contention and lockdown timeout documented; macOS `EntitlementStoreTests` host-state flakiness documented (VAR-790).

## Open Areas
- **CI coverage gap for 3 iOS UI classes** (`NotificationsSettingsUITests`, `NotificationsUITests`, `SkipNudgeUITests`): the `ci.yml:12-13` comment claims the groups cover all iOS UI classes, but these classes are absent from `UI_GROUP_*`. Whether this is intentional (they're covered by unit tests) or a gap is unresolved from the code alone.
- Exact runtime *executed* test counts (vs source `@Test` counts) per destination were not measured this session — "520"/"564" provenance is inferred from git history and grep, not a fresh xcodebuild run.
- `-retry-tests-on-failure` retry counts and the specific flake history behind each CI inline comment are not enumerated beyond what the comments state.
- Watch UI/unit timing and the pairing requirement's exact failure modes are covered by the `simulator-pairing` skill but not re-derived here.
