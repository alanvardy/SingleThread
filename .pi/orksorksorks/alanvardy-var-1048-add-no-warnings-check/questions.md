# Research Questions

## Context

Focus on the build/CI gate (`scripts/test.sh`, `Makefile`,
`.github/workflows/ci.yml`), the Xcode project warning configuration in
`SingleThread.xcodeproj/project.pbxproj`, and the Swift SPM package
(`SingleThreadCore`, `Package.swift`). Relevant build targets are the iOS
app, watchOS app, widget extension, Core package, and the unit/UI test
targets. Two build paths are involved: the local gate in `scripts/test.sh`
and the separate step-based CI in `.github/workflows/ci.yml`.

## Questions

1. How do the Swift 6 compiler warning defaults and the project's per-target
   build settings (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, the SPM package's
   `-suppress-warnings`, per-target config blocks in the pbxproj) determine
   which warnings each build target emits? Trace project-level vs
   target-level config inheritance, the `SingleThreadTests`
   `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` override precedent, and where
   warnings-as-errors would currently fail vs pass.

2. In `scripts/test.sh`, how is each xcodebuild invocation written, how does
   its stdout/stderr flow, where do failures propagate (`set -e`, exit
   codes), and what does the existing `scripts/test-one.sh` build-log capture
   idiom look like? Which build phases and targets exist (build vs
   build-for-testing, per-target `-only-testing`), and what would a warnings
   observation point need to cover?

3. What compiler-warning suppression and lint-convention mechanisms exist
   across the tree — the `SingleThreadTests` warnings-as-errors override,
   SwiftLint disable comments and configs, any pragma/`-Wno` usage, and
   `.swiftformat` / `.swiftlint.yml` settings — and what conventions do they
   establish?

4. In `.github/workflows/ci.yml` and the `Makefile`, how do they invoke the
   build and the gate relative to `scripts/test.sh` — which steps run
   xcodebuild, how is build output logged or retained, and is each CI job a
   faithful re-implementation of the test.sh phases or a separate path?
   Are build logs uploaded or retained anywhere for later inspection?