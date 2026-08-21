# Research Questions

## Context

Focus on the test/build orchestration of the SingleThread Xcode project: the
`xcodebuild` invocations in `scripts/test.sh`, `Makefile`, and
`.github/workflows/ci.yml`; the test/build target and scheme configuration in
`SingleThread.xcodeproj/project.pbxproj`; how DerivedData build artifacts are
built, cached, and reused via `test-without-building`; how XCTest simulator
runtimes are created/cleaned up; and the per-test launch/seam mechanics plus
CI parallelism controls. The bundle unit-test suite (`SingleThreadTests`,
Swift Testing) and the XCTest UI suites (`SingleThreadUITests`,
`SingleThreadWatchUITests`) both matter. Do not propose improvements — just
map what exists and how it behaves.

## Questions

1. In `scripts/test.sh`, `Makefile`, and `.github/workflows/ci.yml`, how is
   each build and test invocation ordered and shaped — which builds are reused
   across test invocations (same `-derivedDataPath` + `test-without-building`)
   versus rebuilt fresh, and which schemes/destinations/device targets are
   involved for iOS unit, iOS UI, watch UI, and macOS tests?

2. What parallelism exists at the `xcodebuild`-test and workflow level: the
   `-parallel-testing-enabled` / `-maximum-concurrent-test-simulator-destinations`
   flags, `-maximum-test-execution-time-allowance`, CI strategy `matrix` jobs,
   `BuildIndependentTargetsInParallel`, and the XCTest device simulators Google
   cloud concurrency constraints on Google-cloud virtualized runners — and why
   was parallel test cloning disabled for iOS UI tests but not watch UI tests?

3. How does DerivedData build artifact caching/reuse currently work — the
   `actions/cache` key design in each CI job, the `test-without-building`
   bridge, the shared `DerivedData` path, `.gitignore` exclusion, and whether
   any local persistence of build artifacts exists outside CI?

4. How much of the total duration comes from where? Trace what happens per XCTest
   UI-test invocation: the ~3 GB XCTestDevices runtime creation/lifecycle, the
   `cleanup_xctest_runtimes` pruning in `scripts/test.sh`, simulator cold boot,
   app launch cost, and the per-test `launchArguments`/test seams
   (`--ui-testing`, `--seed`, `--no-reminders`) — and how
   `runsForEachTargetApplicationUIConfiguration` affects launch multiplication
   per test class.

5. How do the accessibility audits behave differently under CI, and how are
   the slowest/hang-prone test categories (dynamic type, hit region, contrast,
   parallel-clone connection, TCC/Reminders prompt) currently gated, skipped,
   or worked around in the UI test sources and CI flags?

6. What does the unit-test side look like: how the Swift Testing
   (`SingleThreadTests`) suite (~284 tests) is built and executed, the device
   matrix, the separate macOS destination, and whether its build or run
   contributes meaningfully to the overall pipeline.

7. Which XCTest/`xcodebuild` options or simulator-settings exist in the repo
   (`-showBuildTimingSummary`, `-maximum-test-execution-time-allowance`,
   pre-boot via `simctl`, cache/boot steps in CI) that indicate where current
   timing and resource limits are set, and how those limits would be observed
   if the UI suite were re-partitioned?