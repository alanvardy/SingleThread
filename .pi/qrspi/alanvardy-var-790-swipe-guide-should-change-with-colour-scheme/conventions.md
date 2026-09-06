# Project Conventions (shared factual appendix)

Branch: `alanvardy-var-790-swipe-guide-should-change-with-colour-scheme`
Purpose: canonical commands, test inventory, and build/verify gotchas so Design/Structure/Plan need not re-open `Makefile`, `scripts/test.sh`, or the test sources. All refs verified by grep.

## Canonical commands

Source of truth: `Makefile`, `scripts/test.sh`, `.github/workflows/ci.yml`, plus home/project `AGENTS.md`.

- Full CI-identical gate (format, lint, build, periphery, unit + UI + macOS unit + watch tests): `./scripts/test.sh` — mode parse `scripts/test.sh:86-97`; full pipeline block `:195-297`. Sub-modes: `./scripts/test.sh --unit-only` (`:299+`) / `--ui-only` (`:335+`).
- Make targets (line refs `Makefile`): `build` `:17` (iOS build-for-testing), `watch-build` `:20`, `mac-build` `:23`, `mac-test` `:26` (unit-only on macOS), `coverage`/`coverage-ui`/`coverage-all` `:37/50/63`, `test` `:75` (= `scripts/test.sh --unit-only`), `ui-test` `:78`, `simverify` `:81`, `watch-ui-test` `:84`, `watch-test` `:92`, `check` `:100` (= full `scripts/test.sh`), `lint` `:106` (swiftformat --lint + swiftlint --strict), `format` `:110` (swiftformat + swiftlint --fix), `periphery` `:114` (`periphery scan --strict`).
- CI jobs (`.github/workflows/ci.yml`): `unit-tests` `:21` (iPhone 17 + iPad A16 matrix), `ui-tests-flows` `:89` (Group B: Flows), `ui-tests-launch-appearance` `:150` (Group A: Launch + AppearanceLaunch), `ui-tests-audits` `:209` (Group C: main audit + ActionButtons), `mac-tests` `:270`, `lint` `:322` (swiftformat --lint + swiftlint --strict + watch build + periphery), `watch-ui-tests` `:369`. iOS UI classes split into disjoint groups via env `:12-19`.
- Watch pairing for UI tests: standalone ("unpaired") watch sim required — CI creates one via `simctl create` (`ci.yml:394-401`); locally `WATCH_TEST_SIM` default `Apple Watch Series 11 (46mm)` (`Makefile:7`; `scripts/test.sh:14`). Watch UI tests need a CONCRETE device destination (name-only ambiguous) — `scripts/simverify.sh`, `scripts/run-devices.sh` (devicectl install/launch).
- Format/lint configs: `.swiftformat` (organizeDeclarations, preferSwiftTesting; UI tests excluded), `.swiftlint.yml` (35 opt-in rules, `--strict` in CI → every warning an error), `.periphery.yml`.

## Gotchas (surfaced by research)

