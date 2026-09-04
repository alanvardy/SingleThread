# Task: Fix "View in Reminders"

The iOS context-menu action "View in Reminders" is supposed to open the
specific reminder in Apple's Reminders app, but it currently only lands on the
reminders list. The goal is to make the action open the actual reminder for
editing (VAR-764).

Current state: `ContentView.swift` builds a deep link via
`ReminderDeepLink.url(forReminderIdentifier:)` using the raw
`EKReminder.calendarItemIdentifier` and opens
`x-apple-reminderkit://REMCDReminder/<id>` through `@Environment(\.openURL)`.
That is the app's only outbound deep link; no URL schemes are registered in
any target's Info.plist.