# Research Questions

## Context
Focus on the SingleThreadCore package's EventKit integration and value-mapping layer, the three UI surfaces that render reminders (iOS app, watchOS app, widget extension), the App Group–backed preferences system and its Settings UI, the WatchConnectivity sync path for preferences, and the existing unit/UI test suites around these areas.

## Questions
1. Which properties does `EKReminder` expose through EventKit (e.g. `url`, `recurrenceRules`, `alarms`, `attachments`, `completionDate`, `creationDate`, `location`, `isCompleted`, calendar membership), which of them are currently read anywhere in the codebase, and where?
2. How does data flow from `EKReminder` through `ReminderDisplay` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`) to each rendering surface — `ReminderCardView` (iOS), `WatchReminderView` (watchOS), and `NextThingWidgetView` (widget)? Trace the construction sites and the parameters each view receives.
3. How do the existing preference types work end to end — `ShowDatePreference`, `ShowListPreference`, `ShowUndatedRemindersPreference`, `SortOptionStore`, `ExcludedListStore` — including their defaults-key names, default values, storage backing (`AppGroup.defaults`), and where each is read on iOS, watchOS, and widget?
4. How is the iOS Settings screen (`SettingsView.swift`) organized, how are its toggles bound in `ContentView.swift` via `@AppStorage`, and what side effects occur on toggle changes (e.g. `WidgetCenter.reloadAllTimelines`)?
5. How do preferences propagate from iPhone to Apple Watch over WatchConnectivity — what roles do `SkippedReminderSyncService`, `ShowDateState`, and `onShowDateReceived` play — and what would a new synced preference need to hook into?
6. How are these areas tested today — `ReminderDisplayTests`, `ShowDateTests`, `ShowDatePreferenceTests`, `SettingsViewTests`, `EventKitStoringTests` (fake store / `--seed` seam), and `SingleThreadWatchTests/WatchSyncPipelineTests` — and what patterns exist for adding coverage for new mapped fields and new toggles?
