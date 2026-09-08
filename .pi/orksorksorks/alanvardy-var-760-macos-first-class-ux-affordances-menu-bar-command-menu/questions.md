# Research Questions

## Context

This survey covers the SingleThread iOS/macOS app: the macOS build target's
app lifecycle and scene/menu structure, the shared reminder-action and
appearance plumbing, the platform-gated notification code and its test
seams, the shared app-group persistence layer, and the conventions used for
platform-divergent UI and testing.

## Questions

1. **macOS app surface & lifecycle** — Trace how the macOS app is launched
   and structured: the `App` scenes in `SingleThreadApp.swift`, how
   `MacAppDelegate` is adapted into the app and what it currently bridges,
   and how keyboard shortcuts are registered. What app-level menus exist on
   macOS today (explicit or SwiftUI defaults), and what is the card-scoped
   shortcut surface in `ContentView+ActionMenu.swift`?

2. **Reminder action flows** — Trace the complete/skip/delete/reschedule
   flows from the UI (macOS bottom-bar `actionButtons`, iOS `actionCluster`,
   context menus) through `ContentViewModel` into `ReminderStore`. What are
   the method signatures, what gating applies (`ActionMenuGate`,
   `hasVisibleReminder`, etc.), and which actions are exposed on each
   platform?

3. **Appearance switching** — How is appearance mode stored, propagated, and
   applied on each platform (`AppearanceMode` enum, `@AppStorage` key,
   `MacAppDelegate.applyAppearance` vs iOS `overrideUserInterfaceStyle`)?
   Where in the settings UI is it written, and how do the macOS and iOS
   paths differ?

4. **Notification scheduling & platform gating** — Where is
   `UserNotifications` imported and used, and how is that code gated per
   platform (`#if os(iOS)` in `AppViewModel.swift`, `ContentView+iOS.swift`)?
   Trace the permission-request and scheduling flows (trigger type, keys,
   cancel behavior), the `--ui-testing-notifications` seam, and what tests
   exist for notification behavior.

5. **macOS build configuration & shared persistence** — How is the macOS
   target configured in `project.pbxproj` (`INFOPLIST_KEY_*` usage strings,
   per-SDK entitlements, `GENERATE_INFOPLIST_FILE`, macOS capabilities), and
   how does that differ from iOS? Separately, which values are stored in the
   shared app-group `UserDefaults` (`AppGroup.swift`) and how do the app,
   watch, and widget read/write them — including any background/off-main-window
   read patterns (widget timelines, `SkippedReminderSyncService`)?

6. **Platform-divergent conventions & test structure** — What are the
   established patterns for splitting iOS/macOS code (inline `#if os`,
   `+iOS`/`+macOS` files, reduced macOS `SettingsBindings`), and how do
   recent macOS tickets (settings, refresh button, wallpaper) structure
   their platform-divergent changes? How are unit tests (Swift Testing) and
   UI tests (XCTest, a11y audit, `--seed`/`--ui-testing` seams) organized,
   and what macOS-specific verification exists today?