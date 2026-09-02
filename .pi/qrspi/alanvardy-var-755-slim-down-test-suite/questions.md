# Research Questions

## Context

This repo has three test suites: `SingleThreadTests` (Swift Testing, 516 @Test
functions across ~54 files), `SingleThreadUITests` (XCTest, ~50 app launches
across 8 classes), and watchOS counterparts (`SingleThreadWatchTests`,
`SingleThreadWatchUITests`). Local runs are driven by `scripts/test.sh` and
`Makefile`; tests rely on seams such as `InMemoryEventStore`, `--seed` launch
args, and App Group `UserDefaults`. Focus on the structure of these suites,
their runtime-affecting characteristics, and the local test-runner mechanics.
Do not propose changes — map and measure what exists.

## Questions

1. **Assertion density across the unit suite.** What is the distribution of
   assertions per test function across `SingleThreadTests` (and
   `SingleThreadWatchTests`)? Which files are the most fragmented (many
   one-assertion tests exercising the same API), and which files already
   consolidate multiple assertions per test?

2. **Layered duplication of coverage.** Which behaviors are asserted at
   multiple layers at once — e.g. model-level `*PreferenceTests` paired with
   view-render `Show*Tests`, store/protocol/gate layers for the same
   persistence path, or the same settings flow covered in more than one UI
   test class? For each cluster, what does each layer add that the others do
   not?

3. **UI test launch profile.** How many app launches does the local iOS UI
   test run perform (and the watch UI run), and which tests relaunch the app
   multiple times and why? What per-launch work happens (app startup, `--seed`
   parsing, `AppGroup.defaults` reset, SpringBoard permission dialogs) and
   which tests share near-identical launch + interaction scaffolding?

4. **Test seams, shared state, and isolation constraints.** What do
   `InMemoryEventStore`, `--seed`/`--ui-testing*` launch args, and the
   App Group defaults reset touch, and what state is global or shared across
   tests? Which suites are marked `@Suite(.serialized)` and what internal
   state or resource do they serialize (e.g. a shared `EKEventStore`,
   timers, clock, file storage)? Where do tests wait on real time (sleeps,
   `waitForExistence`, minimum-display-duration logic)?

5. **Local runner composition and cost structure.** What does a local full
   run (`scripts/test.sh`) execute step by step — format, lint, build,
   periphery, unit, UI, watch, macOS — and which xcodebuild invocations
   rebuild vs. reuse `DerivedData`? What is inherently sequential in the
   runner, and which test targets/invocations are the heaviest (build
   products, simulator boot, runtime pruning)?

6. **Timing evidence and measurement.** What timing data already exists for
   the local suites (xcresult logs, `xcodebuild` output, past run logs in
   `.pi/qrspi/<branch>/`, CI artifacts)? Which suites or individual tests
   dominate local unit-test wall time, and what mechanisms for measuring
   per-test duration are already available in the repo or its config files
   (xcscheme, pbxproj, `.periphery.yml`)?