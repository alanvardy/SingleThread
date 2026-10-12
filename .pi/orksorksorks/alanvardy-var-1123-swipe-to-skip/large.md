# Task

VAR-1123 "Swipe to skip": swiping a reminder should present a menu (Skip /
Schedule / Delete) instead of skipping directly, and the swipe-revealed
action label currently reading "Skip" should be renamed "More" — with that
"More" menu presenting the same Skip / Schedule / Delete choices. The change
must hold across the existing multi-platform action paths (iOS bottom bar +
swipe reveal, macOS action cluster, and the watch's swipe/action surface) and
keep their shared gating and localized strings consistent.

## Why LARGE

Matched triggers: CONVENTION_RISK, DESIGN_SIGN-OFF, CROSS_CUTTING, MULTI_MODULE, BROAD_TEST_SURFACE.

Decisive signal: the swipe outcome is decided by shared cross-platform code
(`ActionMenuGate` in `SingleThreadCore`, consumed identically by iOS, macOS,
and watch) and surfaced through shared localized strings, yet the ticket
leaves two design decisions open — what "a menu in the middle" actually is
(the existing `confirmationDialog` vs a custom centered menu) and whether the
existing `enableActionButtons` toggle still gates the new swipe behavior —
so this needs research/design before a plan, not a one-pass edit.
