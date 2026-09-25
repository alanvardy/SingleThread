# Research Questions

## Context

This is a multi-module iOS/watchOS Swift codebase: `SingleThread/` (iOS app),
`SingleThreadCore/` (local SPM package, model/domain layer), `SingleThreadWatch/`
(watchOS app), `SingleThreadWidget/`, and four test targets (two Swift Testing
unit suites, two XCTest UI suites). Focus on how the code is layered, where
domain logic lives versus side-effectful infrastructure, what seams make it
testable, and what the current tests actually cover.

## Questions

1. How is SingleThreadCore's domain logic structured and covered? Trace
   ReminderStore's relationships (ReminderSkip, ReminderSort,
   AIReminderRanking, the skipped-reminder list) and describe where pure,
   unit-testable logic lives versus stateful EK-store ownership. Map which
   Core source files have a corresponding unit-test file and which have none.

2. What unit-test coverage patterns and gaps exist across the test targets?
   For each module (iOS app, Core, watch app, widget), list which source types
   have unit tests and which have none, and cite examples of test files that
   exercise complex pure logic (parsing, formatting, state machines, ranking,
   filter/sort).

3. Where does business logic live in the runtime/UI layers (iOS AppViewModel /
   ContentView / settings views, watch WatchAppViewModel / sync services,
   widget) and how is each tested? Describe how these layers keep logic
   testable versus requiring a live EventKit store, and the seams they use.

4. What injection/test seams does the codebase provide, and what are the
   conventions around constructing and consuming each one? Enumerate
   EventKitStoring, InMemoryEventStore, the --seed and --ui-testing launch
   args, AppGroup.defaults, and ReminderStore injection in previews/tests.

5. What are the test conventions and platform gating in the four test targets?
   Map the Swift Testing vs XCTest split, any #if os(...) / whole-file gating /
   gate hooks, the macOS unit-test target, and the shared test fixtures.