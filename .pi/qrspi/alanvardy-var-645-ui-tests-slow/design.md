# Design Discussion — VAR-645: UI tests slow

## Current State

The XCTest UI suite (and to a lesser degree the unit suite) can take up to
~15 minutes wall-clock through CI and the local `scripts/test.sh` pipeline.

**The dominant cost is test-launch count, not build time.** Every XCTest
method constructs a fresh `XCUIApplication()` and launches it into a fresh
~3 GB simulator runtime under `~/Library/Developer/XCTestDevices`
(test.sh:16, 18-19), which Xcode never prunes. The launch count is multiplied
by XCTest's per-target-app-UI-configuration default:

- Only two classes force `runsForEachTargetApplicationUIConfiguration = false`
  to stay under the cold-CI step timeout:
  `SingleThreadUITestsLaunchTests.swift:17` and
  `SingleThreadUITestsAppearanceLaunchTests.swift:17`. The watch launch class
  overrides it to `true` (`SingleThreadWatchUITestsLaunchTests.swift:6`).
  The remaining iOS classes (`SingleThreadUITests`, `SingleThreadUITestsFlows`,
  `ActionButtonsUITests`) do NOT override, so each multiplies its fresh runtime
  + cold boot by the per-config count (research.open-area 1: the exact count
  is not surfaced in sources).
- No app reuse across methods: `SingleThreadUITestsFlows.swift:22-31`
  (`launchApp(seedJSON)` called by every flow test) and
  `SingleThreadUITests.swift:26-28`,
  `SingleThreadUITestsLaunchTests.swift:25-31`,
  `ActionButtonsUITests.swift:12, 29`.

**Build artifacts are ALREADY reused.** Locally, one iOS `build-for-testing`
feeds both unit + UI via `test-without-building` sharing one `-derivedDataPath`
(`scripts/test.sh:180-184 → :202-203, :210-211`); CI restores a
`derived-data-*` cache per job and runs `test-without-building` off it
(ci.yml:50-64, 109-131). macOS is the exception in BOTH layers: plain
`build` + `test`, never `test-without-building` (`ci.yml:162-177`;
`test.sh:230-242`), so the macOS leg recompiles every run.

**Simulator-level parallelism is already effectively off.** CI sets
`-parallel-testing-enabled NO` + `-maximum-concurrent-test-simulator-destinations 1`
on the iOS UI step (ci.yml:128-130) after two reverts (`da236fa`, `3743384`) because
the iOS clone connection to `...deviceservice.lockdown` times out on GitHub's
virtualized runners. Watch UI keeps only the 900s time-allowance (ci.yml:289)
because it runs against a per-run standalone created sim (ci.yml:255-272).
CI already gets cross-job parallelism: 5 independent jobs, iOS unit+UI each on a
2-device `matrix` of separate runners (ci.yml:16-17, 76-78).

**The observable bottleneck.** The `ui-tests` job runs all 5 iOS UI classes in
one sequential `test-without-building` step (`-only-testing:SingleThreadUITests`,
ci.yml:114-131), on one simulator per matrix leg. Every class's launchers queue
up behind the previous class's — so this single step's elapsed time is the sum
of all classes, which sets the wall-clock tail.

## Desired End State

Make CI wall-clock meaningfully shorter **without weakening coverage**. This is a
public repo, so runner billing is NOT a cost constraint — the design maximizes
parallelism to cut wall-clock.

Primary lever: **split the single `ui-tests` step into parallel per-group CI
jobs**. Each new job `-only-testing:` a subset of the 5 iOS UI classes, on its
own runner + pre-booted simulator + DerivedData restore, launching concurrently
with every other job. PR wall-clock is then bounded by the slowest group rather
than by the sum of all classes. This is vertical parallelism across jobs — it
is NOT re-enabling the intra-step simulator clones that flaked
(`-parallel-testing-enabled`, ci.yml:128-130).

Secondary lever (still used): **collapse the per-config multiplier** on the
non-override classes so each group also drops redundant launches within itself.

**Verify correct by:**
- Every UI flow (list, skip, complete, delete, settings — `SingleThreadUITestsFlows.swift`)
  still executes every method; none dropped across the split groups.
- `testAccessibilityAudit`, `testActionButtonsAccessibilityAudit`,
  `testTapRevealsConfirmationDialog` still run and stay green under `CI=true`.
- Each UI group's `-only-testing:` selection is disjoint, and their union
  covers all 5 classes exactly once (no silent drops or doubles).
- Unit suite (iOS + macOS) still passes entirely (`SingleThreadTests`, ~284 tests).
- Watch UI suite unchanged, still green, watch launch keeps
  `runsForEachTargetApplicationUIConfiguration = true`.
- Total PR wall-clock measured below the current ~15-min baseline.

## Patterns to Follow

- **`--seed '<>'` + `InMemoryEventStore`** for deterministic write flows
  (`SingleThreadApp.swift:109-121`, `SingleThreadUITestsFlows.swift:22-33`).
  Keep — the deterministic, no-EventKit seam for UI write tests.
- **`--ui-testing` empty-store seam** for read-only/render tests
  (`SingleThreadApp.swift:130-146`). Keep.
- **`--no-reminders` to suppress the Reminders TCC prompt** on cold-launch paths
  (`SingleThreadUITestsAppearanceLaunchTests.swift:26-27, 35, 62, 93`).
  Keep — removes a hang-prone prompt from scene activation.
- **`runsForEachTargetApplicationUIConfiguration = FALSE`** on the two launch
  classes is the model to extend to the non-override classes so each group's
  remaining launchers no longer multiply per-config.
