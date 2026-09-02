# Structure Outline

## Approach

Slim the local suite along three axes — consolidate one-assertion floods into fewer, named-assertion tests; delete only true cross-target duplicates; and make assertions name what they check — while shrinking the `eventKitSettleDelay` sleep seam and deduplicating/parallelizing `scripts/test.sh`. Proof is structural (counts of tests/assertions/launches/sleeps/xcodebuild invocations) plus a targeted wall-clock before/after on a pinned simulator; the full gate runs once, at the end.

Layers build bottom-up. Every stage ships its tests green before the next starts, and each completed stage (code + tests) is independently landable.

---

## Stage 1: Measurement substrate (structural proxy counter)

Delivers the counting tool that every later stage uses to prove "slimmer." Captures the **before** numbers and the **before** timing, so no later change can silently inflate the suite again.

**Files**: `scripts/count_tests.sh` (new)

**Key changes**:
- Counts, printed as a one-line report per metric:
  - `@Test` functions per target (`SingleThreadTests`, `SingleThreadWatchTests`, both UI targets)
  - `#expect` / `try #require` / `Issue.record` occurrences, and assertion mean (`#expect` count ÷ `@Test` count)
  - app-launch call sites (`.launch()` / `launchApp(`) in UI targets
  - real-time waits: `Task.sleep(nanoseconds:)`, `eventKitSettleDelay`, `usleep`, `waitForExistence`
  - `xcodebuild` invocations in `scripts/test.sh`
- Emits a machine-readable `before.json` snapshot to `.pi/qrspi/<branch>/`.

**Tests**: the counter is its own first test — its `before` output must reproduce the hand-counted baselines in `research.md` (552 unit `@Test`, 961 `#expect`, mean 1.82, 65 launches, 5 settle-sleep sites, 9 xcodebuild). A mismatch means the counter, not the suite, is wrong.

**Verify**:
```
bash scripts/count_tests.sh   # matches research.md baselines exactly
xcodebuild -only-testing:SingleThreadTests -destination <pinned SIM>   # capture before wall time
```

---

## Stage 2: Deterministic settle seam (`SingleThreadCore`)

Replaces the 200 ms production `eventKitSettleDelay` real sleep with an injectable settle hook, so the two `.serialized` store suites stop paying 400 ms forced sleeps per test. This is the production foundation the store-suite tests build on, and the riskiest single change — isolated here so any flake is diagnosed before consolidation touches those suites.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`

**Key changes**:
- Remove `private static let eventKitSettleDelay: UInt64 = 200_000_000` (`:438`); the 5 sleep sites (`:200,:231,:256,:289,:305`) become `await settle()`.
- New injectable seam on `ReminderStore.init` (shape — plan finalizes the exact type):
  ```swift
  typealias Settle = @Sendable () async -> Void
  init(..., settle: Settle = { try? await Task.sleep(nanoseconds: 200_000_000) })
  ```
  Production call sites keep the default; tests pass `settle: {}` (or a zero-delay clock) for instant determinism.

**Tests**:
- `EventKitStoringTests` / `ReminderStoreTests` — save/complete/delete/skip still reload deterministically when `settle` is a no-op **and** when it's the default; proves the seam, not blind deletion, removed the wait.
- Delete the 400 ms `Task.sleep` calls at `ReminderStoreTests.swift:334,352,372` and `ReminderStoreGateTests.swift:116` (replaced by `settle: {}`).

**Verify**:
```
xcodebuild -only-testing:SingleThreadTests -destination <pinned SIM>   # green, no flake
bash scripts/count_tests.sh                                            # settle-sleep sites ↓, unit sleep count → 0
```

---

## Stage 3: Unit-test consolidation & dedupe (iOS + watch)

Collapses the 60.5% single-assertion tests into the fewest tests per file, following the in-repo `LocalizationTests` (4 tests / 33 assertions) and `EventKitStoringTests` (mean 3.5) template. Deletes the zero-assertion test and only the true cross-target duplicates. **Hard acceptance criterion: every merged `#expect` carries a distinct message** (or `sourceLocation:` case label) so a failure still names the exact input/field.

