# Task

Fix "Reschedule not working on watch" (VAR-978): rescheduling a reminder on watchOS visibly does nothing. The ticket asks to describe the reschedule code path and troubleshoot why — the path runs watch UI (`WatchReminderViewModel` sheet) → `WatchAppViewModel` wiring of `ReminderStore.onRescheduleReminder` → `SkippedReminderSyncService.requestRescheduleReminder` WatchConnectivity relay → iPhone side `onRescheduleReminderReceived` → `ReminderStore.rescheduleReminder` EventKit write. Find the broken link, fix it without regressing the phone, and ship a red-first unit test that reproduces the reported symptom.

## Why LARGE

UNKNOWNS + CROSS_CUTTING + CONVENTION_RISK — the root cause is unknown (the ticket is a diagnostic, and the fix site could be any of ~4 layers in the chain), the path spans watch UI / sync contract / shared core store / iPhone EventKit persistence across two platform targets with no proven end-to-end pattern, and it touches the central `ReminderStore` shared by iOS/watch/macOS plus WatchConnectivity/App Group conventions, where a fix must preserve phone behavior and the `AppGroup.defaults` round-trip rule.