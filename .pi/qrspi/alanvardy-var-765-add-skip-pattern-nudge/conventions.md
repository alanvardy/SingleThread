# Conventions — Shared Factual Appendix

Companion to `research.md`. Dense, `file:line`-anchored so Structure/Plan need
not re-open the source tree. All paths relative to repo root.

## Canonical commands

From `Makefile`:
- `make build` — `Makefile:17`
- `make test` — `./scripts/test.sh --unit-only` — `Makefile:75-76`
- `make ui-test` — `./scripts/test.sh --ui-only` — `Makefile:78-79`
- `make watch-ui-test` — scheme `SingleThreadWatch`, `-only-testing:SingleThreadWatchUITests` — `Makefile:84`
- `make watch-test` — `-only-testing:SingleThreadWatchTests` — `Makefile:92`
- `make coverage` / `coverage-ui` / `coverage-all` — `Makefile:37,50,63`
- `make lint` — `Makefile:106`
- `make format` — `Makefile:110` (SwiftFormat; excludes UI tests)
- `make periphery` — `periphery scan --strict` — `Makefile:114`
- `make mac-test` — `Makefile:26`
- Full CI gate: `./scripts/test.sh` (= `full` mode) — `Makefile:101`

`scripts/test.sh`:
- Default simulator `SIM="platform=iOS Simulator,name=iPhone 17"` — `scripts/test.sh:5`;
  watch `WATCH_TEST_SIM="...Apple Watch Series 11 (46mm)"` — `:11`; override with `SIM=` / `WATCH_TEST_SIM=`.
- `--unit-only` / `--ui-only` / `full` modes — `:89-96`.
- iOS destination pinning by UDID when multiple runtimes (this machine has 4) — `:44` sets
  `SIM="platform=iOS Simulator,id=$SIM_UDID"`. A bare `name=` hangs with multiple runtimes —
  pin `,id=` or `,OS=`.
- Full = unit (`-only-testing:SingleThreadTests`, `:237`), iOS UI (`:245`), watch UI
  (`:254`), watch unit (`:255`), macOS unit (`:292,307,315`).
- Destination drift guard + `lib_TestingInterop.dylib` embedded into the watch UI-test runner
  locally — `:174-185`.

CI: `.github/workflows/ci.yml:16-18` splits iOS UI into 3 disjoint `-only-testing:` groups;
watch build/UI/unit at `:411-438`.

## Test-suite inventory

7 targets — `SingleThread.xcodeproj/project.pbxproj:238-406`:
`SingleThread` (iOS app), `SingleThreadTests` (unit bundle), `SingleThreadUITests`
(UI bundle), `SingleThreadWatch` (watch app), `SingleThreadWidget` (app-extension),
`SingleThreadWatchUITests` (watch UI bundle), `SingleThreadWatchTests` (watch unit bundle).

| Suite | Covers | Platform gating |
|---|---|---|
| `SingleThreadTests/ReminderStoreTests.swift` | skip no-ops/notifies, refetch-drops-completed, refetch-keeps-skipped, generation-gated discard, `allSkipped`, complete/delete | injected `InMemoryEventStore` + `noopSettle` (:12) + `withCheckedContinuation` (:60-75) |
| `--/ReminderStoreGateTests.swift` | `canMutate` gating (freemium cap 100, entitled) | seeded `CompletionCounterStore` writes 100 (:137), `EntitlementStore(testingWithEntitled:)` |
| `--/ReminderSkipTests.swift` | pure `resolve`/`skipping` logic, priority, sort | `@Test(arguments:)` tables (:12-96); `EKReminder(eventStore:)` never saved (:117) |
| `--/SkippedReminderSyncServiceTests.swift` | push/receive skip context, relays, other keys | `FakeSession: SkipSyncSession` (:12-34), no EventKit |
| `--/EntitlementSyncTests.swift` | entitled/completion-count in payload | reuses `FakeSession` |
| `--/EventKitStoringTests.swift` | store I/O incl. delete-while-skipped prunes skip id | `FakeEventStore: EventKitStoring` (:8-135), `testStore` helper (:495) |
| `--/PendingCompletionStoreTests.swift`, `PendingCompletionLogicTests.swift`, `CompletionCounterStoreTests.swift`, `ExcludedListStoreTests.swift`, `UndoStoreTests.swift` | companion stores; isolation by UUID key | injected `now` clock + injected `UserDefaults` suite |
| `--/AppGroupTests.swift` | suite name, round-trip | — |
| `--/UITestingSeedTests.swift` | seed parse/defaults/verbatim-250 completion-count pin (:64), key clearing | — |
| `--/LocalizationTests.swift` | catalog parses, 6 langs, `%lld` plurals, InfoPlist keys | — |
| `--/ReminderIntentsTests.swift` | `SkipReminderIntent` instantiation/title/non-discoverability (:22-29) | — |
| `SingleThreadWatchTests/WatchSyncPipelineTests.swift` | watch-side key omission + receive | `WatchFakeSession` (:8-29) |
| `--/ReminderStoreWatchTests.swift` | watch pending-completion insert/reload-hide | `sharedWatchEventStore` + `watchReminder` fixture |
| `--/WatchAppViewModelTests.swift` | glow UI-test seam | — |
| `SingleThreadUITests/SingleThreadUITests.swift` | a11y audit; `testAccessibilityAudit` (:54-65) | `["--ui-testing","--reset-swipe-preference"]`; CI `[.sufficientElementDescription,.trait]`, local adds `[.dynamicType,.hitRegion]` |
| `SingleThreadUITests/SingleThreadUITestsFlows.swift` | skip advance/all-done/cross-device-completion (:72,108,130) | `launchSeeded` seed JSON |
| `SingleThreadUITests/ActionButtonsUITests.swift` | action-buttons render/skip advance + audit (:27,63-67) | `--ui-testing` |
| `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` | a11y audit (:39) | `[.dynamicType,.hitRegion,.sufficientElementDescription,.trait]` |
| `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` | skip all-done (:76), priority (:31), excluded/live-excluded (:47,61), gated (:113) | `--ui-testing`, `--ui-testing-*` flags |