- **`test-without-building` + shared `-derivedDataPath`** is already the bridge;
  keep it, and reuse the same pattern for each new split group (each restores
  its own `derived-data-…` cache and skips recompile).
- **`Pre-boot simulator` step** per job (ci.yml:39-45, 100-106) — each split
  job should pre-boot its simulator the same way so no group starts cold.

## Patterns NOT to Follow

- **Re-enabling `-parallel-testing-enabled YES` (iOS UI).** Both prior attempts
  flaked on virtualized runners (clone `...lockdown` timeout; `.xctrunner`
  `ipc/mig server died`). Job-splitting does not require it; keep it disabled.
- **The asymmetric audit gating.** The iOS main audit trims
  dynamicType/hitRegion when `CI=true` (`SingleThreadUITests.swift:40-46`), but
  `ActionButtonsUITests.swift:54` and `SingleThreadWatchUITests.swift:37` run the
  full rendering-heavy categories with NO `CI` gate — those can hang/stall on
  GitHub runners. If this ticket touches audits at all, make them obey the same
  `CI=true` carve-out (coverage is preserved by the unit suites), not full
  rendering on CI.
- **macOS's rebuild-every-run shape** — it is one leg that still pays a full
  recompile; if this ticket re-touches CI jobs, reuse the bridge there too
  (gated behind `CODE_SIGNING_ALLOWED=NO`).
- **Duplicated full-matrix fallback run** (a "split-and-merge" extra complete run)
  unless coverage demands it — with billing off it is acceptable but not default.

## Design Decisions

1. **Split the iOS UI step into parallel per-group CI jobs (primary).** Replace
   the single `-only-testing:SingleThreadUITests` `ui-tests` step with N
   parallel jobs, each `-only-testing:` one cost-tier group, each with its own
   runner/pre-boot/DerivedData. PR wall-clock becomes the slowest group, not the
   sum.

2. **Grouping by cost tier (G1).**
   - **A — launch/appearance**: `SingleThreadUITestsLaunchTests` +
     `SingleThreadUITestsAppearanceLaunchTests` (already config-capped; cold-sim
     sensitive).
   - **B — write flows**: `SingleThreadUITestsFlows` (heaviest; every method
     does a fresh `--seed` launch).
   - **C — audits**: `SingleThreadUITests` + `ActionButtonsUITests`
     (CI-trimmed already, rendering-heavy).
   This bounds each job's wall-clock by a single cost tier. (The G2 variant —
     splitting group B's 6 flow methods across two jobs — stays available as a
     follow-up if B remains the tail.)

3. **Retain the 2-device matrix on every group (Option A).** Billing is not a
   constraint, so preserve today's coverage parity: every group runs on both
   `iPhone 17` and `iPad (A16)` (ci.yml:77-78). Result: 3 groups x 2 devices =
   6 parallel iOS UI jobs (plus existing unit/mac/lint/watch jobs). This keeps
   device coverage identical to today while giving the wall-clock cut.

4. **Collapse the per-config multiplier (secondary).** Extend
   `runsForEachTargetApplicationUIConfiguration = false` to
   `SingleThreadUITests` and `ActionButtonsUITests` so each group's launch
   count drops. Complement with app reuse within a class only where XCTest
   class-scope allows. Cheap, still a win, independent of split.

5. **Simulator runtime lifecycle untouched.** Keep `Pre-boot simulator`, the
   local `cleanup_xctest_runtimes()` prune, and thresholds. No new
   reuse mechanic.

6. **Unit lane reuse (minimal).** Reuse the bridge for the macOS leg
   (`CODE_SIGNING_ALLOWED=NO`) only if its `test-without-building` is proven
   green; otherwise leave the unit suite as-is.

## What We're NOT Doing

- **NOT re-enabling `-parallel-testing-enabled` for iOS UI** — job-splitting
   is the vector, not intra-step clones.
- **NOT changing the watch launch's `runsForEachTargetApplicationUIConfiguration` =
  `true`.**
- **NOT changing simulator pre-boot / pruning / XCTestDevices thresholds.**
- **NOT reducing the assertion set** — every category currently audited stays
  audited (the `CI=true` trim is preserved, not expanded).
- **NOT changing the single incomplete-run invariant implicitly** — the union of
  the split groups must equal today's entire 5-class selection.
- **NOT splitting group B further (G2) in this change** unless it remains the
  dominant tail after re-measurement.

## Open Risks

- **Group union integrity.** A split risks dropping or double-running a class;
  the job design must derive each `-only-testing:` set from a single source
  of truth (e.g. one `matrix` of class lists) so the union is exact.
- **XCTest determinism under 6 concurrent iOS jobs.** Each job is an isolated
  runner/simulator, so no shared simulator, but GitHub's virtualized fleet can
  still slow individual legs; the 45-min namespace and 900s allowance stay.
- **App-reuse isolation** if reuse within a class ships later: XCUIApplication
  is per-method by default; XCTest may not document share-across-methods. Keep
  the per-method launch unless class-scope sharing is proven — the per-config
  collapse already gives most of the win.
- **`CI=true` audit trim relies on unit suites** (e.g. `AppearanceModeTests.swift`);
  verify each dropped dynamicType/hitRegion case is unit-covered before
  trimming more audits.
- **macOS bridge unproven** — extend behind the existing `derived-data-mac-`
  cache so a failure is isolated.
- **Watch lane untouched**; only iOS `ui-tests` is split in this change.