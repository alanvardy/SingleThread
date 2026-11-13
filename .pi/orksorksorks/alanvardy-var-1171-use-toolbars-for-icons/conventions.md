# Conventions & Factual Appendix — VAR-1171

Dense reference for Design / Structure / Plan. Facts as of
`alanvardy-var-1171-use-toolbars-for-icons`.

## Canonical commands

| Purpose | Command | Source |
|---|---|---|
| Format | `make format` (swiftformat over `SingleThread/ SingleThreadTests/ SingleThreadUITests/ …`) | `Makefile` |
| Lint | `make lint` → `swiftformat --lint` + `swiftlint lint --strict` | `Makefile`, `AGENTS.md` |
| Periphery | `make periphery` (`periphery scan --strict -- -destination "$(SIM)"`) | `Makefile` |
| iOS build | `make build` (`xcodebuild … build-for-testing`, `SIM` default `.simulator_id` else `platform=iOS Simulator,name=iPhone 17`) | `Makefile:37` |
| iOS unit | `make test` → `./scripts/test.sh --unit-only` | `Makefile:98` |
| iOS UI | `make ui-test` → `./scripts/test.sh --ui-only` | `Makefile:101` |
| Full gate | `make check` → `./scripts/test.sh` (run once via `run-gate` skill) | `Makefile`, `AGENTS.md` |
| macOS build | `make mac-build` (`MAC_SIM := platform=macOS`, `CODE_SIGNING_ALLOWED=NO`) | `Makefile`, `scripts/test.sh:18` |
| macOS unit | `make mac-test` → `xcodebuild … -destination "$(MAC_SIM)" … test -only-testing:SingleThreadTests` | `Makefile:46-47` |
| Watch build/test | `make watch-build` / `make watch-test` / `make watch-ui-test` (`WATCH_SIM`, `WATCH_TEST_SIM`) | `Makefile`, `scripts/test.sh:11-17` |
| Single test | `scripts/test-one.sh <Target/Suite>` (pins `.simulator_id`, exits non-zero on zero-match, 600 s bound) | `scripts/test-one.sh`, `AGENTS.md` |

- Destination precedence: explicit `SIM=` > worktree `.simulator_id` > shared default
  `platform=iOS Simulator,name=iPhone 17` (`scripts/test.sh:10-72`, `Makefile:1-11`).
- iOS UI is `-only-testing:SingleThreadUITests` (`scripts/test.sh:287`, `:363`, `:371`);
  watch `SingleThreadWatchUITests`/`SingleThreadWatchTests` (`:296-297`, `:317`, `:325`);
  macOS unit `SingleThreadTests` (`:334`, `:349`).
- `scripts/test.sh` also runs deployment-target drift checks (`:102-215`) — macOS pinned to
  26.5, iOS/watchOS literals checked. App target is a native macOS build
  (`SUPPORTED_PLATFORMS` includes `macosx`), not Catalyst.
- CI (`.github/workflows/ci.yml`): iOS device matrix `["iPhone 17", "iPad (A16)"]` (`:22-25`),
  separate `mac-tests` job (`:161`), periphery (iOS destination, `:282`), watch (`:286`).
- Only two shared schemes exist — `SingleThread.xcscheme`, `SingleThreadWatch.xcscheme`;
  macOS reuses `SingleThread` with `MAC_SIM`.
- Swift Testing caveat: a bare `<Target/Suite/case>` matches zero; use suite level or append
  `()` to the case name. XCTest (UI) keeps the bare `test…` name.
- Unit-test names must NOT start with `test`/`testing` (SwiftFormat strips them); UI-test
  (XCTest) names keep `test…`. See `AGENTS.md`.

## Test-suite inventory (relevant to this surface)

Unit (`SingleThreadTests`, Swift Testing; platform gating by whole-file or inline `#if os`):

| File | Covers | Gating |
|---|---|---|
| `SingleThreadTests.swift:75,109,130,149` | macOS refresh/gear/dictate reflection signatures; reschedule-sheet native chrome | case-level `#if os(macOS)` |
| `SingleThreadButtonModifierTests.swift:11,20` | `.singleThreadButton()` present/absent in reflected chain | none |
| `MacOSActionButtonChromeTests.swift:13,22,29` | macOS action buttons: `ControlPlateModifier` + `SingleThreadButtonModifier`; menu borderless style; no tint | whole file `#if os(macOS)` (`:1`) |
| `ActionButtonTests.swift:21+` | `ContentViewModel.showsActionButtons` gate (cluster is `_ConditionalContent`, not reflectable) | whole file `#if os(iOS) || os(macOS)` (`:8`) |
| `MicrophoneToggleTests.swift:14,31` | `settingsGearButtonIsPresent` (asserts `"Settings"` a11y label), `micButtonHiddenWhenSpeechDenied` | none shown |
| `CardPlateModifierTests.swift:14,22` | `CardPlateModifier` chain shapes | none |
| `AppDelegateTests.swift:9-22,28-54` | appearance replay on a bare `UIWindow`; orientation masks | whole file `#if os(iOS)` (`:1`) |
| `UndoStoreTests.swift`, `SwipeToActModifierTests.swift`, `TransitionAnimationTests` (if any) | iOS undo/swipe chrome-adjacent logic | check inline gates |
| `AppViewModel*`/`ContentViewModelTests.swift` | gate/view-model behavior | mixed |
| `EntitlementStoreTests.swift` | purchases; three macOS-local failures (see `AGENTS.md`) | mixed |
| `SingleThreadWatchTests/*` | watch chrome (`WatchSkipButtonAppearanceTests.swift`, `WatchReminderViewRegressionTests.swift`) | watchOS |

