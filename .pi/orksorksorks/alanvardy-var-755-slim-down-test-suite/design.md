# Design Discussion — Slim down test suite

## Current State

Three test targets plus a monolith local runner. All `file:line` refs relative to repo root; drawn from `research.md`.

- **Unit suite is assertion-poor but count-rich.** `SingleThreadTests` = 54 files / 516 `@Test`; watch = 5 files / 36. Combined 552 tests, **60.5% single-assertion** (334), mean 1.82 assertions/test (`research.md` Q1). Fragmented exemplars: `ReminderSkipTests.swift` 46/53 one-assertion, `ReminderDisplayTests.swift` 21/25, `CodeSpanFormatterTests.swift` 13/16, `AppearanceModeTests.swift` 13/14, plus 13 files at 100% single-assertion. One **zero-assertion** test: `addReminderWithInMemoryStoreDoesNotCrash` (`ReminderStoreTests.swift:237-246`).
- **Wall time is not driven by test count — it's sleeps and serialization.** The 200 ms production `eventKitSettleDelay` (`ReminderStore.swift:438`, slept at `:200,:231,:256,:289,:305`) forces 400 ms test sleeps in the two biggest suites (`ReminderStoreTests.swift:334,352,372`; `ReminderStoreGateTests.swift:116`), both `.serialized` (59 and ~123 tests sequenced). Glow tests poll ≤2 s (`CompletionGlowTests.swift:44-51`). Remaining ~450 unit tests are pure logic.
- **UI wall time is launch count.** iOS 44 tests / **50 launches**; watch 15/15; combined **65 launches**. Five iOS tests relaunch purely to test persistence (`SingleThreadUITestsFlows.swift:272,308,422,478,573`), using `--ui-testing` (not `--seed`) because the seed reset would wipe the key under test (`:290-294,419-424,475-480,570-575,591-593`). Each UI run leaves a ~3 GB XCTest runtime (`test.sh:24-27`).
- **Coverage is layered, 4–5 deep, with narrow uniqueness per layer.** E.g. glow = store (`ShowCompletionGlowPreferenceTests`) → view-model (`CompletionGlowViewModelTests.swift:64-110`) → binding (`SettingsViewTests.swift:13`) → iOS UI (`:478,506,535`) → watch unit + watch UI (`:166,185`). Each layer asserts something the others don't, but iOS `:506/:535` ≈ watch `:166/:185` are near-identical cross-target duplicates (`research.md` Q2).
- **Local runner is a sequential monolith.** 13 phases in one `set -euo pipefail` bash process, 9 xcodebuild invocations, shared `DerivedData`, no clean (`test.sh:165-258`). **The unit suite runs twice** — iOS (`:199-204`) and macOS (`:248-254`, the only combined build+test phase). No `-parallel-testing-enabled`, no pre-boot, no `-resultBundlePath` (`research.md` Q5).
- **No timing data exists anywhere in-repo** — no baseline, no per-test tooling, no xcresult in the repo (`research.md` Q6).

## Desired End State

Local `./scripts/test.sh` wall time measurably reduced, with diagnosis *improved* (not degraded) and CI-equivalence preserved.

Verify by structural proxies plus a targeted before/after:

1. **Test count down** — merged/parameterized families and removed duplicates reduce the 552 unit + 59 UI test counts.
2. **Launch count down** — iOS < 50, watch ≤ 15 (the five persistence relaunch tests restructured to avoid extra cold launches where safe).
3. **Sleep count down** — `eventKitSettleDelay` shrink/removal eliminates the 400 ms forced sleeps in the two serialized store suites; glow poll loops bounded.
4. **Runner invocation count down** — the macOS duplicate unit run deduplicated/parallelized within `scripts/test.sh`, watch build amortized.
5. **Targeted before/after** — run `-only-testing:SingleThreadTests` (and `SingleThreadWatchTests`) on the same pinned sim before and after; assert a wall-clock reduction. Full `./scripts/test.sh` runs once at the end as the gate, not as a baseline.
6. **Assertion messages** — every merged/consolidated test keeps a distinct `#expect(_, "…")` message so a failure still names the specific case; single-failure diagnosis survives aggressive consolidation.

## Patterns to Follow

Good patterns the implementation must match:

- **Swift Testing only in unit suites** (`#expect`, `try #require`, `Issue.record`); XCTest only in UI targets — `research.md` Q1. Never mix.
- **Consolidation exemplars already in-repo**: `LocalizationTests.swift` (4 tests / 33 assertions, mean 8.25), `EventKitStoringTests.swift` (mean 3.5, e.g. `addReminderSavesAndReturnsTrue` = 8 at `:206`), `ReminderDictationParserTests.swift` (mean 3.4, two 6-assertion tests at `:60`), `BackgroundImageStoreTests.swift` (mean 2.8, 18/19 have 2+), watch `WatchSyncPipelineTests.receiveAppliesEveryPresentKey` = 10 (`:61-111`). Use these as the template for table-style merging.
- **`@Suite(.serialized)` for anything touching real state**: shared `EKEventStore`, real UserDefaults keys, real StoreKit `SKTestSession`, timers, file I/O (`research.md` Q4). Keep this discipline — consolidation must not break isolation.
- **`--seed` for deterministic write-flow UI tests; `--ui-testing` for persistence-across-relaunch tests** — this distinction is load-bearing and must not be collapsed (`research.md` Q3/Q4).
- **App Group `AppGroup.defaults` for every watch-shared value** (`AppGroup.swift:8,13-14`); the `.standard` fallback means the two stores are the *same* store on watch/simulator — reset clears both (`UITestingSeed.swift:48-55`).