**Files** (representative; the full list is the 13 × 100%-single-assertion files + the busy files):
- `SingleThreadTests/AppearanceModeTests.swift`, `ReminderSkipTests.swift`, `ReminderDisplayTests.swift`, `CodeSpanFormatterTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `ReminderStoreTests.swift`, `CompletionGlowTests.swift`
- `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`, `WatchSyncPipelineTests.swift`

**Key changes** (signatures, not bodies):
```swift
// AppearanceModeTests.swift: 14 tests → 3 (one per facet), parameterized
@Test(arguments: [
    (AppearanceMode.system, NSWindowStyle.unspecified),
    (AppearanceMode.light, .light),
    (AppearanceMode.dark, .dark),
])
func windowOverrideStyleMaps(_ pair: (AppearanceMode, NSWindowStyle)) {
    #expect(pair.0.windowOverrideStyle == pair.1, "\(pair.0) should map to \(pair.1)")
}

// ReminderNotesFormatterTests (in ReminderSkipTests.swift): 15 → 2–3
@Test(arguments: [nil, "", "   ", "\n\n", "t", "t "])
func formatReturnsNilForBlankInput(_ input: String?) {
    #expect(ReminderNotesFormatter.format(input) == nil, "nil for input \(input ?? "nil")")
}
```
- Delete `addReminderWithInMemoryStoreDoesNotCrash` (`ReminderStoreTests.swift:237-246`) — zero assertions.
- Collapse watch `WatchSyncPipelineTests` 5 structurally identical relaunch tests (`:149,:257,:272,:331,:389`) into one parameterized test.
- Cross-target dedupe: iOS glow `SingleThreadUITestsFlows.swift:506/:535` ≈ watch glow `:166/:185` — keep the richer, delete the other. (Decided here; the actual deletion lands in Stage 4.)

**Tests**: the consolidated suites themselves are the tests; they must stay green with strictly fewer `@Test` and strictly more named assertions per test.

**Verify**:
```
xcodebuild -only-testing:SingleThreadTests -destination <pinned SIM>
xcodebuild -only-testing:SingleThreadWatchTests -destination <watch SIM>
bash scripts/count_tests.sh   # @Test count ↓, assertion mean ↑, zero-assertion tests = 0
```

---

## Stage 4: UI-test scaffolding dedup & launch reduction

Unifies the four re-implemented `launchApp(seedJSON:)` helpers and three `flipToggle` copies behind one base class, and restructures the five persistence-relaunch tests to cut cold launches. The `--seed` (deterministic write flows) vs `--ui-testing` (persistence-across-relaunch) distinction is load-bearing and must not collapse.

**Files**:
- `SingleThreadUITests/SingleThreadUITestCase.swift` (new base class)
- `SingleThreadUITests/SingleThreadUITestsFlows.swift`, `NotificationsUITests.swift`, `NotificationSchedulingUITests.swift`, `NotificationsSettingsUITests.swift`
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`

**Key changes**:
```swift
// SingleThreadUITestCase.swift — new shared base
class SingleThreadUITestCase: XCTestCase {
    @MainActor func launchApp(arguments: [String]) -> XCUIApplication   // unifies --seed / --ui-testing
    @MainActor func flipToggle(_ toggle: XCUIElement, target: String) -> Bool
    @MainActor func assertTogglePersists(toggleID: String, target: String)  // 5 relaunch tests → 1 helper
}
```
- Relaunch tests (`:272,:308,:422,:478,:573`) keep their two-launch behavior but share the helper; launch count target: iOS < 50 (from 50), watch ≤ 15.

**Tests**: iOS + watch UI suites stay green with fewer launches and no regressed persistence assertions.

**Verify**:
```
xcodebuild -only-testing:SingleThreadUITests -destination <pinned SIM>
xcodebuild -only-testing:SingleThreadWatchUITests -destination <watch SIM>
bash scripts/count_tests.sh   # launch call sites ↓, iOS < 50
```

