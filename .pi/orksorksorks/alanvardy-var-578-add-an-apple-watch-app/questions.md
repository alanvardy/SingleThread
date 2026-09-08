# Research Questions

## Context

Focus on the `SingleThread` Xcode project: its app sources, its pure-logic
types, the Xcode project/build configuration, the test suites, and the CI
pipeline. In particular, look at how source files are assigned to targets, how
the app's single SwiftUI scene is structured, how per-device state is
persisted, what UI interaction and EventKit lifecycle patterns the main view
uses, which platforms and build settings are configured, how the build/test/lint
tooling is organized, and how tests are written and run.

## Questions

1. How does the Xcode project assign source files to targets, and what
   mechanisms exist for making one source file available to more than one
   target? What do the synchronized file groups and build phases look like?

2. What scene and entry-point structure does the app use (`@main`, `App`,
   `Scene` types), and what SwiftUI scene/lifecycle patterns are present in the
   codebase?

3. How is the "skipped reminders" list persisted? Trace the full lifecycle of
   `SkippedReminderStore` — its constructor, load/save behavior, which
   `UserDefaults` it targets (standard vs. suite), and where it is instantiated
   and called. Is there any existing App Group or cross-device/extension
   synchronization configuration (entitlements, container URLs)?

4. How does `ContentView` render reminders and handle interactions? Trace its
   layout primitives (GeometryReader, ZStack, List, ScrollView), interactive
   affordances (swipe actions, refreshable, task/onAppear), and EventKit
   lifecycle patterns (authorization request, predicate/fetch, completing a
   reminder, and the `@retroactive @unchecked Sendable` conformance).

5. What build settings govern the app and its targets — supported platforms,
   deployment targets, `TARGETED_DEVICE_FAMILY`, Swift language version,
   concurrency/isolation settings, code signing, and Info.plist generation —
   and where are they set (project level vs. target level)?

6. How is the build/test/lint/dead-code pipeline organized across the
   `Makefile`, `scripts/test.sh`, and `.github/workflows/ci.yml`? Which
   targets, schemes, simulators, and `-only-testing` filters are used, and how
   are warnings treated?

7. What test conventions exist in the unit and UI test targets? Which testing
   frameworks are used, how do tests avoid EventKit authorization prompts
   (launch arguments, dependency injection), and what fixture/pattern examples
   exist for constructing `EKReminder` instances and previewing views?
