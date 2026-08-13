# Task

SingleThread should surface the user's Reminders inside its main list, so the day's actionable reminders are visible in one place. Only reminders that are overdue or due today should be displayed.

The app currently shows only locally stored `Item` records (a timestamp) in a SwiftData-backed list, so this requires integrating a new data source and filtering it by due date.
