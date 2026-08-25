# Task — VAR-691: Add the other reminder attributes

The app currently surfaces only a subset of reminder attributes (title, notes, due date, priority marker, list name). Other attributes available through EventKit (e.g. tags, URL, recurrence, alarms) are not represented anywhere in the model or UI.

Goal:
- Inventory everything accessible via the internal (EventKit) API and add the remaining attributes to the reminder representation.
- Add settings toggles so each newly surfaced attribute can be disabled by the user.

Ticket: https://linear.app/vardy/issue/VAR-691/add-the-other-reminder-attributes
