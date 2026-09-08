# Research Questions

## Context
Focus on the reminder card rendering path in the iOS app (`ReminderCardView`, `ContentView`), the model/domain layer in the `SingleThreadCore` package (`ReminderStore`, `ReminderDisplay`, `EventKitStoring`, `AppGroup`), the settings screen (`SettingsView`) and its persistence, and how data and preferences reach the watch app and widget surfaces.

## Questions
1. Trace the full flow of reminder data from `EKReminder` objects held by `ReminderStore` through `ReminderDisplay` to each rendering surface (iOS card view, watch card view, widget): which fields exist on `ReminderDisplay`, where are they populated from EventKit, and which surfaces consume which fields?
2. How does the codebase currently access per-reminder calendar/list information — e.g. how do the excluded-projects filtering and available-projects list read calendar titles — and what APIs or abstractions (`EventKitStoring`, test/in-memory stores) exist around it?
3. How are boolean display preferences defined end to end: the `Toggle` rows in `SettingsView`, their `@AppStorage` bindings in `ContentView`, which UserDefaults suite they use (`.standard` vs App Group), and how changes propagate to widget timelines and the watch via `ReminderStore` hooks / WatchConnectivity?
4. Where exactly do the settings label strings "Show Undated" and "Enable action buttons" appear across app code, tests, and any other targets, and what conventions govern their wording, casing, icons, and platform gating?
5. How does `ReminderCardView` conditionally show or hide optional content rows (such as the due-date row gated by a preference) and handle its contrast/accessibility modes, and what unit-test patterns cover its rendered output?
6. What UI-testing seams exist for driving settings toggles and verifying card contents deterministically (launch args like `--ui-testing` / `--seed`, `UITestingSeed`, accessibility identifiers), and how do existing UI tests assert toggle behavior?
