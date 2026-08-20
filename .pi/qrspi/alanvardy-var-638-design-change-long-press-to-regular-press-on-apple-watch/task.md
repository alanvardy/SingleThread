# Task

On the Apple Watch app, revealing the reminder's options menu (currently just
a "Refresh" action) requires a long-press on the reminder card, which drives a
`confirmationDialog`. This should be presented with a single tap instead, so
the menu is reachable by a plain tap.

The relevant code lives in `SingleThreadWatch/WatchReminderView.swift`, where
`reminderCard` attaches `.onLongPressGesture` to a `ScrollView` and flips
`@State isShowingRefreshConfirmation` to present the dialog. A regular-tap
`Button("Refresh")` already exists in the same file's empty states.