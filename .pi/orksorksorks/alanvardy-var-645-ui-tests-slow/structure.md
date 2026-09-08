# Structure Outline — VAR-645: UI tests slow

## Approach

Cut PR wall-clock by splitting the single monolithic iOS `ui-tests` CI step into
parallel per-cost-tier jobs (each on its own runner, pre-booted simulator, and
DerivedData restore), and by collapsing XCTest's per-config launch multiplier on
the classes that still run once per target-app configuration. No coverage is
dropped: the split groups' `-only-testing:` selections are disjoint and their
union equals today's full 5-class set. Watch UI, simulator lifecycle, and all
assertions are untouched.

> Vertical-slice axes here are orchestration, not DB/service/API/UI: each phase
> crosses **CI workflow config** × **XCTest source** × **local verification +
> coverage evidence** end-to-end, delivering a named wall-clock reduction that
> is green in isolation.

---

## Phase 1 — Collapse the per-configuration launch multiplier

Delivers the cheapest, lowest-risk win first: stops `SingleThreadUITests` and
`ActionButtonsUITests` from launching a fresh cold simulator once-per-target-
UI-configuration, dropping redundant launches today and shrinking every split
job's burst later. Independent of the split — valuable on its own.

**Files**:
- `SingleThreadUITests/SingleThreadUITests.swift`
- `SingleThreadUITests/ActionButtonsUITests.swift`

**Key changes**:
- Add to both classes:
  `override class var runsForEachTargetApplicationUIConfiguration: Bool { false }`
  (mirrors `SingleThreadUITestsLaunchTests.swift:17` and
  `SingleThreadUITestsAppearanceLaunchTests.swift:17`)
- Add `swiftlint:disable:next static_over_final_class` guard above each override.

**Verify**: `make ui-test` (or `scripts/test.sh --ui-only`) passes; iOS UI suite
still runs all methods; simulator launch count / XCTestDevices growth drops for
these two classes.

---

## Phase 2 — Split the monolith into two parallel iOS UI jobs

First slice of the primary lever, small enough to prove mechanics without a
full blast radius: carve the launch/appearance tier (group A) out of the
monolithic `ui-tests` job so it runs concurrently with the (now smaller)
groups B+C. Halves wall-clock for the cold-sim-sensitive tier immediately.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- New job `ui-tests-launch-appearance` — `strategy.matrix` of
  `["iPhone 17", "iPad (A16)"]`, with its own `Pre-boot simulator`,
  `actions/cache@v4` DerivedData restore (same `derived-data-…` namespace),
  `build-for-testing`, then `test-without-building` with
  `-only-testing:SingleThreadUITestsLaunchTests, SingleThreadUITestsAppearanceLaunchTests`.
- Narrow existing `ui-tests` job to the remaining tier:
  `-only-testing:SingleThreadUITests, ActionButtonsUITests, SingleThreadUITestsFlows`.

**Verify**: both jobs go green concurrently; the union of their
`-only-testing:` selections is exactly the current 5-class set (no drop /
double from today); the A job's runtime overlaps B+C rather than queuing behind
it; iOS flow + audit coverage unchanged.

---

### Phase 3: Fully split into per-tier jobs + single source of truth

Completes the vertical split: 3 groups × 2-device matrix = 6 parallel iOS UI
jobs. Introduces a single source of truth for the class lists so the disjoint /
exact-union invariant is structurally guaranteed, not hand-audited.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- Job `ui-tests-launch-appearance` (A): `…LaunchTests`, `…AppearanceLaunchTests`
- Job `ui-tests-flows` (B): `…SingleThreadUITestsFlows` (heaviest; every method
  fresh-launches a 118-seed)
- Job `ui-tests-audits` (C): `…SingleThreadUITests`, `ActionButtonsUITests`
- Drop the transitional combined job.
- Class lists declared once (one top-level map / anchor/pair of comma-joined
  `-only-testing:` strings) and each job reads from it; no duplicated lists.
- Each job keeps `-parallel-testing-enabled NO`,
  `-maximum-concurrent-test-simulator-destinations 1`,
  `-maximum-test-execution-time-allowance 900` (preserve ci.yml:129-130), and
  the 45-min step timeout.

**Verify**: all 6 iOS UI jobs + existing unit/mac/lint/watch jobs green;
coverage-matrix check passes (every index in the 5-class union exactly once;
`testAccessibilityAudit`, `testActionButtonsAccessibilityAudit`,
`testTapRevealsConfirmationDialog`, all 7 `…Flows` methods still execute);
PR total wall-clock measured below the ~15-min baseline.

---

### Phase 4 (optional, deferred) — macOS build reuse behind gate

**Only if** the reuse bridge is proven and the macOS leg remains a meaningful
wall-clock contributor. Reuse `test-without-building` on the macOS unit leg,
gated behind `CODE_SIGNING_ALLOWED=NO` against the existing `derived-data-mac-`
cache so a failure is isolated. Not a vertical slice — it is the design's open
risk and is explicitly out of the primary path.

---

## Testing Checkpoints

- **After Phase 1**: unit suite intact (~284), iOS UI suite green with launch
  count reduced for the two adapted classes.
- **After Phase 2**: two iOS UI jobs both green concurrently; split union still
  covers all 5 classes; cold-launch tier no longer queues behind flows/audits.
- **After Phase 3**: six iOS UI jobs green; union-disjointness proven from a
  single source of truth; PR wall-clock < baseline (measure per-leg for group
  B; if B is still the tail, the G2 follow-up split of its 6 flows is the plan).
- **Untouched invariant (never regress)**: watch launch keeps
  `runsForEachTargetApplicationUIConfiguration = true`; watch UI suite green;
  `CI=true` audit trim preserved (not widened); all assertions still audited.

---

**Not vertically sliceable**: the exact-union integrity guarantee (Phase 3) is
only meaningfully exercised once all 3 jobs exist — splitting the first two
jobs does not fully prove it. Likewise, app-reuse across XCTest methods is
deliberately out of scope (XCTest is per-method by default); if desired later,
it needs its own proof of class-scope sharing.