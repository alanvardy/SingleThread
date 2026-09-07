# Research Questions

## Context

Focus on the test-runner infrastructure and test suites of this iOS + watchOS
app: `scripts/test.sh`, `Makefile`, `.github/workflows/ci.yml`, the
`SingleThreadTests` / `SingleThreadUITests` / `SingleThreadWatchUITests`
targets, and the launch seams (`--ui-testing`, `--seed`) they drive. The goal
of this research is to map exactly how test phases are wired today, what each
destination (iOS Simulator vs macOS native vs watchOS Simulator) actually
executes, and what tooling exists for platform-conditional test execution.

## Questions

1. Trace `scripts/test.sh full` end to end: which phases run, in what order,
   which destination each xcodebuild invocation targets, and what each phase
   depends on from the prior one (shared booted simulator, build products,
   env vars such as `UNIT_ONLY`/`UI_ONLY`). Where exactly does the iOS-Simulator
   unit pass run relative to the macOS native unit pass, and how do the
   `--unit-only` and `--ui-only` modes slice the same pipeline?

2. Compare what the 520 `SingleThreadTests` actually execute on the iOS
   Simulator versus natively on macOS. Which test files/methods touch
   iOS-only frameworks (EventKit/EKEventStore, UIKit, TCC prompts, file
   system paths) and how are they currently gated (compile-time `#if os(...)`
   vs anything runtime)? What behaviors exist on one destination and not the
   other (real EK store availability on macOS, entitlement/lock-file state,
   `CODE_SIGNING_ALLOWED`), and what is the provenance of the "520" and "564"
   test counts?

3. What platform-conditional execution facilities does the Swift Testing /
   XCTest toolchain in use actually support for skipping tests at runtime —
   `@available(on:)` / `@available(platform:)`, trait-based skip, XCTest
   invocation args, or `-only-testing` filters — and which of them does the
   repo's Swift version (6.0) and Xcode accept? Is there any existing
   precedent of a skipped/available-gated test anywhere in the repo, and how
   does `#if os(...)` interact with `-only-testing:SingleThreadTests` at two
   destinations?

4. Enumerate the full surface of the UI test targets: all 23 iOS + 15 watch
   test methods, what each asserts, and which assertions are already mirrored
   by native unit tests via the `--seed`/`--ui-testing` seams. Separately map
   the `performAccessibilityAudit` call sites (which a11y categories, the CI
   carve-out logic), and the `runsForEachTargetApplicationUIConfiguration`
   settings across iOS vs watch launch tests.

5. Map `.github/workflows/ci.yml`: every job, the device matrices, the env
   group split (Launch+AppearanceLaunch / Flows / Audits for iOS, and watch),
   which simulator is booted by whom (including the standalone watch sim),
   the `-parallel-testing-enabled NO` / `-maximum-concurrent-test-simulator-
   destinations 1` constraints, retry/artifact handling, and which raw
   xcodebuild invocations each job runs (CI does not call `scripts/test.sh`).

6. Trace the launch seams from launch argument to rendered UI: how
   `AppViewModel` (iOS) and `WatchAppViewModel` (watchOS) parse `--ui-testing`
   and `--seed '<json>'`, what state the resulting `InMemoryEventStore` seeds
   and how a UI test launches the app (`SingleThreadUITestCase.launchApp`
   / the watch private `launchApp` helper). What does the app render on a
   plain `--ui-testing` launch on each platform (what a smoke test would
   assert), and what differs between the iOS and watch launch paths (sim
   install, dylib injection, launch arguments)?