# Task

Add a user-selectable "sort by" preference to the app's settings screen so
the user can choose how their reminders are ordered, instead of the single
fixed ordering (priority → due date → title) hard-coded in
`ReminderSort.areInIncreasingOrder` today. The choice must be a new persisted
preference alongside the existing appearance, text size, and toggle settings,
and it must determine which reminder is presented as the current one everywhere
that ordered list is consumed.