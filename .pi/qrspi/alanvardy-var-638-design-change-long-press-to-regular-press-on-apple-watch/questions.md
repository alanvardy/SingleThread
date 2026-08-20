# Research Questions

## Context

Focus on the Apple Watch app view layer (`SingleThreadWatch/`), the SwiftUI
view-descriptor DSL it uses for gestures, buttons, and modals, the Xcode
build/test targets and CI scripts for the watchOS app, and the accessibility
and SwiftLint conventions that apply to interactive controls. Compare against
the iOS app (`SingleThread/ContentView.swift`) where relevant patterns exist.

## Questions

1. Which user-interaction and modal APIs does the watchOS SwiftUI DSL provide
   (tap gestures, long-press gestures, buttons, confirmation dialogs, context
   menus, sheets), and where are each used across `SingleThreadWatch/` and
   `SingleThread/`?

2. How is the watch reminder view composed in `WatchReminderView.swift` — how
   are the reminder card, its scroll region, the state-managed gesture handler,
   and the Complete / Skip / Refresh buttons laid out and wired together?

3. How is the Apple Watch app target built and verified: which Xcode schemes /
   simulator destinations, build and test targets, and CI / `scripts/test.sh`
   paths cover the watchOS app, and what (if any) interaction-level test
   coverage exercises its views?

4. What accessibility and lint conventions apply to interactive watch controls:
   which SwiftLint rules (`accessibility_label_for_image`,
   `accessibility_trait_for_button`), `.accessibilityLabel` /
   `.accessibilityAddTraits` usages, and UI accessibility audit checks exist,
   and do the existing watch action buttons satisfy them?