# Research Questions

## Context
This is a small SwiftUI app (iOS and macOS) that reads the user's Reminders via EventKit. The main sources are `ContentView.swift` (rendering and layout), `ReminderStore.swift` (EventKit fetch plus access-status state), and `ReminderFilter.swift` (a pure due-date classifier). Unit tests cover only the classifier; UI tests are a boilerplate scaffold. Focus your investigation on these files and the surrounding SwiftUI/EventKit patterns.

## Questions
1. Trace the flow of reminder data from EventKit to the screen: where are reminders fetched, filtered, sorted, and rendered, and what happens at each step?
2. What EventKit APIs does the codebase use for reading reminders, and what capabilities exist for mutating a reminder (e.g. marking it complete and saving changes back to the store)?
3. How is the order in which reminders are presented determined, and is there any existing notion of a "current" or "first" reminder?
4. How does SwiftUI state and observation work in this app — which object is observed, how is it injected, and what causes the view to re-render when data changes?
5. How is the UI laid out across iOS and macOS (list, navigation wrapper, empty states), and what layout primitives are in use for centering content and placing controls?
6. How is the app tested — what do the unit tests cover, what does the UI-test scaffold do, and which components are pure versus coupled to EventKit or the view layer?
