# Qrspi Conventions — Shared Factual Appendix

Path shorthand: `Core/X.swift` = `SingleThreadCore/Sources/SingleThreadCore/X.swift`.

## Canonical Commands (Makefile / scripts/test.sh / CI)

- **Build**: `make build` → `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build-for-testing` (Makefile:9-11).
- **Full gate (CI-identical)**: `./scripts/test.sh` (alias `make check`, Makefile:49-51). Sub-modes: `make test` = `--unit-only`, `make ui-test` = `--ui-only` (Makefile:53-60). Script phases (scripts/test.sh:198-302): swiftformat (198), swiftlint --fix (199), swiftformat --lint (203), swiftlint lint --strict (207), iOS build (211-212), watch build (219-220), periphery (227), iOS unit `-only-testing:SingleThreadTests` (231-237), iOS UI `-only-testing:SingleThreadUITests` (241-245), watch unit+UI (249-255), macOS unit (287-292).
- **Watch**: `make watch-build` (Makefile:13-15), `watch-test` (35-38), `watch-ui-test` (28-33).
- **macOS**: `make mac-build` / `mac-test` (17-26), `code sign` disabled via `CODE_SIGNING_ALLOWED=NO`.
- **Lint/format**: `make lint` = `swiftformat --lint <dirs>` + `swiftlint lint --strict` (55-58); `make format` (60-62). UI test dirs are in the arg list but excluded by `.swiftformat` config (`--exclude SingleThreadUITests`).
- **Dead code**: `make periphery` = `periphery scan --strict -- -destination "$SIM"` (63-66); scripts/test.sh:227 uses `--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`.
- **Coverage**: `make coverage` (unit) / `coverage-ui` / `coverage-all`, result bundles under `build/Coverage*.xcresult` (Makefile:38-48).
- **Destinations** (Makefile:1-6): `SIM ?= platform=iOS Simulator,name=iPhone 17`, `WATCH_SIM = generic/platform=watchOS Simulator`, `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`, `MAC_SIM = platform=macOS`. `SIM` is exported and overridable (`SIM='...' make test` would work — but see gotchas).
- **CI** (.github/workflows/ci.yml): runners `macos-26`, Xcode 26.6 (`maxim-lobanov/setup-xcode`), iOS jobs run a **matrix over `device: ["iPhone 17", "iPad (A16)"]`** (ci.yml:22-27, :90-95, repeating); every run resolves `SIM_UDID` from `xcrun simctl list` (ci.yml:50).

## Test-Suite Inventory

### SingleThreadTests/ (unit, Swift Testing, `import Testing`)
Run via `-only-testing:SingleThreadTests` on iOS (and macOS variant). Names must NOT start with `test`/`testing` (SwiftFormat `.swiftformat` strips them — AGENTS.md).
- `CardPlateTests.swift` — shared card plate styling pins (corner radius 10, promptBoxFill dark grey, adaptive plateFill light/dark) :13-35. No gating.
- `CardPlateModifierTests.swift` — `.cardPlate` modifier chain + `restoresGeometry` negative-padding undo via `String(describing:)` :11-25. No gating.
- `RescheduleSheetTests.swift` — non-rendering `RescheduleSheet` helpers (`hasDueTime`, `displayedComponents`, `dateComponentsMask`) :12-40; EKEventStore-backed fixtures never saved :45-51.
- `SkipCountStoreTests.swift` — UserDefaults round-trip, `shouldNudge` threshold table, `crossedThreshold` fires-once :11-53; per-test UUID suites :57-61.
- `ReminderStoreTests.swift` — biggest skip-path coverage; `noopSettle` injectable `settle:` seam :12; `ReminderStoreSkipCountTests` :512+ **gated**: 6th-skip interrupt `#if os(iOS)||os(watchOS)` :557-580; reschedule reset `#if !os(watchOS)` :672-693; further `#if !os(watchOS)` blocks UndoCompletion :718-839 / MakeReminder :883+ / CompletedReturningEventStore :1004+. Serialized suites (shared AppGroup defaults).
- `ContentViewModelTests.swift` — deep-link + `--url-opener-spy` accessor :11-101; `refreshManual` :104-208. No card layout coverage.
- `UITestingSeedTests.swift` — `--seed` JSON parser :12-177.
- Others (no skip/card relevance): AboutView, ActionButton, ActionMenuGate, AppDelegate, AppearanceMode, AppGroup, AppInfo, Background*, BoolPreference*, CodeSpanFormatter, ColorCrossPlatform, CompletionCounter*, Entitlement*, EventKitStoring, ExcludedListStore, ListContent, Localization, MicrophoneToggle, MinimumDisplayDuration, PendingCompletion*, PrivacySettingsContent, ReminderDeepLink, ReminderDictation*, ReminderDisplay, ReminderIntents, ReminderRecurrenceFormatter, ResumptionGate, Settings*, ShowAlarms/Date/Recurrence, SwipPrompt, TextSize, TranscriptionAccumulator, UndoStore, URLOpening.

