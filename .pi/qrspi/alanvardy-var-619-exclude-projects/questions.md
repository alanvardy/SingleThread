# Research Questions

## Context
This codebase is an iOS/watchOS SwiftUI app that surfaces Apple Reminders through EventKit, showing one reminder at a time. Focus on: the settings screen and how preferences are declared, bound, and persisted; the reminder fetch/filter/sort pipeline in `ReminderStore`; EventKit's calendar/list model; the skipped-reminder exclusion and its persistence/sync; and the store injection and testing conventions.

## Questions
1. Trace how the settings screen is built and persisted: how is `SettingsView` structured, how are its preference values declared and bound (e.g. `@AppStorage` vs `@Binding`, platform-specific initializers), which SwiftUI controls are used, and how are these settings tested and previewed?

2. Trace the reminder fetch-to-display flow: what exactly does `ReminderStore.reload()` query (including the `calendars:` argument of the EventKit predicate), and where between EventKit and `visibleReminders` is the decision made about which reminders are shown?

3. What EventKit types and APIs are present for reading reminder lists/calendars (e.g. `EKCalendar`, `EKSource`, `calendarIdentifier`, titles, any enumeration such as `calendars(for:)`)? Does any calendar/list model exist in the codebase, and is the predicate's `calendars:` argument ever used?

4. Trace how the skipped-reminder exclusion set is persisted and pruned: how do `SkippedReminderStore`, `ReminderSkipLogic`, and the App Group `UserDefaults` interact, and how do stored identifiers stay aligned with the currently-fetched reminders?

5. How is `ReminderStore` injected and tested? Describe the `EventKitStoring` protocol, the `FakeEventStore` test double, the preview/test initializers, and the Swift Testing conventions used for store-level tests.

6. How do the watch app and the widget construct and use their own `ReminderStore` instances, and how does phone↔watch WatchConnectivity sync currently push user-controlled state between devices?