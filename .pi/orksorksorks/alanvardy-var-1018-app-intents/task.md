# Task

Add three App Intents to SingleThread so users can drive the app from Siri/Shortcuts
and the app-icon long-press menu:

1. **"What's Next"** — a query intent with no side effects that returns the current next
   task using the existing prioritization logic already in `ReminderStore`.
2. **"Complete Current Task"** — re-fetches the current next task at execution time and
   marks it complete.
3. **"Skip Current Task"** — same re-fetch approach, but uses the existing skip logic
   already in the data model.

Design requirements from the ticket: always re-fetch the current item inside each intent
rather than trusting a cached value (state changes between calls); make the `ReminderStore`
safely accessible from a background / non-foregrounded context since intents run outside
the normal app lifecycle; handle the "no next task" case explicitly with a clean dialog or
result rather than crashing; and explicitly await any save operation before returning the
intent's result so a completed/skipped task isn't lost if the app is suspended right after.
Testing is expected to be manual (Shortcuts or app-icon long-press), since there is no easy
unit-test path for the Siri invocation itself.
