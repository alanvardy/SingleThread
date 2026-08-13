# Task

SingleThread should show exactly one reminder at a time — centered on screen — instead of the current list of all overdue/due-today reminders. A "Complete" button at the bottom marks that reminder as completed, and completing it advances to the next overdue/due-today reminder.

This delivers the app's single-task focus: the user sees one actionable reminder, completes it, and the next one appears. Completion must write back to the system Reminders store via EventKit so the change persists.
