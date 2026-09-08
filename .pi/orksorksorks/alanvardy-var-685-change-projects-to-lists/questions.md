# Research Questions

## Context
Focus on the reminder-filtering feature that lets users exclude named calendar groupings:
its state lives in `SingleThreadCore` (`ReminderStore`, `ExcludedProjectStore`,
`SkippedReminderSyncService`, `UITestingSeed`), its UI is in `SingleThread/SettingsView.swift`
and the watch app, and it spans iOS/watchOS sync and unit/UI tests.

## Questions
1. Trace the full flow of an excluded title on iOS: from the settings UI toggle, through
   `ReminderStore` state changes, into `ExcludedProjectStore` persistence, and back out via
   `visibleReminders` filtering. Which type names, property names, method names, callback
   names, and UserDefaults keys are involved at each hop?
2. How do excluded titles sync between iPhone and Apple Watch over WatchConnectivity?
   Identify the payload keys written to the application context, the receive path callbacks,
   how each side applies received values, and any asymmetry between the push and receive paths.
3. Where does user-facing text mention "project" or "projects" across all targets (iOS app,
   watch app, widget)? Include navigation titles, row labels, accessibility identifiers/labels,
   placeholder text, SwiftUI preview fixtures, and UI-test launch arguments.
4. What compatibility constraints exist around the persisted and exchanged keys — the App Group
   UserDefaults key(s), the WatchConnectivity payload keys, and the UI-test seed JSON keys
   (including legacy keys such as `"excludedProjects"`)? What would break on already-installed
   devices or paired watches if a key name changed, and do any existing keys have migration or
   fallback handling?
5. How does EventKit model these groupings natively — what does `EKCalendar` expose (title,
   identifier) for `.reminder` calendars, and does the codebase already use "list" terminology
   anywhere (comments, symbols, doc comments) when referring to them?
6. What test coverage exists for this exclusion feature — unit tests for persistence, filtering,
   sync, and seed decoding, plus UI tests on iOS and watchOS? Name the suites, helper functions,
   fixture builders, and launch-argument seams that reference the concept.
