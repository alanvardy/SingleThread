# VAR-750 — Do a refetch for reminders after skip and completion

When reminders are completed on multiple devices at once, a single reminder can
end up completed twice under the current system. To prevent this, the app
should re-fetch reminders from the EventKit store after every completion and
skip action, and drop any reminders from the in-memory list that have already
been completed. This guarantees the shown list is always reconciled against
the store, regardless of which device performed the action.