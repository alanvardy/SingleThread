# Research Questions

## Context
The app is a reminders-focused SwiftUI client spanning an iOS app, a watchOS app,
and a widget extension, with shared model logic in the `SingleThreadCore` package.
The iOS app presents reminders one at a time from a store that fetches via
EventKit and computes a visible, ordered list, while user preferences are declared
and toggled from a settings screen. This research explores how preferences are
declared and persisted, how reminders are fetched and filtered by date, how the
visible list is derived, and how the watch and widget surfaces consume the same
store.

## Questions
1. What user preferences does the settings screen currently expose, and exactly
   how is each one represented — where is its `@AppStorage` state declared, what
   key and default value does it use, and how is the value bound into the
   settings view (init parameters, iOS-only vs. shared across platforms)?

2. How does `ReminderStore` load reminders from EventKit, and what due-date
   window does the fetch predicate use? Which reminders — timed, all-day, or
   those with no due date — does the current fetch actually return?

3. How is `visibleReminders` computed from the fetched reminders — what skip
   filtering is applied, and what ordering does `ReminderSort` impose? Where do
   reminders with a nil `dueDateComponents` land in that ordering relative to
   dated reminders?

4. How do the watch app and the widget extension each obtain and display the
   current reminder, and what state do they share with the phone app (e.g. App
   Group `UserDefaults`, WatchConnectivity payloads) versus what they compute
   independently?

5. What testing and preview conventions apply to settings and reminder display —
   which unit-test fixtures, store-seeding initializers, and UI/accessibility
   audit tests exist, and how are preference-related changes currently validated?