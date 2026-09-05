# Research Questions

## Context

Focus on the reminder-card swipe guide UI (its rendering, visibility, colors, and dismissal), the app's appearance/colour scheme system, the adaptive-color patterns used by other components, and the tests covering these areas.

## Questions

1. Trace the swipe guide UI end-to-end: which view code renders it, what controls its visibility and persistence (@AppStorage, bindings, Settings toggle), on which platforms it appears, and what exact colors it uses today (plate fill, separators, hint symbols, dismiss button) in both light and dark appearance? Include file:line references.

2. How does the app decide and propagate its appearance (system/light/dark)? Trace the flow from the appearanceMode setting through AppearanceMode type, window style overrides, and app-delegate application-lifecycle handling on each platform (iOS, macOS, watchOS), and how that reaches SwiftUI's `@Environment(\.colorScheme)`.

3. What patterns do other views and components use to adapt their colors to light/dark (e.g. `CardPlate.plateFill(for:)`, `ControlPlateModifier`, semantic/system colors, `colorScheme` conditionals, asset catalogs)? How are these adaptive helpers structured to be pure and testable, and which components currently adapt correctly?

4. When the appearance changes at runtime, how do views react (live flip vs restart-required)? Are there existing hooks or mechanisms that observe appearance/trait changes, and does `UIWindow.overrideUserInterfaceStyle` propagate to SwiftUI's colorScheme?

5. Which tests cover the swipe guide and appearance behavior today: unit tests that pin exact color values or string snapshots, UI flow tests and their launch seams (`--reset-swip-preference`, `--ui-testing`, `--seed`), and accessibility audits? Which of these would be sensitive to changing the guide's colors, and are there any existing tests that exercise light-vs-dark rendering?