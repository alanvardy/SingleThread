# Research Questions

## Context

An iOS app shows a single reminder card with an action menu that opens a deep
link into Apple's Reminders app. The deep link is constructed in the app
target (`SingleThread/ContentView.swift`) and handed to a URL builder in the
shared `SingleThreadCore` package; reminders themselves come from EventKit via
a `ReminderStore` that holds raw `EKReminder` objects. There is no app-side
URL-scheme registration, and the deep-link's behavior depends on how Apple's
Reminders app resolves the URL.

Focus areas: `SingleThread/ContentView.swift` (card + context menu),
`SingleThreadCore/Sources/SingleThreadCore/ReminderDeepLink.swift`,
`ReminderStore.swift`, `ReminderDisplay.swift`, the `EventKitStoring`/
`InMemoryEventStore` test seams, and `SingleThreadTests` /
`SingleThreadUITests`.

## Questions

1. Trace the deep-link flow from the iOS context-menu button to the opened
   URL: where is the button, which `EKReminder` property supplies the
   identifier, what URL string is produced, and what happens with the result
   of `openURL`? Include the deep-link builder's unit tests and any
   localization keys used by the menu item.

2. What identifier properties does `EKReminder` expose
   (`calendarItemIdentifier`, `reminderIdentifier`,
   `calendarItemExternalIdentifier`, …) and what are their documented
   semantics and stability guarantees? Where does the codebase currently use
   each, and which one(s) survive a fetch/reload cycle unchanged?

3. What is known about the URL schemes Apple's Reminders app accepts to open
   an individual reminder for editing — in particular the
   `x-apple-reminderkit://REMCDReminder/<id>` scheme: what identifier format
   does it expect in the path, does it require any additional URL structure,
   and how does Reminders behave (list vs. specific reminder) when the given
   identifier does not resolve? Look for documented, community, and
   reverse-engineered evidence; note whether the scheme works on both
   simulator and device and which iOS versions support it.

4. How can URL-opening behavior be asserted in this project's tests? Map
   existing test seams: how the context menu / swipe actions are exercised in
   `SingleThreadUITests` (e.g. the delete-via-context-menu test), whether any
   infrastructure exists to intercept or mock `openURL` /
   `@Environment(\.openURL)`, and which unit tests cover the deep-link
   builder today.

5. How is a reminder represented between the data and view layers? Trace how
   `EKReminder` becomes `ReminderDisplay`, what fields that struct carries,
   and how the identifier currently flows (or doesn't) into views, the
   widget, and the watch app. Note any places where a raw `EKReminder` is
   still reached into directly from SwiftUI views.