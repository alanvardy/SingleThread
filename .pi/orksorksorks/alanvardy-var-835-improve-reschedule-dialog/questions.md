# Research Questions

## Context

UI construction, presentation, styling conventions, and test coverage in the
SingleThread iOS app, the watchOS app, and their test suites. Focus areas: the
reminder reschedule sheets on both platforms, the SwiftUI components they use
(labels, date pickers, buttons, layout containers), and the sheet/action-menu
infrastructure that presents them.

## Questions

1. How is the iOS reschedule sheet (`SingleThread/RescheduleSheet.swift`)
   constructed and presented? Trace its layout structure (containers, label,
   date picker, button), its two call sites (`ContentView+iOS.swift` nudge
   flow and `ContentView+ActionMenu.swift` action-menu flow), and the sheet
   presentation mechanics that wrap it.

2. How is the watchOS reschedule sheet constructed and presented? Trace
   `SingleThreadWatch/WatchReminderView.swift` `actionMenuRescheduleSheet`
   (its containers, date picker, button, toolbar), its placement inside
   `reminderCard`, and the view-model state that drives it
   (`WatchReminderViewModel`).

3. What button and label styling conventions exist across the iOS app?
   Survey how other sheets and dialogs style confirm buttons and labels
   (buttonStyle variants, tint, roles, label construction) and how layouts
   are centered or aligned, with concrete `file:line` examples.

4. What button and label styling conventions exist across the watchOS app?
   Survey how buttons and labels are constructed and styled in
   `SingleThreadWatch` (plain buttons, roles, any tint/emphasis variants)
   and how layouts are aligned or centered, with concrete `file:line`
   examples.

5. What is the observed API surface and layout behavior of the
   `EventKit.DatePicker` component used on both platforms? Enumerate every
   usage site in the repo, what they reveal about its constructor/options
   (label, selection binding, displayedComponents), and whether its source
   or any layout documentation exists in the repo or local dependencies.

6. What test coverage exists for the two reschedule sheets on iOS and
   watchOS? Inventory the unit and UI tests that touch reschedule UI (what
   they assert, how they construct the view under test) and the
   infrastructure patterns used to assert on SwiftUI view structure and
   accessibility.