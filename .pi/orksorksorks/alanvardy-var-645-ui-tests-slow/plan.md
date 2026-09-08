# Implementation Plan — VAR-645: UI tests slow

## Overview

Shorten PR wall-clock by (a) collapsing XCTest's per-configuration launch
multiplier on the two iOS UI classes that still multiply (secondary lever), and
(b) splitting the single monolithic iOS `ui-tests` CI step into parallel
per-cost-tier jobs, each on its own runner with a pre-booted simulator and
DerivedData restore. Coverage is unchanged: the split groups' `-only-testing:`
selections are disjoint and their union equals today's full 5-class iOS UI set.

> **Critical identifier correction (supersedes `structure.md` snippets).**
> xcodebuild's `-only-testing:` value is a **test identifier** of the form
> `TestTarget/TestClass[/TestMethod]`, not a bare class name, and comma-separating
> classes inside one `-only-testing:` flag is **not reliably supported** — the
> documented safe form is **one repeated `-only-testing:` flag per class**.
> The XCTest bundle here is `SingleThreadUITests` (pbxproj `productName`), so
> class-level identifiers are the five below. `structure.md` shows items like
> `-only-testing:SingleThreadUITestsLaunchTests` (no target prefix) and comma-joined
> lists — those would silently run **zero** tests. Every `-only-testing:` below is
> written in the corrected, verified form. The union/disjointness topology of the
> structure is unchanged.

Reference test-id map (bundle = `SingleThreadUITests`):

| Group | Classes | `-only-testing` identifiers |
|---|---|---|
| A | LaunchTests + AppearanceLaunchTests | `SingleThreadUITests/SingleThreadUITestsLaunchTests`, `SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests` |
| B | Flows | `SingleThreadUITests/SingleThreadUITestsFlows` |
| C | UITests + ActionButtons | `SingleThreadUITests/SingleThreadUITests`, `SingleThreadUITests/ActionButtonsUITests` |

Union of A+B+C = the 5 iOS UI classes; all disjoint. Before hand-editing
`ci.yml`, the implementer **SHOULD** confirm these exact identifiers with
`xcodebuild … -enumerate-tests` (see Phase 2 verification) and adjust the
fragments below if any class identifier differs.

---

## Phase 1 — Collapse the per-configuration launch multiplier

Cheapest, lowest-risk change: stop `SingleThreadUITests` and
`ActionButtonsUITests` from re-launching a fresh cold simulator once per
target-app UI configuration. Independent of the split.

### Changes

#### 1. `SingleThreadUITests/SingleThreadUITests.swift`
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify

Add the same `runsForEachTargetApplicationUIConfiguration = false` override the
two launch classes already use, with the matching `swiftlint` guard. Insert it
between the class declaration and `setUpWithError`:

```swift
final class SingleThreadUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it.
    // Run once (not once per target app configuration): the audit launches one
    // deterministic app state; multiplying it by the configuration count adds
    // redundant cold launches on CI for no coverage.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
```

#### 2. `SingleThreadUITests/ActionButtonsUITests.swift`
**File**: `SingleThreadUITests/ActionButtonsUITests.swift`
**Action**: modify
Same override + guard, inserted after the class declaration:

```swift
final class ActionButtonsUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it.
    // Run once (not once per target app configuration): both methods render the
    // same `--ui-testing` UI; the per-config multiplier only adds redundant cold
    // launches on CI. The audit categories/CI-carve-out are otherwise untouched.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
```

#### 3. Untouched — watch launch invariant
**Action**: verify-only, no edit. `SingleThreadWatchUITests/SingleThreadWatchUITestsLaunchTests.swift` must **keep** `runsForEachTargetApplicationUIConfiguration = true`. Do not touch this file.

### Verification

#### Automated
- [x] `make format` passes and re-formats these two files only if formatting drifted.
- [x] `make lint` passes (`swiftlint lint --strict`) — the new overrides carry the `static_over_final_class` disable, and warnings are hard errors.
- [x] `make ui-test` (`./scripts/test.sh --ui-only`) passes — iOS UI suite still runs
      all methods for `SingleThreadUITests` (audit) + `ActionButtonsUITests` (both).
