# Task — Clear stale reminders

The iOS/macOS app, watchOS app, and widget each surface a single "current"
Apple Reminder at a time. Today, nothing notices when that reminder is
completed or deleted elsewhere (on another device, or directly in Apple
Reminders) until the user manually refreshes. This ticket adds a periodic
re-check on all platforms so that when the currently displayed reminder is
no longer incomplete, the app immediately advances to the next one.