Anti-patterns the research found — do NOT copy:

- 100% one-assertion files (13 of them) and the zero-assertion `addReminderWithInMemoryStoreDoesNotCrash`.
- Per-class re-implementations of `launchApp(seedJSON:)` (4 iOS classes) and `flipToggle` (3×) with no shared base class (`research.md` Q3) — the duplication that makes UI changes expensive.
- The 200 ms settle sleep + 400 ms forced test sleeps (production constant forcing test cost).
- The macOS duplicate unit run (`test.sh:248-254`) — same tests, second toolchain.

## Design Decisions

1. **Scope = test files + runtime seams + runner (Q1:C).** Apply the three named techniques, *and* shrink/remove `eventKitSettleDelay` + its forced sleeps, *and* restructure `scripts/test.sh`. Runner changes are narrowly scoped: dedupe the macOS unit run and add `-parallel-testing-enabled` / pre-boot / `-maximum-test-execution-time-allowance` flags matching what CI already does (`ci.yml:48-52,129-132`). Any production-constant change (`ReminderStore.swift:438`) must be proven to keep tests deterministic — the sleep exists to let EventKit settles land (`research.md` Q4), so removal must come with a deterministic substitute (seam or injected clock), not a blind delete.

2. **Duplicate coverage: merge within each layer, delete only cross-target identical tests (Q2:C).** Keep every layer that asserts something distinct (store semantics vs view rendering vs freemium gate vs sync transport). Delete only true identicals — iOS glow `:506/:535` ≈ watch glow `:166/:185` — keeping the richer of the pair. No wholesale layer deletion.

3. **Assertion consolidation is aggressive (Q3:B).** Collapse per-file single-assertion floods into the fewest tests per file, following the `LocalizationTests`/`EventKitStoringTests` template. **Compensating requirement:** every merged `#expect` gets a distinct message (or Swift Testing `#expect(_:_:sourceLocation:)` case label) so a failure names the exact input/field. This is what preserves the task's "aid future diagnosis" goal under aggressive merging.

4. **Verification = structural proxies + targeted before/after (Q4:A).** No full multi-hour baseline. Count tests, launches, sleeps, and xcodebuild invocations before/after; time `-only-testing:SingleThreadTests` + `SingleThreadWatchTests` on a pinned sim. Full gate runs once, at the end.

5. **Watch suites in scope (Q5:A).** Same consolidation/dedupe applied to `SingleThreadWatchTests` (36) and `SingleThreadWatchUITests` (15 launches). The watch `build-for-testing` is the single heaviest invocation (`research.md` Q5), so fewer watch tests pays the most. Collapse the 5 structurally identical relaunch tests (`WatchSyncPipelineTests.swift:149,257,272,331,389`) into one parameterized test.

## What We're NOT Doing

- **Not touching CI.** `ci.yml` sharding, matrices, and timeouts stay as-is. Local-only wins, per the task ("focus is reducing local runtime").
- **Not migrating UI tests off XCTest** or converting any suite to/from Swift Testing.
- **Not rewriting the EventKit seam** (`InMemoryEventStore`, `EventKitStoring` protocol) beyond the settle-sleep change in decision 1. The `.serialized` architecture stays.
- **Not adding new coverage** — this is a slimming pass. If a merge reveals a genuinely untested behavior, record it as a follow-up ticket, don't add it here.
- **Not parallelizing `scripts/test.sh`** into background jobs beyond what the existing phase dependencies allow — the runner must remain CI-identical in *result*, so any concurrency added must be the same `xcodebuild` flags CI already proves safe.
- **Not removing** the `--seed` / `--ui-testing` / `--reset-*` seams or the 5 persistence-relaunch *behaviors* — only their launch cost.
- **Not changing Periphery, SwiftFormat, or SwiftLint** configs; `make format`/`make lint` stay green.

## Open Risks

- **Aggressive consolidation vs diagnosis (Q3:B).** Merging to fewest-tests-per-file concentrates failure surface; mitigated only if every `#expect` carries a distinct message. Plan phase must treat "named assertions" as a hard acceptance criterion, not a nicety.
- **`eventKitSettleDelay` removal correctness.** The 200 ms sleep (`ReminderStore.swift:438`) exists because EventKit save/remove delivery is async; a blind removal can reintroduce flake in `EventKitStoringTests`. Requires a deterministic substitute (clock injection or seam) — the riskiest single change in scope.
- **`scripts/test.sh` equivalence with CI.** Any runner change must produce identical pass/fail semantics; a locally-optimized gate that diverges from CI would hide real failures. Runner edits need a diff-review pass against `ci.yml`.
- **Persistence-relaunch UI tests are load-bearing.** The 5 relaunch tests use `--ui-testing` *precisely* to avoid the seed reset (`research.md` Q3). Restructuring them risks either losing the "persists across relaunch" assertion or reintroducing the reset. Collapse carefully or leave alone.
- **No measured baseline.** Without prior timing data (Q6), "faster" is provable only structurally + the targeted before/after; the full-gate number may be noisy (cold sim, ~3 GB runtimes).
- **Line-number drift.** A few research `file:line` refs in rarely-touched spots (`ReminderStoreGateTests.swift:116`, watch relaunch tests) carry small off-by-a-few risk; implementation must re-locate before editing.