### SingleThreadUITests/ (XCTest, base `SingleThreadUITestCase.swift`)
Run via `-only-testing:SingleThreadUITests` on iOS.
- `SkipNudgeUITests.swift` — 6th-skip nudge end-to-end, seeded `--seed {...skipCounts:{Buy groceries:5}}` :24-26: delete :30-72, reschedule :76-103, view-in-Reminders URL spy :105-141.
- `ActionMenuUItests.swift` — menu Skip/Delete/Reschedule + toggle-off swipe-skip :21-125.
- `SingleThreadUItestsFlows.swift` — 27 flows, skip set :54-147; relaunch uses `--ui-testing`; glow `--seed`+`--ui-testing-glow`; swipe `--ui-testing --reset-swipe-preference`.
- `ActionButtonsUItests`, `Notification*UItests`, `SingleThreadUItests.swift`, `..LaunchTests`, `..AppearanceLaunchTests`.

### SingleThreadWatchTests/ (unit) — 6 files: ReminderStoreWatchTests, ShowCompletionGlowStateTests, ShowEnableActionButtonsStateTests, WatchAppViewModelTests, WatchReminderViewRegressionTests, WatchSyncPipelineTests.
### SingleThreadWatchUItests/ (XCTest) — 3 files: SingleThreadWatchUItests, ..Flows, ..LaunchTests; run via `WATCH_TEST_SIM` conditioned on paired sim
### SingleThreadCore package — no test target of its own

## Build/Verify Gotchas (research-surfaced)

- **Destination pinning**: bare `name=iPhone 17` is ambiguous with multiple runtimes; scripts/test.sh resolves `SIM_UDID` from `xcrun simctl list devices available` and re-pins `SIM=platform=iOS Simulator,id=$SIM_UDID` (scripts/test.sh:22-44). Watch UI tests likewise need a concrete `WATCH_TEST_SIM`.
- **One xcodebuild test process at a time**: simulator contention; on `Busy`/`RequestDenied` shutdown sims and kill orphaned xcodebuild/xctest. Watch UI tests need a paired sim (`simctl pair`).
- **AppGroup, never `UserDefaults.standard`**: every watch-shared persisted value must round-trip through `AppGroup.defaults` — including `--seed`'s skipCounts write (AppViewModel.swift:309-310). On simulator the suite always exists, so the two diverge silently.
- **Previews/tests inject pre-populated `ReminderStore` or `loadsReminders: false`** — never a real `EKEventStore`.
- **Seams**: `--seed '<json>'` (UITestingSeed.swift:44-56; schema :8-33) ↔ `--ui-testing` (AppViewModel.swift:257-286) ↔ `--ui-testing-glow` / `--url-opener-spy` / `--ui-testing-notifications` (iOS-only, AppViewModel.swift:216/:235/:414); seeded store path AppViewModel.swift:302-332 (InMemoryEventStore.swift backing).
- **SwiftLint `--strict`**: every warning is an error (CI) — 35 opt-in rules incl. accessibility/perf/concurrency; identifiers ≥3 chars; force-unwrapping banned outside test fixtures (relaxed via SingleThreadTests/.swiftlint.yml).
- **Unit-test naming**: names must not start with `test`/`testing` or SwiftFormat silently renames under `make format`.
- **Warning-as-error**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; per-target pbxproj overrides only (never CLI).
- **6th-skip sync gap**: the nudge interrupt (ReminderStore.swift:384-389) returns before `applySkipSet`, so `onSkipSetChanged`→watch `pushAll` doesn't fire for that bump — tests touching watch sync after a 6th skip must account for it.
- **Card sizing is row-driven**: card width = row `padding(.horizontal, 40)` + `frame(maxWidth: .infinity, center)` (ContentView.swift:429,:433); plate is net-zero geometry (CardPlateModifier.swift:23-30). No size-class/idiom branching exists anywhere — iPad layout changes would be new ground, but that is design's call to make, not this appendix's.