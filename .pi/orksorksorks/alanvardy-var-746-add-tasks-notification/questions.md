# Research Questions

## Context

This research covers the SingleThread iOS codebase: the iOS app, watchOS app,
widget extension, and the `SingleThreadCore` SPM package. Focus areas are OS
notification/permission infrastructure, app lifecycle observation, the
settings/preferences persistence and UI layers, the EventKit reminder
fetch/filter pipeline, cross-target shared storage and sync, and existing
deterministic test seams. Map what exists and how it works — no code changes
are required.

## Questions

1. How are local/OS notifications handled in this app today? Trace any
   notification permission requests, `UNUserNotificationCenter` (or similar)
   usage, and what notification-related configuration exists in the project
   (entitlements, Info.plist keys, capabilities) on each target.

2. How does the app observe its own lifecycle (foreground/background/active)?
   Where are `scenePhase` changes or `UIApplicationDelegate` callbacks
   handled across the iOS and watchOS targets, and is any app-activity
   timestamp (e.g. last opened/active) currently read or persisted anywhere,
   in any UserDefaults suite?

3. What is the established pattern for adding a new user preference/setting?
   Describe each layer: `@AppStorage` keys in the app entry view, the
   `SettingsBindings` snapshot bag, the settings subviews, write-back via
   `.onChange`, the Core preference-store structs (both `load()/save(_:)` and
   `isEnabled`/`set(_:)` flavors), and any side effects (e.g. widget reload,
   orientation lock). Also: how is the settings UI organized into sections,
   and is there a distinct "interface settings" area?

4. How does `ReminderStore` determine which reminders are incomplete and due?
   Trace the fetch/filter/sort pipeline (EventKit predicates, date windows in
   `ReminderDateFilter`, skip/exclusion filtering) and identify what data
   would be available to answer "are there reminders the user still needs to
   complete" at an arbitrary point in time — including overdue reminders and
   reminders outside the current visible window.

5. How is persisted state shared and synced across the iOS app, watch app,
   and widget? Describe AppGroup UserDefaults usage per target (including
   any standard-suite fallback), the WatchConnectivity sync payload keys in
   `SkippedReminderSyncService`, and the `UserDefaults.didChangeNotification`
   observation flow.

6. What deterministic testing seams exist for iOS and watchOS (e.g. `--seed`
   launch arguments, `InMemoryEventStore`, `UITestingSeed.persistedKeys`,
   other launch-arg seams)? How are time-sensitive or async behaviors
   currently unit-tested (Swift Testing) and UI-tested (XCTest), and what
   accessibility-audit requirements apply?