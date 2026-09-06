# Research Questions

## Context

This repo runs Swift/XCTest suites both locally (Makefile, scripts/test.sh,
scripts/simverify.sh) and in GitHub Actions (`.github/workflows/ci.yml` with
matrix jobs). Research should map every piece of shared machine state that a
test/build run reads or writes: the DerivedData build directory, result and
coverage bundles, simulator devices and their persisted on-device state,
UserDefaults suites (App Group vs standard), the InMemoryEventStore launch
seams (`--seed`, `--ui-testing`), CI caches and artifacts, and how parallel
execution is configured inside a single xcodebuild run. Also survey the
`.pi/qrspi/<branch>/` archives, commit history, and CI config comments for
documented incidents or stated reasons related to test-run interference.

## Questions

1. How is filesystem state shared between build and test invocations? Trace
   where `-derivedDataPath`, `-resultBundlePath`, coverage bundles, and the
   Periphery index store are written across Makefile, scripts/test.sh, and
   ci.yml — which paths are fixed vs per-invocation, and which are read or
   written by multiple invocations.

2. Which simulator devices and `simctl` state do test runs depend on, and
   what persists across runs? Cover device selection/destination resolution,
   pre-boot logic, watch device creation and pairing, `XCTestDevices` runtime
   pruning, and the absence or presence of shutdown/erase/terminate steps in
   local vs CI automation.

3. How do the `--seed` and `--ui-testing` launch seams and unit-test code
   interact with persisted UserDefaults state? Map which keys each seam and
   test target writes to `AppGroup.defaults` vs `UserDefaults.standard`,
   where persisted state is reset between launches, and where it is
   intentionally or implicitly retained (cross-launch leaks).

4. How is parallelism structured within a single test run? Examine scheme
   `parallelizable` settings, `-parallel-testing-enabled` /
   `-maximum-concurrent-test-simulator-destinations` flags, the
   `test-without-building` pattern, process-scoped shared objects (e.g. a
   shared EKEventStore/InMemoryEventStore), and how the iOS, watchOS, and
   macOS suites relate to each other in a run.

5. How does the GitHub Actions pipeline isolate or share state across jobs
   and runs? Cover the matrix structure, DerivedData cache keys (device-
   scoped or not), fixed artifact/xcresult names and their upload paths,
   `concurrency` groups, and per-job VM freshness assumptions.

6. What coordination mechanisms exist around test runs today, and what
   documented incidents show runs interfering with each other? Inventory
   locks, conventions (e.g. "one xcodebuild test process at a time"),
   age-gated cleanup, retry logic, and any failure descriptions in
   `.pi/qrspi/<branch>/` archives (e.g. OOM kills, DerivedData collisions,
   simulator Busy/RequestDenied) alongside their likely causes.