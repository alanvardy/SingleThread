# Conventions — build, verify, test inventory

Shared factual appendix for Design/Structure/Plan. All paths relative to repo
root. Line numbers from the current tree. The local machine and CI run the same
gate (`./scripts/test.sh`); tests run on iPhone 17 / iPad (A16) simulators and
a standalone watchOS simulator.

## Canonical commands

- Full CI-identical gate (format → lint → build → watch build → Periphery →
  unit → UI → watch UI → watch unit → macOS unit): `./scripts/test.sh`
  (scripts/test.sh mode table at `:188-202`). Flags: `--unit-only`, `--ui-only`.
- `make` targets (Makefile):
  - `build` — iOS `build-for-testing` on `$(SIM)` (Makefile:18-19)
  - `watch-build` — `SingleThreadWatch` on `$(WATCH_SIM)` (Makefile:21-22)
  - `test` → `scripts/test.sh --unit-only` (Makefile:57-58); `ui-test` →
    `--ui-only` (Makefile:60-61); `check` → full script (Makefile:84-85)
  - `watch-ui-test` (Makefile:67-74) and `watch-test` (Makefile:76-82) — the
    two watch `-only-testing:` suites on `$(WATCH_TEST_SIM)`
  - `mac-test` (Makefile:24-25), `lint` (Makefile:88-91: swiftformat --lint +
    `swiftlint lint --strict`), `format` (Makefile:93-95: swiftformat + `swiftlint
    --fix`), `periphery` (Makefile:97-98: `periphery scan --strict`),
    `coverage`/`coverage-ui`/`coverage-all` (Makefile:28-56)
- Simulator selection: `SIM ?= platform=iOS Simulator,name=iPhone 17`
  (Makefile:1), `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch
  Series 11 (46mm)` (Makefile:5), `WATCH_SIM = generic/platform=watchOS
  Simulator` (Makefile:2). `scripts/test.sh` resolves a name-only SIM to its UDID
  and pre-boots it (`scripts/test.sh:41-63`); watch UI tests **require a
  concrete device** (name-only works only when exactly one standalone watch sim
  exists, Makefile:3-5, scripts/test.sh:8-10). Pin with `SIM=…` or
  `WATCH_TEST_SIM='platform=watchOS Simulator,id=<UDID>'`.

## Build / verify gotchas (research-surfaced)

- **One xcodebuild test process at a time** (simulator contention); on runner
  `Busy`/`RequestDenied`, `xcrun simctl shutdown all` and kill orphaned
  xcodebuild/xctest (AGENTS.md).
- **Destination pinning**: name-only `iPhone 17` / watch destinations are
  ambiguous with multiple runtimes and hang — pin `,OS=` or `,id=` (AGENTS.md;
  scripts/test.sh:41-47).
- CI creates an **unpaired** standalone watch simulator for the watch UI suite
  (`.github/workflows/ci.yml:391-405`); no `simctl pair` needed — the sync
  service no-ops without sessions (`WatchAppViewModel.swift:173`) and the
  live-excluded test injects the context directly (`:291-299`).
- Local watch-UI gate workaround: `scripts/test.sh` embeds
  `lib_TestingInterop.dylib` into the watch UI-test runner when the local
  watchOS simruntime lacks it (CI's runtime includes it) — see comment at
  scripts/test.sh:216-228.
- **Deployment-target guard**: `./scripts/test.sh` (full mode) enforces
  IPHONEOS 18.7, macOS/watchOS 26.5 across pbxproj (20 literals) and Package.swift
  (3 platform floors) and fails on drift (scripts/test.sh:66-132).
- **XCTest-runtime pruning**: full gate deletes stale `~/Library/Developer/
  XCTestDevices` runtimes older than `RUNTIME_AGE_HOURS` (default 1 h,
  scripts/test.sh:64-87) — disk hygiene, never touches in-flight runs.
- Swift 6 language mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only on app
  targets — `SingleThreadCore`, widget, and test targets annotate `@MainActor`
  explicitly (AGENTS.md). `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide.
- SwiftLint `--strict` (every warning fails) with 35 opt-in rules; identifiers
  ≥ 3 chars; force-unwraps banned outside tests
  (`SingleThreadTests/.swiftlint.yml` relaxes). Unit tests use **Swift Testing**
  (`import Testing`, `@Test`); **test names must not start with `test`/
  `testing`** (SwiftFormat strips those prefixes and renames silently); UI tests
  use XCTest and are SwiftFormat-excluded.
- Every persisted value shared with the watch round-trips through
  `AppGroup.defaults` (`UserDefaults(suiteName:) ?? .standard`,
  AppGroup.swift:11,16-17), never `UserDefaults.standard` directly — including
  `--ui-testing*` seams (AGENTS.md).
- Unit + UI coverage policy: every feature/bug ships a unit test; UI tests only
  when justified (accessibility audits, end-to-end flows); watch UI tests use
  the `--ui-testing*` seams, never a real EKEventStore (AGENTS.md).

## Test-suite inventory

### iOS unit tests — `SingleThreadTests/` (Swift Testing; run via
`-only-testing:SingleThreadTests` on iPhone 17 + iPad (A16), CI matrix
ci.yml:21-87, and on macOS ci.yml:270-310)

Relevant to the watch/refresh/delete topics:
- `MinimumDisplayDurationTests.swift:11-30` — min-spinner math (watch refresh pad).
- `ActionMenuGateTests.swift:6-31` — 2×2×2 truth table for `showsActionMenu`.
- `ReminderStoreTests.swift` — reload no-op when `loadsReminders` false
  (`:430-435`), skip-not-reapplied generation test (`:356-363`), delete/reset
  behavior.
- `ReminderSkipTests.swift`, `SkipCountStoreTests.swift` — skip persistence,
  nudge-threshold crossing (`crossedThreshold`).
- `PendingCompletionLogicTests.swift`, `PendingCompletionStoreTests.swift` —
  watch-relayed completion filter.
- `ReminderStoreGateTests.swift`, `ResumptionGateTests.swift` — canMutate/gating.
- `ShowEnableActionButtonsState` equivalents live in the watch unit target
  (below), not here.
- Also: AboutView, ActionButton, AppDelegate, AppearanceMode, AppGroup,
  AppInfo, Background*, BoolPreference*, CardPlate*, CardWidth,
  CodeSpanFormatter, ColorCrossPlatform, CompletionCounterStore,
  CompletionGlow, ContentViewModel, EnableActionButtonsMigration/Sync,
  EntitlementStore/Sync, EventKitStoring, ExcludedListStore, ListContent,
  Localization, MacOSActionButtonChrome, MicrophoneToggle, NotificationScheduler,
  PrivacySettingsContent, ReminderDeepLink, ReminderDictation(Parser),
  ReminderDisplay, ReminderIntents, ReminderRecurrenceFormatter,
  RescheduleSheet/Sync, Settings*, SingleThreadButtonModifier, SingleThreadTests,
  SkippedReminderSyncService, SortOption, SwipePrompt, TextSize,
  TranscriptionAccumulator, UITestingSeed, UndoStore, URLOpening,
  UserNotificationCentering. (No `#if os(...)` gating in this target — the same
  suite runs on iOS and macOS simulators.)

