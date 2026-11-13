# Task

On the iOS main screen, convert the three bottom-center icons (complete / mic / skip) and the floating settings gear into proper SwiftUI toolbars following Apple's HIG, and support a vertical toolbar layout when the app is shown on an "iPhone Duo" external screen. The work must not regress macOS (which shares the action-button chrome) or the existing accessibility/reflection tests.

# Why LARGE

Matched triggers: **NEW_SURFACE + UNKNOWNS + CONVENTION_RISK**. External-display support is entirely greenfield (no `UIScene` external scene, no scene-manifest config, no runtime duo/external handling anywhere — "iPhone Duo" appears only as a physical CI test device), the ticket's external-screen intent is ambiguous and would need research/spike, and the change touches shared chrome helpers (`controlPlate`, `singleThreadButton`) with cross-platform (iOS/macOS) and test-surface consequences.