---

## Stage 5: Runner restructuring (`scripts/test.sh`)

Narrows the runner: pin the simulator destination, add the CI-proven parallelism/allowance flags, and drop the duplicate macOS unit *test* run (keeping the macOS *build* as a compile guard). Result must stay CI-identical in pass/fail semantics.

**Files**: `scripts/test.sh`

**Key changes**:
- Pin `SIM` from name-only to `,OS=<ver>` / `,id=<UDID>` (AGENTS.md destination-pinning rule).
- Add `-parallel-testing-enabled YES` and `-maximum-test-execution-time-allowance 900` to the unit `test-without-building` phase; pre-boot the sim (`xcrun simctl bootstatus … -b`).
- Delete the macOS unit `test` invocation (`:248-254`); keep the macOS `build` (`:239-245`, `CODE_SIGNING_ALLOWED=NO`) so `#if os(macOS)` paths still compile.
- No change to `ci.yml`, Periphery, SwiftFormat, or SwiftLint.

**Tests**: the full gate is the test; an explicit diff-review against `ci.yml` proves the flags and destination match what CI already proves safe.

**Verify**:
```
bash scripts/test.sh                  # full gate green (the one full run, at the end)
git diff scripts/test.sh | <review against ci.yml:48-52,129-132>
bash scripts/count_tests.sh           # xcodebuild invocations ↓ (9 → 8)
```

---

## Stage 6: Verification gate (targeted before/after + full gate)

Not new code — re-runs the counter and the pinned-sim timing to prove the end state, then runs the full gate once.

**Files**: none (consumes `before.json` + `count_tests.sh` output)

**Key changes**: none.

**Tests**: the acceptance assertions in `design.md` "Desired End State" — test count down, launch count down (iOS < 50), sleep count down (settle sleeps eliminated), invocation count down, wall-clock reduction on the pinned sim.

**Verify**:
```
bash scripts/count_tests.sh                            # after: all four counts down vs before.json
xcodebuild -only-testing:SingleThreadTests -destination <pinned SIM>   # wall time < before
bash scripts/test.sh                                   # the single full gate, green
```

---

## Testing Checkpoints

- **After Stage 1** — `count_tests.sh` reproduces `research.md` baselines (552/961/65/9/5); `before.json` written.
- **After Stage 2** — `SingleThreadTests` green with `settle: {}` and default; zero settle-sleep sites in tests; no flake in `EventKitStoringTests`.
- **After Stage 3** — iOS + watch unit suites green; `@Test` down, assertion mean up, zero-assertion tests = 0; every merged `#expect` has a message.
- **After Stage 4** — iOS + watch UI green; iOS launches < 50; no lost persistence assertion.
- **After Stage 5** — full `test.sh` green; `xcodebuild` invocations down to 8; diff-review vs `ci.yml` clean.
- **After Stage 6** — all four counts down vs `before.json`; pinned-sim wall time reduced; final full gate green.

## Cross-cutting notes (can't be built purely horizontally)

- **Named-assertion acceptance (Stage 3)** is a cross-stage invariant, not a layer. Stub it early: `count_tests.sh` also flags merged `#expect` calls lacking a message, so the constraint is enforced from Stage 1 onward.
- **Runner ↔ CI equivalence (Stage 5)** is only fully provable at Stage 6's full gate. Stub it at Stage 5 with the `ci.yml` diff-review and reuse of CI's exact flags, rather than inventing new concurrency.
- **Persistence-relaunch behavior (Stage 4)** is inherently top-layer — "persists across a real relaunch" can't be unit-tested. The behavior is preserved and only its launch cost is restructured; the `--ui-testing` (not `--seed`) choice stays because seeding resets the key under test.
- **Settle-delay correctness (Stage 2)** is a production change whose full no-flake guarantee only shows at the store-suite level; that's why it is its own bottom stage with both no-op and default-path tests before any consolidation touches those suites.
