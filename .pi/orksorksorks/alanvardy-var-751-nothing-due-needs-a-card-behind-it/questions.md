# Research Questions

## Context

The SingleThread app shows several different content states on its reminder
surface across three targets: the iOS app (`SingleThread/ContentView.swift`, which
renders one of several branches depending on store state), the watchOS app
(`SingleThreadWatch/WatchReminderView.swift`), and the widget
(`SingleThreadWidget/NextThingWidget.swift`). Each state renders text over a
background, and one state ("Nothing due") is currently plain white text on the
background while other states sit on a plate/card surface. Investigate how these
states are structured, styled, and tested today, across all three targets.

## Questions

1. **Store-driven state branching (iOS app):** Trace how `ContentView` decides
   which state to render (`authGatedContent` vs `reminderList`, and within
   `reminderList`: the `allSkipped` "All Done" branch, the `reminders.isEmpty`
   empty branch, and the populated `List`). What store properties drive these
   decisions (`allSkipped`, `hasHidden`, `reminders.isEmpty`, `authorizationStatus`)
   and how are they computed in `SingleThreadCore`'s `ReminderStore`? How is each
   branch laid out (ScrollView / GeometryReader / bottomBar composition, refreshable)?

2. **Card/plate visual surface (iOS app):** How exactly is the reminder card's
   plate rendered in `ReminderCardView.swift` — the `plateFill` color logic, corner
   radius, the `padding(12)`/`padding(-12)` geometry trick, and `@Environment(\.colorScheme)`
   handling? What other plate-like surfaces exist on iOS (`ControlPlateModifier`,
   `promptBoxFill`, `Color+CrossPlatform.swift` helpers), and is any of this
   styling shared/extracted or duplicated per-view?

3. **Empty & reminder states on the watch:** How does `WatchReminderView.swift`
   render its states — the `noRemindersState`, `allDoneState`, auth-denied state,
   and the populated `reminderCard`? What styling (colors, plates, fonts) does each
   use, and how do the watch's surfaces differ from iOS's card look?

4. **Empty & reminder states on the widget:** How does `NextThingWidget.swift`
   render its states — the shared `messageView` for `.noAccess`, `.empty(hasHidden)`,
   `.allDone`, and the populated reminder view? What backgrounds/plates do widget
   container and content use (`containerBackground`, fills)?

5. **Testing & assertion seams for visual decisions:** What patterns do
   `SingleThreadTests/` and `SingleThreadUITests/` use to assert empty-state
   rendering and visual/layout decisions — the extracted static constants/functions
   (`plateFill`, `promptBoxFill`, `EmptyStateCopy` factory, `rowChromeBackground`),
   string-snapshot tests, UI tests asserting `staticTexts`, and the accessibility
   audit? Which seams exist for asserting that a visual element (like a background
   plate) is or isn't present behind a given view?