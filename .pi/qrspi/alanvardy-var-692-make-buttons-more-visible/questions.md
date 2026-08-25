# Research Questions

## Context

Focus on the iOS app's user-facing controls and how they are styled and layered
over the app's background. Relevant areas: the main view's bottom action bar and
top-right controls in `SingleThread/ContentView.swift`, the decorative
background photo layer in `SingleThread/BackgroundImageStore.swift`, the
appearance/scheme handling (`AppearanceMode.swift`, `AppDelegate.swift`), the
shared cross-platform color symbol in `Color+CrossPlatform.swift`, the reminder
card's photo-plate styling in `ReminderCardView.swift`, the watch app's action
buttons in `SingleThreadWatch/WatchReminderView.swift`, and the iOS
accessibility-audit UI tests in `SingleThreadUITests/`.

## Questions

1. How are the microphone button, the recording indicator, and the creation
   feedback icons rendered in `ContentView.swift`'s bottom bar — what fills,
   glyph foreground colors, frame sizes, shadows, and adaptive colors do they
   use, and how are they layered over the rest of the view?

2. How is the settings (gear) button in the top-trailing overlay rendered —
   what foreground style, tint, sizing, and hit-target frame does it use, and
   does it have any fill or background of its own?

3. How does the app currently determine and apply its appearance (light vs.
   dark) via `AppearanceMode` and `AppDelegate.applyAppearance`, and how do
   views read the effective scheme at render time? What existing patterns (for
   example the `showsOverPhoto` reminder-card plate) switch a control's color
   based on the active color scheme?

4. How does the background photo layer (`BackgroundPhotoLayer`) render and
   composite over the view, including its fade/opacity and its relationship to
   the system background color (`Color.systemBackground`)? Where does the
   "blue background" that obscures the controls come from?

5. How are the iOS Complete and Skip action buttons constructed in
   `ContentView.swift`'s action cluster — their styling, placement relative to
   the mic button, tint colors, icon-only labels, and the conditions under which
   they appear?

6. How do the watch app's action buttons in `WatchReminderView.swift` style
   their Complete/Skip controls, since that styling was the stated reference for
   the iOS action buttons?

7. How do the iOS UI tests (especially the accessibility audit in
   `SingleThreadUITests`, and `ActionButtonsUITests.swift`) inspect, interact
   with, and assert on these controls, and what launch-arg/seed seams are
   available to drive deterministic UI tests of the bottom bar?