### Watch unit tests — `SingleThreadWatchTests/` (Swift Testing; run via
`-only-testing:SingleThreadWatchTests` on the concrete watch simulator,
scripts/test.sh and ci.yml:420-429)

- `ReminderStoreWatchTests.swift` — watchOS pending-completion insertion
  (`completeReminder` on watch must not resurrect on pre-relay `reload`),
  `@Suite(.serialized)`; `@MainActor` fixture with file-level live `EKEventStore`
  (deallocated store → SIGTRAP).
- `WatchSyncPipelineTests.swift` — receive hooks persist before firing
  (`:521-560`), inscluded absent-key behavior.
- `ShowEnableActionButtonsStateTests.swift` — `apply` persists to App Group
  suite (`:38-42`), `init` reads persisted value (`:45-49`).
- `ShowCompletionGlowStateTests.swift` — `--ui-testing-glow` /
  `--ui-testing-glow-disabled` seam mapping (`:48-51`).
- `WatchAppViewModelTests.swift` — stable root VM instance; glow seam extends
  duration to 2.0.
- `WatchReminderViewRegressionTests.swift` — canvas/render path reads every
  `ReminderDisplay` field (SIGTRAP regression).

### iOS UI tests — `SingleThreadUITests/` (XCTest; iOS seam `--seed "<json>"`,
driven by `InMemoryEventStore`; CI splits `ui-tests-flows` ci.yml:89-149,
`ui-tests-launch-appearance` ci.yml:150-208, `ui-tests-audits` ci.yml:209-268)
- `SingleThreadUITests.swift` — a11y audit with CI/local categories (see
  research Q4). `NotificationsUITests.swift` — whole-file `#if os(iOS)`.
- `ActionButtonsUITests.swift` — action buttons + audit. `ActionMenuUITests.swift`,
  `SkipNudgeUITests.swift` — swipeLeft on the iPhone card (`:31`). Also
  NotificationScheduling, NotificationsSettings, appearance LaunchTests,
  `SingleThreadUITestCase.swift` base.

### Watch UI tests — `SingleThreadWatchUITests/` (XCTest; seams `--ui-testing*`
per research Q5; CI `watch-ui-tests` ci.yml:369-429, `-retry-tests-on-failure`,
`-parallel-testing-enabled NO`, `-maximum-concurrent-test-simulator-destinations
1`, 900 s allowance)
- `SingleThreadWatchUITests.swift` — `testTapRevealsConfirmationDialog`
  (`:9-27`); `testAccessibilityAudit` (`:30-42`, `#if os(watchOS)` → full
  `.dynamicType/.hitRegion/.sufficientElementDescription/.trait` set, `:38-40`).
- `SingleThreadWatchUITestsFlows.swift` — 14 flows (`:13,:25,:39,:58,:76,:92,
  :110,:134,:159,:189,:224,:243,:262,:282`) + `launchApp()` (`.swift:317-322`):
  card display, priority marker, exclusion (static + live), complete, skip→all
  done, action menu (show/delete/reschedule), nudge-delete dialog, delete via
  card dialog, empty-state refresh, upgrade prompt, glow hold.
- `SingleThreadWatchUITestsLaunchTests.swift` — `testLaunch` with
  `["--ui-testing"]`, `runsForEachTargetApplicationUIConfiguration = true`.

## Watch seam reference (from research Q5)
`--ui-testing` (fixture store, WatchAppViewModel.swift:108-168) · `-priority <n>`
(`:119-121`) · `-skip-count <n>` (`:130-133`) · `-excluded-list <l>` /
`-live-excluded <l>` (`:143-157`, delivery `:286-299`) · `-gated` (`:26-27`) ·
`-glow` / `-glow-disabled` (`:50-59`) · `-action-menu` (`:61-67`; plain
`--ui-testing` resets the menu toggle OFF). `--seed` is iOS-only.