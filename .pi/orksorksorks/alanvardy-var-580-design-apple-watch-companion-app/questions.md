# Research Questions

## Context

Focus on the `SingleThread` Xcode project and its surrounding tooling. In
particular, trace the app's target/build configuration (supported platforms,
deployment targets, `TARGETED_DEVICE_FAMILY`, bundle identifiers, code
signing), how source files are assigned to targets and shared between them,
the SwiftUI entry-point and scene structure, how the "skipped reminders" list
is persisted and whether any App Group or cross-device synchronization
mechanism exists, how `ContentView` performs EventKit lifecycle operations and
renders interactions, and how the unit/UI test suites are structured and
invoked by CI.

## Questions

1. What platforms and device families does the Xcode project currently
   support, and where are `SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY`,
   deployment targets, bundle identifiers, and code-signing settings defined
   for each target? What does the project's file-group/target structure look
   like, and how would a source file be made available to more than one
   target?

2. What is the app's scene and entry-point structure (`@main`, `App`, `Scene`
   types, `WindowGroup`), and which SwiftUI lifecycle patterns are in use?

3. How is the "skipped reminders" list persisted? Trace the full lifecycle of
   `SkippedReminderStore` — construction, load/save, which `UserDefaults`
   (standard vs. suite) it targets, and where it is instantiated and called.
   Is there any existing App Group, entitlements, or container/synchronization
   configuration anywhere in the project?

4. How does `ContentView` render reminders and handle user interaction? Trace
   its layout primitives, interactive affordances (swipe actions,
   `refreshable`, `task`/`onAppear`), and EventKit patterns (authorization
   request, predicate/fetch, completing a reminder, and the
   `@retroactive @unchecked Sendable` conformance).

5. What pure-logic components exist (`ReminderSkipLogic`,
   `ReminderNotesFormatter`, `ReminderDateFilter`), what are their
   dependencies, and how are they unit-tested? What makes them reusable
   outside the iOS app target?

6. How is the build/test/lint pipeline organized (Makefile, `scripts/test.sh`,
   `.github/workflows/ci.yml`)? Which schemes, targets, simulators,
   `-only-testing` filters, and warning settings are used, and how would an
   additional target or destination (e.g. a watch simulator) fit into it?

7. How do the unit and UI test suites avoid EventKit authorization prompts
   (launch arguments, dependency injection), and what fixture/pattern
   examples exist for constructing `EKReminder` instances and previewing
   views?
