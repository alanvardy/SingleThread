# Research Questions

## Context
This repository is a small SwiftUI app (iOS and macOS) built with Xcode. The repository also contains the full CI and testing setup: a GitHub Actions workflow, a local test script, a Makefile, an Xcode project with unit-test and UI-test targets, and lint/format tooling. Focus your investigation on the CI workflow, the Xcode build/test configuration and destinations, the composition of the test targets, and the local build/test/lint tooling.

## Questions
1. Trace the CI pipeline end to end: what jobs, steps, and dependencies does the GitHub Actions workflow define, and how are build, unit-test, and lint/format steps sequenced and parallelized across jobs?
2. How does the CI workflow invoke `xcodebuild` for building versus running tests — what arguments (scheme, destination, configuration, test filters) are passed, and are build and test run as separate invocations or combined? What simulator destination and runtime is targeted, and how (if at all) is the simulator prepared before `xcodebuild` runs?
3. What test targets and test cases exist in the Xcode project — what does the unit-test bundle cover, what does the UI-test bundle do, and which test code is pure versus coupled to system frameworks or the app target?
4. What build settings and compilation modes are configured in `project.pbxproj` (Debug vs Release: debug-info format, optimization level, active-arch, testability, whole-module compilation), and how are they distributed across the app and test targets?
5. How is build output cached in CI — what paths are cached, what cache keys and restore-keys are used, and what triggers a cache miss or partial restore?
6. How are SwiftLint and SwiftFormat provisioned and run in CI, and what do the `.swiftlint.yml` and `.swiftformat` configurations enable or disable?
7. How do the local Makefile targets and `scripts/test.sh` relate to the CI steps — which commands do they share, and where do they differ?