- [x] `./scripts/test.sh --unit-only` passes — unit suite intact (~284).

#### Manual
- [ ] Xcode project still opens clean; the two classes compile.
- [ ] Launch count drops: `SingleThreadUITests`/`ActionButtonsUITests` no longer
      spawn `XCTestDevices` runtimes once per UI configuration (observe either the
      xcodebuild/XCUIRun output or `~/Library/Developer/XCTestDevices` growth
      shrinking for these classes vs. a pre-change baseline run).
- [ ] `testAccessibilityAudit`, `testActionButtonsAccessibilityAudit`, and
      `testActionButtonsRenderAndSkipAdvancesCard` each still execute (they are
      exercised by `make ui-test`).

---

## Phase 2 — Split the monolith into two parallel iOS UI jobs

First slice of the primary lever: carve the launch/appearance tier (group A) out
of the monolithic `ui-tests` job so it runs **concurrently** with the (now
smaller B+C) job. No single source of truth yet — that lands in Phase 3.

### Changes

#### 1. `.github/workflows/ci.yml` — add `ui-tests-launch-appearance` (group A)
**File**: `.github/workflows/ci.yml`
**Action**: add

Add a second iOS UI job copied from `ui-tests`, with its own `strategy.matrix`
(`iPhone 17` / `iPad (A16)`), `Pre-boot simulator`, and identical
`actions/cache@v4` `derived-data-…` restore. Keep the Build step building the
**full** `SingleThreadUITests` target (so the shared DerivedData artifact is
identical across UI jobs and each job only pays its group's test-run cost). The
only functional difference from `ui-tests` is the job id/name and the UI-tests
step's `-only-testing:` (group A, repeated-flag form):

```yaml
  ui-tests-launch-appearance:
    runs-on: macos-26
    strategy:
      matrix:
        device: ["iPhone 17", "iPad (A16)"]
    env:
      SIM: platform=iOS Simulator,name=${{ matrix.device }}
      DERIVED_DATA: ${{ github.workspace }}/DerivedData
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        id: xcode
        with:
          xcode-version: '26.6'

      - name: Override development team
        run: echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV

      - uses: actions/cache@v4
        with:
          path: ${{ github.workspace }}/DerivedData
          key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadUITests/**', 'SingleThreadCore/**', 'SingleThreadWatch/**', 'SingleThreadWidget/**', 'SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-

      - name: Pre-boot simulator
        run: |
          SIM_UDID=$(xcrun simctl list devices available | grep -F "${{ matrix.device }} (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
          xcrun simctl boot "$SIM_UDID" || true
          xcrun simctl bootstatus "$SIM_UDID" -b

      - name: Build
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadUITests \
            -showBuildTimingSummary

      - name: UI tests (launch + appearance)
        timeout-minutes: 45
        run: |
          # Disable parallel test simulator clones (see the main ui-tests
          # comment); a single concurrent destination per job avoids the race.
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -derivedDataPath "$DERIVED_DATA" \
            -maximum-test-execution-time-allowance 900 \
            -parallel-testing-enabled NO \
            -maximum-concurrent-test-simulator-destinations 1 \
            test-without-building \
            -only-testing:SingleThreadUITests/SingleThreadUITestsLaunchTests \
            -only-testing:SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests
```

#### 2. `.github/workflows/ci.yml` — narrow `ui-tests` to groups B+C
**File**: `.github/workflows/ci.yml`
**Action**: modify

Replace the existing `ui-tests` job's UI-tests step `-only-testing:SingleThreadUITests`
(line ~131) with the B+C class identifiers (`SingleThreadUITestsFlows`,
`SingleThreadUITests`, single `ActionButtonsTests`). Keep the Build step on the
full target; keep the flags, the matrix, cache, pre-boot, and timeouts:

```yaml
      - name: UI tests (flows + audits)
        timeout-minutes: 45
        run: |
          # Disables parallel test simulator clones: on GitHub's virtualized macOS
          # runners the iOS clone connection to com.apple.instruments.deviceservice.lockdown
          # can time out (120s) and stall the whole step. A single concurrent
          # destination avoids that race.
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -derivedDataPath "$DERIVED_DATA" \
            -maximum-test-execution-time-allowance 900 \
            -parallel-testing-enabled NO \
            -maximum-concurrent-test-simulator-destinations 1 \
            test-without-building \
            -only-testing:SingleThreadUITests/SingleThreadUITestsFlows \
            -only-testing:SingleThreadUITests/SingleThreadUITests \
            -only-testing:SingleThreadUITests/ActionButtonsUITests
```

### Verification
#### Automated
- [x] `actionlint .github/workflows/ci.yml` passes (YAML schema + `-only-testing` identifiers are structurally reachable); if actionlint unavailable, confirm the file parses with a strict YAML load that tolerates `${{ }}` interpolation (GitHub's own parser is final authority).
- [x] Confirm exact identifiers before relying on the matrix: run on a pre-boosted simulator:
  `xcodebuild -scheme SingleThread -destination '<sim>' -derivedDataPath DerivedData -enumerate-tests`
  and check the enumerated tree has `SingleThreadUITests` as the bundle with exactly
  the five class names above. If any differ, fix the `-only-testing:` fragments before pushing.
- [x] Push the branch; GitHub Actions starts **both** `ui-tests-launch-appearance` and `ui-tests` jobs concurrently (2 iOS UI jobs, each 2-device matrix).
- [x] `test-without-building` still skips recompile (warm DerivedData cache).
- [x] Union check holds: A ∪ (B+C) = today's same 5 classes (no class dropped,
      none double-run). `testAccessibilityAudit` and `testActionButtonsAccessibilityAudit`
      are in group C, `testActionButtonsRenderAndSkipAdvancesCard` too; all 7 `…Flows`
      methods are in group B — confirm each still executes in its group.

#### Manual
- [ ] PR shows 2 iOS UI jobs (4 matrix legs) running concurrently, not one.
- [ ] A job's wall-clock overlaps B+C instead of queuing behind it (job start times overlap in the actions page).

---

## Phase 3 — Fully split into per-tier jobs + single source of truth

**Files**: `.github/workflows/ci.yml`

### Changes

#### 1. `.github/workflows/ci.yml` — single source of truth (top-level `env`)
**File**: `.github/workflows/ci.yml`
**Action**: modify

Add a top-level workflow `env:` block (below `concurrency:`, above `jobs:`)
declaring each cost tier's `-only-testing:` fragment exactly **once**. This is
the structurally-guaranteed source: every job reads its key; no class list is
duplicated anywhere. (This replaces `structure.md`'s "comma-joined anchor string"
idea — those were written in the unsupported format. The fragment keys here use
the corrected repeated-flag form and a real workflow `env` map, which avoids YAML
anchor/merge-key/define-before-use pitfalls.)

```yaml
# Single source of truth for the iOS UI class groups. Each job reads exactly one
# `-only-testing:` fragment; the groups are disjoint and cover all 5 iOS UI classes
# in the SingleThreadUITests target exactly once.
env:
  UI_GROUP_A_ONLY_TESTING: "-only-testing:SingleThreadUITests/SingleThreadUITestsLaunchTests -only-testing:SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests"
  UI_GROUP_B_ONLY_TESTING: "-only-testing:SingleThreadUITests/SingleThreadUITestsFlows"
  UI_GROUP_C_ONLY_TESTING: "-only-testing:SingleThreadUITests/SingleThreadUITests -only-testing:SingleThreadUITests/ActionButtonsUITests"
```

#### 2. `.github/workflows/ci.yml` — group A job reads `env.UI_GROUP_A_ONLY_TESTING`
Change the `ui-tests-launch-appearance` test step's `-only-testing:` lines to a
single `${{ env.UI :GROUP_A_ONLY_TESTING }}` reference (same class set as Phase 2):

```yaml
      - name: UI tests (launch + appearance)
        timeout-minutes: 45
        run: |
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -derivedDataPath "$DERIVED_DATA" \
            -maximum-test-execution-time-allowance 900 \
            -parallel-testing-enabled NO \
            -maximum-concurrent-test-simulator-destinations 1 \
            test-without-building \
            ${{ env.UI_GROUP_A_ONLY_TESTING }}
```

#### 3. `.github/workflows/ci.yml` — split B and C into two jobs
**Action**: modify

Rename/split so the three iOS UI jobs are A, B (flows), C (audits):
- Rename the Phase 2 `ui-tests` combined (B+C) job to `ui-tests-flows`, and run
  only group B:
  `${{ env.UI_GROUP_B_ONLY_TESTING }}.`
- Add a new `ui-tests-audits` job (copy of the same template) running only group C:
  `${{ env.UI_GROUP_C_ONLY_TESTING }}.`

Both keep: `strategy.matrix` 2-device, `Pre-boot simulator`, `derived-data-…`
cache restore, full-target `build-for-testing`, and the test-step flags
`-maximum-test-execution-time-allowance 900`, `-parallel-testing-enabled NO`,
`-maximum-concurrent-test-simulator-destinations 1`, 45-min step timeout.

#### 4. `.github/workflows/ci.yml` — drop the transitional combined job
There is no longer any job with a merged A+B+C `-only-testing`, nor a B+C-
combined job. Exactly three iOS UI jobs remain (`...launch-appearance`, `...flows`,
`...audits`), parallel.

### Verification
#### Automated
- [x] `actionlint` (or equivalent) passes on `ci.yml`; no `<<` merge keys; anchors avoided.
- [x] The exact class-list strings appear **only** in the top-level `env:` (single source of truth).
- [x] Union/disjoint check from source alone: the five class-path identifiers in A, B, C are
      pairwise disjoint and their union == the current 5-class whole selection.
- [x] `./scripts/test.sh` (full) still passes locally: unit suite intact (~284, iOS + macOS),
      UI suite green, watch UI suite green with `runsForEach…=true` untouched.
- [ ] PR shows 6 iOS UI jobs (A/B/C on both iPhone 17 and iPad A16) plus the
      existing `unit-tests`, `mac-tests`, `lint`, `watch-ui-tests` jobs all green concurrently.

#### Manual
- [ ] Confirm total PR wall-clock < the ~15-minute baseline (measure longest leg; the
      tail is expected to be group B flows, which still fresh-launches each method).
- [ ] Spots-check empty group edge: temporally disable each `env.*` key and confirm only
      that tier's classes are skipped (proving groups are disjoint, not overlapping).
- [ ] `testAccessibilityAudit`, `testActionButtonsAccessibilityAudit`, and
      `testTapRevealsConfirmationDialog`-equivalent still run with assertion coverage
      under `CI=true`. `CI=true` audit trim preserved (not widened).
- [ ] Watch UI suite still green; `SingleThreadWatchLaunchTests` still
      `runsForEachTargetApplicationUIConfiguration = true`.

---

Backlog (out of scope for this change): if group B remains the wall-clock tail
because every method fresh-launches a `--seed` simulator, the G2 follow-up is to
split B's flow methods (7 currently) across two jobs.

## Whole-run invariant (never regressed)
- Watch launch keeps `runsForEachTargetApplicationUIConfiguration = true`.
- The union of the final three `-only-testing:` groups is the 5 iOS classes exactly
  once regardless of the split — no class dropped, none run twice.
- All assertions still audited (`CI=true` carve preserved, not expanded).
- Simulator pre-boot / pruning / XCTestDevices thresholds unchanged.
- No new `-parallel-testing-enabled YES` on iOS UI (the flaky clone path stays off).

---