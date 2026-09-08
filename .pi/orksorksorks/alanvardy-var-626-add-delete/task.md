# Task

Give the user a way to permanently remove a reminder from the SingleThread app
(VAR-626, "Add delete"). Today the app can only complete a reminder (mark it
done in EventKit) or skip it (hide it via a persisted skip list); there is no
way to get rid of a reminder entirely. Delete must remove the reminder from
EventKit so it disappears everywhere the reminder is shown, follow the
existing conventions for destructive actions and accessibility on every
surface, and be covered by unit tests like other reminder mutations.