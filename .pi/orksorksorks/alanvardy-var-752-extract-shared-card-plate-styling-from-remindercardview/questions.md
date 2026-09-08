# Research Questions

## Context

The SingleThread app draws rounded-rectangle "plate" surfaces in two files: `SingleThread/ReminderCardView.swift` (two plate sites with different fills and paddings) and `SingleThread/ContentView.swift` (empty-state plates). The styling seams are exposed as static constants on `ReminderCardView` that other views and test files reference. The app target compiles for both iOS and macOS under Swift 6 with MainActor default isolation; the watch and widget targets build their own separate view stacks.

## Questions

1. How does `ReminderCardView` draw its two card plates? Trace the full view-modifier chains in `body` and `prompt`, quoting the exact `RoundedRectangle`/`fill`/`padding` chains, the static `plateCornerRadius` / `plateFill(for:)` / `promptBoxFill` constants, and how the `+12/−12` padding pair in `body` differs from the prompt box's `frame(maxWidth: .infinity)` + no-restore approach.

2. How do the iOS empty states in `ContentView.swift` (`EmptyStateCard` and its `reminderList` call sites) draw their plate, and what is the dependency relationship between that styling and `ReminderCardView`'s static constants (which constants are referenced, from which line)?

3. What shared view-styling infrastructure already exists in the `SingleThread` target — `ViewModifier` definitions (`ControlPlateModifier`, `TextSizeModifier`), `View` extensions, `Color`/`ShapeStyle` extensions (`Color+CrossPlatform`) — and what conventions do they follow (naming, `#if os(macOS)` guards, color spellings, default-parameter style, documentation comments)?

4. Which test files pin the card-plate styling seams, and what exactly do they assert? Enumerate each reference to `plateCornerRadius`, `plateFill`, `promptBoxFill`, or plate-related view behavior in `SingleThreadTests/` with file:line and the asserted values.

5. How do the `SingleThread` (iOS/macOS), `SingleThreadWatch`, and `SingleThreadWidget` targets share code today, and what build rules constrain where SwiftUI view code can live and how it must be written (`SWIFT_DEFAULT_ACTOR_ISOLATION`, Swift 6 language mode, `SUPPORTED_PLATFORMS`, SPM package boundaries, `SingleThreadCore`'s current lack of SwiftUI imports)?

6. Across the `SingleThread` target, what distinct plate-like background surfaces exist (rounded rectangles, capsules, circles, materials) — where, with what corner radius, fill, and padding — and which parameters overlap versus differ between them?