- **Destination pinning**: name-only `iPhone 17` is ambiguous when multiple runtimes exist — `scripts/test.sh` resolves `name=` to a concrete UDID via `xcrun simctl list devices available` (`:25-52`) and pre-boots it (`:40-45`); CI does the same (`ci.yml:52-58` per job). Override with `SIM=platform=iOS Simulator,id=UDID` (`Makefile:1`). A bare `name=` hangs.
- **One xcodebuild test process at a time** (simulator contention). CI disables parallel sim clones (`-parallel-testing-enabled NO`, `-maximum-concurrent-test-simulator-destinations 1`) in every UI/unit job (`ci.yml:85-87, 125-127, 186-188, 245-247, 312-314`); local full gate enables parallel unit tests (`scripts/test.sh:236-237`). On `Busy`/`RequestDenied`: shut down sims, kill orphaned xcodebuild/xctest.
- **Watch runtime library**: local watchOS sim runtime is missing `lib_TestingInterop.dylib` — `scripts/test.sh:257-269` embeds the Xcode-side lib into the runner; CI ships it (comment at `:258-259`).
- **Deployment-target guard**: `scripts/test.sh:119-192` fails on any drift of the 20 `*_DEPLOYMENT_TARGET` literals (iOS 18.7; macOS/watchOS 26.5) and 3 `Package.swift` floor literals.
- **XCTest runtime cleanup**: each UI run leaves ~3 GB in `~/Library/Developer/XCTestDevices`; `scripts/test.sh:54-83` prunes entries older than `RUNTIME_AGE_HOURS` (default 1 h).
- **Concurrency compiler house rules**: iOS/watch app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (async defaults to `@MainActor`; no `Task { @MainActor in }` needed); `SingleThreadCore`/widget/test targets do NOT — annotate explicitly. Swift 6 (`SWIFT_VERSION=6.0`), `SWIFT_APPROACHABLE_CONCURRENCY=YES`. Warnings are errors everywhere (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`).
- **Persistence rule**: every value shared with the watch must round-trip through `AppGroup.defaults`, never `UserDefaults.standard` — incl. `--ui-testing`/`--seed` seams (`AGENTS.md`). `UITestingSeed.resetPersistedState()` clears BOTH suites over 24 keys including `"showSwipePrompt"` (`UITestingSeed.swift:88-111`).
- **Swift unit test naming**: unit-test functions must not start with `test`/`testing` (SwiftFormat strips the prefix under `make format`); follow camelCase convention. Force-`!` banned outside test code (`SingleThreadTests/.swiftlint.yml` relaxes fixtures).
- **UI-test seams** for deterministic flows: iOS `--seed '<json>'` (`UITestingSeed.fromLaunchArguments`, `SingleThreadCore/.../UITestingSeed.swift:44-56`) backed by `InMemoryEventStore`; `--ui-testing` + `--reset-swipe-preference`/`--reset-glow-preference` (`AppViewModel.swift:257-263`); watch `--ui-testing` seam.

## Test-suite inventory

### SingleThreadTests (unit, Swift Testing) — `SingleThreadTests/`
Runs on iOS (`scripts/test.sh:237, 315`) AND macOS (`scripts/test.sh:285-292`; `ci.yml:270-320 mac-tests`). Uses `@testable import SingleThreadCore` for package-domain tests. Function names must NOT start with `test`.

Appearance/swipe-guide-relevant:
- `AppearanceModeTests.swift` — pins every `AppearanceMode` mapping (`.system/.light/.dark` -> UIUserInterfaceStyle, NSAppearance, ColorScheme) + `load(from:)` fallback (`:13-79`).
- `AppDelegateTests.swift` — pins `applyAppearance` window override incl. `.system -> .unspecified` clear (`:11-23`); runs on iOS and macOS (gated per platform).
- `CardPlateTests.swift` — pins `plateFill(for: .light/.dark)` and `promptBoxFill == Color(red:0.16,0.17,0.18)` (`:16-36`).
- `SwipePromptTests.swift` — reflected-body snapshots: "Swipe left to skip", "Swipe right to complete", "CardPlateModifier", "style: orange", "style: green", "Dismiss", "BorderedProminentButtonStyle" (`:9-54`); `promptBoxFill` pin (`:38`).
- `BackgroundCardTests.swift` — light/dark plate fills (`:69-77`).
- `SettingsViewTests.swift` — settings-bag default/round-trip for `showSwipePrompt` (`:21-26`) and expected settings rows incl. "Show swipe prompt" + caption (`:93-120`).
- `UITestingSeedTests.swift` — seed parsing/seeding; `resetPersistedStateClearsShowSwipePrompt` (`:163-166`).
- `LocalizationTests.swift` — every `.xcstrings` key non-empty in EN + 5 languages (`:36-111`).
- `ColorCrossPlatformTests.swift` — `Color.systemBackground` cross-platform mapping.
- `CardPlateModifierTests.swift` — modifier-chain snapshot `"CardPlateModifier"` (`:10-23`).

Other unit files (categories, from `ls`): About/ActionButton/ActionMenuGate, AppGroup/AppInfo, Background*(fade/imageStore/photoLayer/fixtures), BoolPreferenceKey/Store, CodeSpanFormatter, CompletionCounterStore, CompletionGlow, ContentViewModel, EnableActionButtons Migration/Sync, EntitlementStore/Sync, EventKitStoring, ExcludedListStore, ListContent, MicrophoneToggle, MinimumDisplayDuration, PendingCompletionLogic/Store, PrivacySettingsContent, ReminderDeepLink, ReminderDictation/Parser, ReminderDisplay, ReminderIntents, ReminderRecurrenceFormatter, ReminderSkip, ReminderStoreGate, ReminderStore, RescheduleSheet/Sync, ResumptionGate, SettingsCaption, SettingsSubscreenLayout, SettingsViewModel, ShowAlarms, ShowDate, ShowRecurrence, SingleThreadTests (modifier-chain dump), SkipCountStore, SkippedReminderSyncService, SortOption, StubBundle, TextSize, TranscriptionAccumulator, UndoStore, URLOpening.

### SingleThreadUITests (XCTest) — `SingleThreadUITests/`
iOS (iPhone 17 + iPad A16 in CI: `ci.yml:21-88, 89-149...`). Launch seams: `--ui-testing`, `--reset-swipe-preference`, `--reset-glow-preference`, `--seed <json>` (helper `launchSeeded(_:extra:)` `SingleThreadUITestCase.swift:22-31`).
- `SingleThreadUITestsFlows.swift` — swipe-prompt flows: appears under ui-testing (`:517-524`), dismiss persists across relaunch (`:529-551`), settings toggle round-trip (`:556-599`).
- `SingleThreadUITestsAppearanceLaunchTests.swift` — cold-launch appearance, runtime appearance toggle via picker, device-following clears override (`:48-170`).
- `SingleThreadUITests.swift` — `testAccessibilityAudit` (`:23-66`): `performAccessibilityAudit` with CI vs local category lists; launched with `--ui-testing --reset-swipe-preference` so the prompt renders during the audit.
- `SingleThreadUITestsLaunchTests.swift`, `ActionButtonsUITests.swift` (audit + flows), `ActionMenuUITests.swift`, `SkipNudgeUITests.swift`, `NotificationsUITests.swift` (`#if os(iOS)`, seeded + audit `:103-110`), `NotificationsSettingsUITests.swift`, `NotificationSchedulingUITests.swift`, `SingleThreadUITestCase.swift`.

### SingleThreadWatchUITests — `SingleThreadWatchUITests/`
Standalone-paired watch sim only; `--ui-testing` seam.
- `SingleThreadWatchUITests.swift` — watch accessibility audit `:39-42`.
- `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift`.

### SingleThreadWatchTests — `SingleThreadWatchTests/`
Watch unit tests; run via `watch-test` (`Makefile:92`) and CI watch job (`ci.yml:369+`, `scripts/test.sh:280-283`).

### Note
`SingleThreadCore` is a library-only SPM package (`Package.swift:1-16`) — NO `.testTarget`; its logic is tested through `SingleThreadTests` via `@testable import`. No widget test target exists. Watch test targets reference the swipe guide nowhere (it is iOS-only).

## Platform gating summary
- `#if os(iOS)` whole-file: `NotificationsUITests.swift`. Partial gating: `AppearanceMode.swift` (UIKit/AppKit/ColorScheme vars), `AppDelegate.swift` (iOS vs macOS delegate classes), `ContentView.swift:100-103` (@AppStorage iOS-only), `InterfaceSettingsView.swift:98-109`, `ContentView+Settings.swift:21-31`, `SingleThreadUITests.swift:54-64` (CI vs local vs macOS audit).
- Unit tests run on iOS AND macOS destinations (`SingleThreadTests` is one target, `AppearanceModeTests`/`AppDelegateTests` test both platform halves with `#if`).
- watchOS has NO appearance plumbing; swipe guide absent (`SingleThreadWatch/` zero hits).