## Build/verify gotchas

- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied`:
  prune stale `~/Library/Developer/XCTestDevices`, `xcrun simctl shutdown all`, kill orphaned
  `xcodebuild`/`xctest` (AGENTS.md).
- **Destination pinning**: bare `name=` hangs with multiple runtimes — pin `,id=<UDID>` or `,OS=<ver>`
  (`scripts/test.sh:44`). Check devices: `xcrun simctl list devices available`.
- **Swift Testing (not XCTest)** for unit tests; `import Testing`, `@Test`
  (AGENTS.md).
- **Unit-test names must NOT start with `test`/`testing`** — SwiftFormat strips the prefix
  and silently renames the function (`make format` phantom diffs). Follow `isEntitledFallsByDefault`.
  UI-test (XCTest) names keep `test…` (SwiftFormat-excluded).
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`** project-wide (Debug+Release); `swiftlint lint --strict`
  = every warning is an error. Scope per-target overrides in pbxproj, never CLI flags.
- **Persisted values shared with the watch must round-trip `AppGroup.defaults` (the
  `UserDefaults(suiteName:)` suite), never `UserDefaults.standard`** — on simulator the suite
  always exists, so they diverge silently. Includes `--ui-testing`/`--seed` seams.
- **`--seed` wipes persisted state** (`UITestingSeed.resetPersistedState` clears 23-24 keys from
  both suites); `--ui-testing` does **not** reset — use `--ui-testing` for persistence-across-relaunch
  tests.
- **Force-unwrapping banned outside tests**; relaxed in `SingleThreadTests/.swiftlint.yml`.
- **Variable names ≥ 3 chars** (exceptions: `id`,`e`,`d`,`rt`,`to`,`gvm`) per `identifier_name`.
- **Run the FULL `./scripts/test.sh` gate ONCE, by the parent, after phases commit** — never in
  phase/subagent workers (multi-hour; exceeds run caps).
- **Local a11y audit runs extra strictness categories** (`.hitRegion`, `.dynamicType`) beyond CI;
  a local hit-region failure can be local-only.
- **Caption-sized SwiftUI buttons need `.padding` on the label** — `.frame(minHeight:44)` does not
  expand the accessibility label frame.
- **Gate staging**: phase subagents verify with a build + targeted `-only-testing:` suites only.

## Launch-arg seams (summary cross-ref)

- iOS `--seed '<json>'` → `AppViewModel.makeStore` (`SingleThread/AppViewModel.swift:234`),
  schema `UITestingSeed.swift:31`; deterministic multi-reminder write flows.
- iOS `--ui-testing` / `--no-reminders` → `AppViewModel.swift:245`; one `"Buy groceries"` reminder.
- iOS `--reset-swipe-preference` / `--reset-glow-preference` → `AppViewModel.swift:246-251`.
- watch `--ui-testing`, `--ui-testing-priority`, `--ui-testing-excluded-list`,
  `--ui-testing-live-excluded`, `--ui-testing-gated`, `--ui-testing-glow` →
  `WatchAppViewModel.swift:14-53,94-143`.