UI (`SingleThreadUITests`, XCTest, `#if os(iOS)`):
| File | Covers |
|---|---|
| `SingleThreadUITests.swift:31` `testLaunchAndRenderSmoke` | `--ui-testing` launch; `completeButton` `:46`, `skipButton` `:48`, `dictateButton` `:50`; `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` `:59-67` |
| `:207`, `:276` | tap `settingsButton` (`:212`, `:280`) then `settingsInterfaceRow`/`languagePicker` |
| `:190` | action-menu flow: up-drag then `rescheduleButton`/`deleteButton` (`:194-197`) |
| `:238-239` | settings title text (string assertion, not toolbar structure) |

Watch UI: `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` (XCTest).

Introspection conventions:
- Unit chrome tests use `String(describing: view.body)` / `String(describing: subview)` —
  reflected generic type chain, NOT `Mirror` and NOT accessibility values. A11y identifiers and
  labels do not survive reflection (`SingleThreadTests.swift:88-108,116-124,137-144`).
- Where reflection cannot see a runtime `_ConditionalContent` branch, tests assert the
  ViewModel gate instead (`ActionButtonTests.swift:12-19`).
- UI tests query accessibility identifiers and run `performAccessibilityAudit`.
- No test anywhere constructs a `ToolbarItem` or asserts on `.toolbar` structure.
- Reflection tests for chrome are `#if os(macOS)`-guarded; the iOS cluster's rendered existence
  is covered only by the UI smoke test.

## Build / verify gotchas

- One `xcodebuild` test process at a time; on `Busy`/`RequestDenied`, shut down sims and kill
  orphaned `xcodebuild`/`xctest` (see `simulator-pairing` skill).
- Name-only `iPhone 17` is ambiguous with multiple runtimes; a bare `name=` destination can hang,
  and unanchored matching can pick the leftover `Gate iPhone 17` sim. Pin by UDID or `SIM=`.
- Watch UI tests need an **unpaired** watch pinned by UDID via `WATCH_TEST_SIM`.
- `make periphery` reads a stale build index after branch switches — clean `DerivedData/` first.
- Debug builds only: `DEBUG_INFORMATION_FORMAT = dwarf`; Release uses `dwarf-with-dsym`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the iOS app and watch app targets only;
  `SingleThreadCore`, widget, and test targets must annotate `@MainActor` explicitly.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; the gate fails on any source-located
  compiler warning. Allowed toolchain/SDK diagnostics go in `scripts/xcodebuild-warnings.allow`.
- UI extras locally: the accessibility audit runs `.hitRegion`/`.dynamicType` locally beyond CI —
  a local hit-region failure can be local-only.
- Known local-only failures: three macOS `EntitlementStoreTests`
  (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`)
  — do not debug.
- Adding a new `.swift` file needs no pbxproj edit (synchronized file groups); a new **test target**
  does (pbxproj IDs, scheme TestAction, `-only-testing` entry, CI matrix).

## Relevant view-code inventory (for Structure/Plan)

| Concern | Location |
|---|---|
| Root `body` `ZStack` | `ContentView.swift:168-171` |
| Settings gear overlay | `ContentView.swift:181-197` (`.controlPlate()` `:188`, `.singleThreadButton()` `:191`, id `settingsButton` `:193`) |
| macOS refresh overlay | `ContentView.swift:199-225` |
| iOS undo overlay | `ContentView.swift:228-249` (id `undoButton`) |
| `reminderList` / `bottomBar` attach | `ContentView.swift:423-543` (`.empty` `:445-456`, `.reminder` `:458-543`) |
| `bottomBar` | `ContentView.swift:727` (iOS branch `:748-757`) |
| `actionCluster` (iOS) | `ContentView.swift:571-577` |
| `completeButton` (iOS) | `ContentView.swift:558-569` |
| `micButton` (shared) | `ContentView.swift:582-592` |
| `recordingIndicator` | `ContentView.swift:594-600` |
| `creationFeedbackView` | `ContentView.swift:651-658` |
| `upgradePrompt` (iOS) | `ContentView.swift:705-724` |
| `skipButton` (iOS) | `ContentView+ActionMenu.swift:71-93` |
| macOS `actionButtons`/menu | `ContentView+ActionMenu.swift:104-196` |
| `controlPlate` modifier | `ControlPlateModifier.swift:12-56` (56×56 circle) |
| `singleThreadButton` modifier | `SingleThreadButtonModifier.swift:10-22` (`.borderless`) |
| App scene / WindowGroup | `SingleThreadApp.swift:9,19-26`; delegates `:72-78` |
| iOS AppDelegate | `AppDelegate.swift:16-58` (`#if os(iOS)`) |
| Info.plist | `SingleThread/Info.plist` (only `SENTRY_DSN`) |
| Generated scene-manifest keys | pbxproj `:773-774`, `:824-825` |
| Existing `.toolbar` sites | `ContentView+iOS.swift:75-78`, `ContentView+ActionMenu.swift:216-219`, `SettingsView.swift:203-209`, `PurchaseSettingsView.swift:181-187`, `WatchReminderView.swift:316-318` |
| `localizedNavigationTitle` | `LocalizedNavigationTitle.swift:16-27` |
