# Conventions — SingleThread repo

Shared factual appendix for Design/Structure/Plan. Dense references; no source re-reading needed.

## Canonical commands

From `Makefile:1-14` (variables) and targets:

- `make build` — iOS app `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug … build-for-testing` (`Makefile:22-23`). `make watch-build` :25-27, `make mac-build` :29-31.
- `make test` → `./scripts/test.sh --unit-only` (:96-97); `make ui-test` → `./scripts/test.sh --ui-only` (:99-100); `make check` → full `./scripts/test.sh` (:130-131).
- `make watch-test` / `make watch-ui-test` — `xcodebuild … -only-testing:SingleThreadWatchTests` (:109-116) / `SingleThreadWatchUITests` (:102-107).
- `make mac-test` — `-destination 'platform=macOS' … -only-testing:SingleThreadTests CODE_SIGNING_ALLOWED=NO` (:33-36). Known local-only failures here (annotate, don't debug): `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary.
- `make lint` — `swiftformat --lint <all dirs>` + `swiftlint lint --strict` (:135-138); `make format` — `swiftformat` + `swiftlint --fix` (:141-143). SwiftLint `--strict` in CI ⇒ every warning is an error (`.swiftlint.yml` auto-discovered from repo root).
- `make periphery` — `periphery scan --strict` (:146-147); stale build index after branch switches — clean `DerivedData/` first.
- `make coverage` / `coverage-ui` / `coverage-all` (:41-91) — `xcrun xccov view`.
- `make simverify` — `./scripts/simverify.sh` (:101-102).

### Destination pinning (critical)

- Defaults: `SIM ?= platform=iOS Simulator,name=iPhone 17` (`Makefile:1`); `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (:7-9); `WATCH_SIM` generic watch (:2); `MAC_SIM = platform=macOS` (:10). `export SIM` (:14).
- **A bare `name=` destination hangs when multiple runtimes exist** — `scripts/test.sh:23-24` documents this; pin with `,OS=<ver>` or `,id=<UDID>`. `scripts/test.sh:41-46` resolves and preboots the iPhone sim UDID automatically; `SIM=` override accepted (`Makefile:1`).
- CI matrix: iPhone 17 and iPad (A16) parallel jobs (`.github/workflows/ci.yml:15-18`, `:83-86`), `platform=iOS Simulator,name=${{ matrix.device }}`; `-maximum-concurrent-test-simulator-destinations 1` (:59-68, :128-137); separate `mac-tests` job :141 (build :164-168, unit tests :175-184).
- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`. Watch UI tests use a standalone (unpaired) watch sim; pairing (`simctl pair`) is only a troubleshooting step.
- iOS default local sim is `iPhone 17`; `iPad (A16)` also supported (`scripts/test.sh:5`).

### Format/lint gotchas

- SwiftFormat enables `organizeDeclarations`, `blankLinesAroundMark`, `preferSwiftTesting`; disables `trailingCommas`, `trailingClosures`, `isEmpty` (`.swiftformat`).
- iOS UI tests excluded from swiftformat (`--exclude SingleThreadUITests` in CI; `Makefile:141` runs all dirs — see AGENTS.md). Watch UI tests are NOT excluded but keep `test…` names (XCTest).
- SwiftLint identifier_name ≥ 3 chars (exceptions: `id`, `e`, `d`, `rt`, `to`, `gvm`).
- **Unit-test (Swift Testing) names must not start with `test`/`testing`** — SwiftFormat strips those prefixes and silently renames (phantom diffs). XCTest UI-test names DO keep `test…`.
- Force-unwrapping banned outside tests; `SingleThreadTests/.swiftlint.yml` relaxes. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide — scope per-target overrides in pbxproj, never CLI flags.
- Swift 6 (`SWIFT_VERSION = 6.0`), `SWIFT_APPROACHABLE_CONCURRENCY = YES`. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS + watch app targets only (not Core/widget/tests — annotate `@MainActor` explicitly there).

## Test-suite inventory

Swift Testing (unit, names without `test` prefix) unless noted:

| Suite / file | Covers | Platform gating |
|---|---|---|
| `SingleThreadTests/ReminderStoreTests.swift` (~1088+ lines) | visibleReminders :17-125, sort :181, add :241, skipCurrent :265-329, completeCurrent :394-401, completeReminder :399, reload guards :406, hasHidden :428-509, skip-count section :563-799 (increment/receive-path/nudge 6th/5th/7th/reset-on-complete-delete-reschedule/reload-prune), undo decrements counter :802-923, hasHiddenFor :956-960, CompletedReturningEventStore seam :935-1053 | `@Suite(.serialized)` :20 |
| `SingleThreadTests/CompletionCounterStoreTests.swift` | counter default/incr/decr/clamp/persist/seed :6-78 | `@Suite(.serialized)` :6 |
| `SingleThreadTests/SkipCountStoreTests.swift` | round-trip, isolation, `shouldNudge` ≥6, `crossedThreshold` :6-49 | — |
| `SingleThreadTests/ReminderSkipTests.swift` | resolve/skipping, priority, rank, notes, sort :23-260 | — |
| `SingleThreadTests/AppGroupTests.swift` | suite name :8-11, defaults round-trip :13-19 | defer cleanup :16 |
| `SingleThreadTests/PendingCompletionStoreTests.swift` | pending store :5-47 | — |
| `SingleThreadTests/CompletionGlowTests.swift` | glow trigger/dismiss :14-98 | — |
| `SingleThreadTests/UITestingSeedTests.swift` | `--seed` parse, unclamped 250, malformed, store render, resetPersistedState :16-183 | `@Suite(.serialized)` :12 |
| `SingleThreadTests/EntitlementSyncTests.swift` | pushAll incl. completionCount :22-36, seeded 42 :59-91, applyDecodes :93-108 | — |
| `SingleThreadTests/SkippedReminderSyncServiceTests.swift` | FakeSession push/receive :11-120 | — |
| `SingleThreadTests/SingleThreadTests.swift` | `ReminderDateFilterTests` UTC window :155-230; timezone/`now` seam :242,246 | — |
| `SingleThreadTests/EventKitStoringTests.swift` | reload window predicate :465-500 | — |
| `SingleThreadWatchTests/ReminderStoreWatchTests.swift` | pending-completion insert/hide/noop/preserve, reschedule relay+gating :15-148 | `@Suite(.serialized)` :11; watch-only |
| `SingleThreadWatchTests/WatchSyncPipelineTests.swift` | pushAll keys :16-63, absent-key no-ops :69-125, survive-relaunch :132-143, showCompletionGlow receive :218-244, skipCounts/inverted omission :271-317, enableActionButtons :345-424 | serialized :383-388 |
| `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift` | state holder + view-model transition :84-268 | — |
| `SingleThreadWatchTests/TestFixtures.swift` | `sharedWatchEventStore`, `watchReminder`, `WatchFakeSession` :12-48 | — |
| `SingleThreadUITests/` (XCTest) | end-to-end iOS UI flows + a11y audit (`testAccessibilityAudit` / `performAccessibilityAudit`); SwiftFormat-excluded | XCTest names keep `test…` |
| `SingleThreadWatchUITests/` (XCTest) | watch UI + a11y | XCTest |

### Test seams (CRITICAL)

- **`InMemoryEventStore`** (`SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:7-11`) implements `EventKitStoring` in memory; `fetchReminders` filters `!isCompleted` :60-98; one process-wide `sharedStore = EKEventStore()` :151 backs every `makeReminder` (weak refs — deallocated store ⇒ SIGTRAP); `makeReminder` is `#if !os(watchOS)`.
- **`TestFixtures.swift`** — file-scope `sharedTestEventStore` :15-17; `makeReminder(title:priority:dateComponents:)` :20-30; `inListReminder` :53-63; `FakeSession` (records `lastContext`/`lastMessage`, `pushShouldThrow`) :74-104.
- **`--seed '<json>'` launch-arg** (`UITestingSeed.swift`) — standard for deterministic iOS UI write-flow tests; decoded via `fromLaunchArguments` :44-60; `resetPersistedState` :62-73 clears 24 keys from both `AppGroup.defaults` and `.standard`; wired in `AppViewModel.makeStore`/`seededStore` :198-215, :283-345 (writes `completionCount` :296, `skipCounts` :300, `enableActionButtons` :304, `--ui-testing-noop-settle` :319-324). Watch uses `--ui-testing` seams (`WatchAppViewModel.swift:100-160`). Glow seams: `--ui-testing-glow` 2.0 s / `--ui-testing-reduced-glow` 0.1 s (`AppViewModel.swift:168-176`).
- **UserDefaults isolation** — UUID-suffixed keys on shared suites, or throwaway `UserDefaults(suiteName: "<Test>-\(UUID())")!` suites; `defer removePersistentDomain` cleanup; `@Suite(.serialized)` for shared-store suites.
- **Async assertion** — rendezvous on store hooks (continuation resume) before asserting; `noopSettle`/`settle:` injection to skip the 200 ms production settle.
- **`UI` vs unit** — UI tests are the exception, not the default; unit tests must ship with every feature/bug.

## Persistence & sync conventions (watch-shared)

- **Every persisted value shared with the watch must round-trip through `AppGroup.defaults` (`UserDefaults(suiteName: "group.app.alanvardy.SingleThread")`)** — never `UserDefaults.standard` (on simulator the suite always exists; the two diverge silently). On watch/previews the suite is unavailable and falls back to `.standard` (`AppGroup.swift:12-17`). Includes `--ui-testing`/`--seed` seams.
- All Core stores default to `AppGroup.defaults`: `SkippedReminderStore` ("skippedReminderIdentifiers"), `SkipCountStore` ("skipCounts"), `ExcludedListStore`, `SortOptionStore`, `CompletionCounterStore` ("completionCount"), `BoolPreferenceStore`, `PendingCompletionStore`.
- Sync payload keys live in `PayloadKey` enum (`SkippedReminderSyncService.swift:340-360`); `pushAll` (:200-243) always sends `skippedReminderIdentifiers`/`skipCounts`/`excludedListTitles`/`showUndatedReminders`/`sortOption`/`completionCount`/`enableActionButtons`, conditionally the `show*`+`isEntitled`; watch pushAll omits phone-only keys. Interactive relays (complete/delete/reschedule) use `sendMessage` (:245-281).
- **New persisted key checklist** (from research): store class defaulting to `AppGroup.defaults`; `PayloadKey` + `pushAll` (if phone→watch) + `apply`/`applyRemaining` hooks; watch `Show*State` holder + `wireStateReceiveHooks`; `seededStore` seed write + `UITestingSeed` fields + `resetPersistedState` key list; store tests + ReminderStore integration + sync pipeline + seed tests.
- `EntitlementStore.unlockProductID` is the single source of truth for the premium product id (never hardcode elsewhere; `Products.storekit` + scheme `StoreKitConfigurationFileReference` in sync). `canMutate` gates mutation: `isEntitled || completionCounter.count < freemiumCap(100)` (`ReminderStore.swift:176-177`).

## Build/verify gotchas

- `make periphery` after branch switch: clean `DerivedData/` first (stale index).
- Full gate = `./scripts/test.sh` (formats, lints, builds, Periphery, unit + UI tests; multi-hour). Run via the `run-gate` skill as one async gate subagent in a worktree — never `nohup … &` ad-hoc, never re-run by phase workers (targeted `-only-testing:` suites only during phases).
- After two local UI-stage contention failures, stop re-running — CI is authoritative.
- `hx` git editor panics without TTY — `git commit -m`, `git -c core.editor=true rebase --continue`. Merge PRs with `--rebase` only.
- Back up files to `.bak` before in-place destructive edits.
- macOS-only known failures: three `EntitlementStoreTests` (see mac-test above) — pre-existing, annotate.