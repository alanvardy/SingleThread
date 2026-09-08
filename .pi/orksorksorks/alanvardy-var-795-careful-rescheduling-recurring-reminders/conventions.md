# Conventions — SingleThread Reschedule/Recurrence Research

Shared factual appendix: canonical commands, test-suite inventory, build/verify gotchas. Line numbers verified against source.

## Canonical commands (Makefile, scripts/, CI)

From `Makefile` (paths relative to repo root):
- **Build**: `make build` (= `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build-for-testing`); `make watch-build` (generic watch sim); `make mac-build` (+ `CODE_SIGNING_ALLOWED=NO`).
- **Test**: `make test` = `./scripts/test.sh --unit-only`; `make ui-test` = `./scripts/test.sh --ui-only`; `make check` = full `./scripts/test.sh` (CI-identical gate — formats, lints, builds, Periphery, unit + UI tests). `make watch-test` / `make watch-ui-test` = targeted `xcodebuild … -only-testing:SingleThreadWatchTests|SingleThreadWatchUITests` on `WATCH_TEST_SIM`.
- **macOS**: `make mac-test` (unit only, macOS destination), `make mac-run`, `make mac-distribute` (`bash scripts/distribute-macos.sh`).
- **Lint/format**: `make lint` = `swiftformat --lint <all dirs>` + `swiftlint lint --strict` (every warning is an error); `make format` = `swiftformat <all dirs>` + `swiftlint --fix`. CI list matches `Makefile`'s `lint` target.
- **Periphery**: `make periphery` (`periphery scan --strict -- -destination "$SIM"`) — clean `DerivedData/` after branch switches (stale index).
- **Coverage**: `make coverage` (unit), `coverage-ui`, `coverage-all` (unit + UI; `xccov view`).
- `SIM ?= platform=iOS Simulator,name=iPhone 17`; `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`; `MAC_SIM := platform=macOS`. Override with `SIM=platform=iOS Simulator,id=<UDID>` or `,OS=<ver>`.

`scripts/test.sh` (full gate, identical to CI): default `SIM`/`WATCH_TEST_SIM` envs (lines 5-12); resolves a bare name to a UDID from `xcrun simctl list devices available` to avoid ambiguous-name hangs (lines 42-44); runs iOS unit (`-only-testing:SingleThreadTests`), iOS UI (`-only-testing:SingleThreadUITests`), watch unit + watch UI (`-only-testing:SingleThreadWatchUITests -only-testing:SingleThreadWatchTests`) on the concrete watch sim; supports `--unit-only` / `--ui-only`.

CI (`.github/workflows/ci.yml`): 6 jobs on `macos-26` —
- `unit-tests` (line 21) and the three UI jobs (`ui-tests-flows` :89, `ui-tests-launch-appearance` :150, `ui-tests-audits` :209) matrix over `device: ["iPhone 17", "iPad (A16)"]`; each resolves/boots the sim UDID first.
- Simulator-clone contention: unit + UI builds pass `-parallel-testing-enabled NO` and `-maximum-concurrent-test-simulator-destinations 1` (e.g. :76-77), `-maximum-test-execution-time-allowance 900`.
- `ui-tests-flows` splits the iOS UI classes into 3 disjoint `-only-testing` groups A/B/C (:16-18).
- `mac-tests` (:270), plus a watch job (:323) and `watch-ui-tests` (:369) — the latter **creates an unpaired standalone watch simulator** (`simctl create` with a deterministic name + `WATCH_UDID`, :391-403) and runs against `platform=watchOS Simulator,id=$WATCH_UDID`; pairing is only a troubleshooting step locally.

## Test-suite inventory (reschedule/recurrence-relevant)

All unit tests use **Swift Testing** (`import Testing`, `@Test`); UI tests use XCTest.

