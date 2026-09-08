# Task

Polish the clunky reminder reschedule dialog: place the "Reschedule to" label
and the date picker next to each other and centered, and restyle the
"Reschedule" confirm button underneath to match the app's other buttons and
center it. The reschedule dialog exists as parallel implementations on both iOS
(`SingleThread/RescheduleSheet.swift`, used by the skip-nudge sheet and the
action menu) and watchOS (`SingleThreadWatch/WatchReminderView.swift`
`actionMenuRescheduleSheet`); the ticket does not say which — or whether both —
is in scope.