# Research Questions

## Context
Focus on the multi-platform reminder action surfaces of this SwiftUI app:
the shared `SingleThreadCore` package (swipe decision logic, action-menu
gating, shared localized strings and their String Catalog), the iOS app
(Content view, swipe modifier, action-menu modifier), the macOS action
cluster, and the watchOS reminder view. Also cover the unit/UI test suites
that exercise these paths, and the accessibility seams they expose. Describe
what exists; do not suggest improvements or propose solutions.

## Questions
1. How does the swipe gesture pipeline work end to end — how a drag offset is
   converted into a `SwipeGestureOutcome`, how the reveal panel chooses its
   label/symbol/alignment, and how the resulting outcome is dispatched by the
   iOS rem and by any other platform that consumes the same shared logic?
2. How is the Skip / Schedule (Reschedule) / Delete action menu currently
   constructed and presented on each platform (iOS confirmationDialog, macOS
   action cluster, watchOS confirmationDialog), including the button order,
   roles, IDs, and the shared reschedule sheet?
3. How do `ActionMenuGate`, `enableActionButtons`, and `showsActionButtons`
   interact to gate the action surfaces — where each is stored/read, how the
   value reaches iOS/macOS/watch, and how the watch's inline gate differs from
   the shared enum?
4. How are the user-facing action strings (`SharedStrings.*`, "Reschedule",
   swipe labels) declared, consumed, and stored in the String Catalogs, and
   what conventions exist for adding, renaming, or localizing such keys
   (including the test fixtures a key must join)?
5. What test coverage exists for these paths — the unit suites for swipe
   decisions, reveal panel labels, action-menu gating, the enable toggle and
   its migration/sync, plus the UI tests that drive swipe and button flows —
   and what does each assert?
6. What accessibility seams exist on the swipe and action surfaces —
   `accessibilityAction`s, a11y labels/identifiers, button traits, hit-region
   padding — and how do the accessibility audits in the UI tests exercise
   them?