| File | Covers | Platform / gating |
|---|---|---|
| `SingleThreadTests/RescheduleSheetTests.swift` | picker components/mask from `hasDueTime` (:15,23,31,38,43) | iOS/macOS unit |
| `SingleThreadTests/EventKitStoringTests.swift` (suite `ReminderStoreWriteTests` :149) | add w/ recurrence (:206, asserts `recurrenceRules?.count == 1` :223), complete (`===` :152), delete, reschedule (:274,298,313) via `FakeEventStore` (save = same ref :101-106; makeReminder :122-132) | iOS/macOS unit |
| `SingleThreadTests/ReminderStoreTests.swift` | `addReminderSucceedsAndKeepsExistingReminders` :222 (weekly rule), `rescheduleResetsSkipCount` :674, `makeReminderLeavesUnsetFieldsNil` :1043, `makeReminderSetsRecurrenceRule` :1053 | iOS/macOS unit |
| `SingleThreadTests/RescheduleSyncTests.swift` | watch→phone reschedule relay serialization (wire dict :12, omit-nil :35, receive fires hook :54, no-op :90) | **`#if os(iOS) || os(watchOS)`** (:1); file-system-synchronized group compiles it into both unit-test targets |
| `SingleThreadTests/ReminderDictationParserTests.swift` | 19 recurrence-parse tests :141-316; "rescheduled" only as title text (:141) | unit |
| `SingleThreadTests/ReminderRecurrenceFormatterTests.swift` | `format` nil/strings :10,16 | unit |
| `SingleThreadTests/ReminderDisplayTests.swift` | `recurrenceFlagsAndSummary` :146 (hasRecurrence/summary) | unit |
| `SingleThreadTests/ShowRecurrenceTests.swift` | card row follows preference + data :11 | unit |
| `SingleThreadWatchTests/ReminderStoreWatchTests.swift` | watchOS store branches: reschedule relay hook :111, canMutate gate :143 | watch unit |
| `SingleThreadWatchTests/WatchSyncPipelineTests.swift` | showRecurrence **preference** sync (not `EKRecurrenceRule`): :69,133,177-182,229,267 | watch unit |
| `SingleThreadWatchTests/WatchReminderViewRegressionTests.swift` | `rendersEveryReminderDisplayFieldWithoutCrashing` :34 (asserts `!display.hasRecurrence` :43) | watch unit |
| `SingleThreadUITests/SkipNudgeUITests.swift` | nudge sheet is **documented only** in a comment (:10) — no iOS UI reschedule test | iOS UI (XCTest) |
| `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` | `testActionMenuReschedulePresentsSheetWhenToggleSyncedOn` :159 (menu → sheet → `rescheduleConfirmButton`) | watch UI (XCTest) |

Remaining iOS unit files (Appearance, ActionMenuGate, SortOption, PendingCompletion, SkipCount, UndoStore, etc.) do not touch reschedule or `EKRecurrenceRule`. `ReminderDictationTests.swift` has no recurrence/reschedule coverage.

## Build/verify gotchas (surfaced by this research)

- **No test combines a repeating reminder with a reschedule**, and the deterministic seams cannot: `--seed '<json>'` (`UITestingSeed` `ReminderSeed` = title/notes/priority only, `UITestingSeed.swift:123-126`) and `--ui-testing` (`AppViewModel.swift:230-235`, `recurrenceRule: nil`) are recurrence-free by construction. A test wanting recurrence × reschedule must build the rule via `makeReminder(..., recurrenceRule:)`.
- **`InMemoryEventStore.save` appends without dedup** (`InMemoryEventStore.swift:87-89`): rescheduling an already-seeded reminder duplicates it in `allReminders`; fetches return it twice. `remove` (by `calendarItemIdentifier`, :91-93) is the only dedup mechanism.
- **Watch side effects not asserted**: watch reschedule emits only `.year/.month/.day` (time lost, `WatchReminderView.swift:299-301`); watchOS store branch does no local write/reload (`ReminderStore.swift:358-362`); relay is fire-and-forget (`replyHandler: nil`, `SkippedReminderSyncService.swift:287-289`).
- **Destination pinning**: a bare `name=iPhone 17` is ambiguous when multiple runtimes exist — pin `,OS=<ver>` or `,id=<UDID>`; `scripts/test.sh`/`Makefile` accept `SIM=`.
- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`. Watch UI tests need a standalone (unpaired) watch sim; pair only for runner-launch troubleshooting.
- **Debug builds only** (`DEBUG_INFORMATION_FORMAT = dwarf`); release with `dwarf-with-dsym`.
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat strips them (`make format` silently renames); UI-test (XCTest) names keep `test…` (UI tests SwiftFormat-excluded). Lint: identifiers ≥ 3 chars.
- **App Group defaults everywhere shared with the watch** (`AppGroup.defaults(suiteName:)`), never `UserDefaults.standard` — includes `--ui-testing`/`--seed` seams; incl. `enableActionButtons` flag (`AppGroup.defaults.bool(forKey: "enableActionButtons")`, `SkippedReminderSyncService.swift:209`).
- **`--ui-testing-noop-settle`** skips the 200 ms post-save settle (`AppViewModel.swift:204,236-251`); production default sleep is `ReminderStore.swift:39-41`.
- Gate staging: phase-level verification uses targeted `-only-testing:` suites only; the full `./scripts/test.sh` runs once by the parent (multi-hour); local UI-contention rules apply.