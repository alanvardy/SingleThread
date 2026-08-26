# Research Questions

## Context

Focus on how a reminder's title and notes flow from an `EKReminder` through to
rendered SwiftUI views across the three display surfaces: the iOS app
(`SingleThread/ReminderCardView.swift`, `SingleThread/ContentView.swift`), the
watch app (`SingleThreadWatch/WatchReminderView.swift`), and the widget
(`SingleThreadWidget/NextThingWidget.swift`). The display model
(`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`) and the
note-string formatter
(`SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift` —
`ReminderNotesFormatter`) sit between the store and these views. Also relevant
are the unit tests that snapshot rendered card content and the UI-test /
accessibility seams.

## Questions

1. Trace how a reminder's `title` and `notes` flow from an `EKReminder` through
   `ReminderDisplay` and `ReminderNotesFormatter` into the `Text` views in the
   iOS card, watch view, and widget. Which representation is passed to `Text`
   (`String` vs `AttributedString`), and how is each absent/present value
   handled?

2. How does `Text`/SwiftUI currently style the title, notes, and any
   multi-line content on each surface? What font, line-limit (`lineLimit`),
   spacing, and foreground modifiers are applied, and how does that styling
   differ between iOS, watch, and widget?

3. What existing text-processing/formatting lives in `SingleThreadCore`
   (e.g. `ReminderNotesFormatter`, `ReminderPriority`, `ReminderRecurrenceFormatter`)
   — what does each transform, and are there any existing uses of
   `AttributedString`, Markdown parsing, `monospaced` fonts, or string escaping
   / sanitization anywhere in the sources?

4. How are title/notes rendering asserted today in `SingleThreadTests` — e.g.
   the `String(describing:)` snapshot approach in `ShowDateTests` /
   `ShowRecurrenceTests` / `ShowAlarmsTests`? Do any unit tests format or parse
   raw reminder note/title strings, and are there formatter-only tests of
   `ReminderNotesFormatter`?

5. How do the iOS UI tests (`SingleThreadUITests`) and the accessibility
   audit (`performAccessibilityAudit`, `ReminderCardView`'s
   `.accessibilityElement(children: .combine)`) observe rendered title/notes,
   and what constraints (line limits, VoiceOver combining, hit-region checks)
   could be affected by changes to how notes or titles are rendered?