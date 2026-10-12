# Task

VAR-1123 "Swipe to skip": swiping a reminder should present a menu (Skip /
Schedule / Delete) rather than skipping directly, and the swipe-revealed
action label currently reading "Skip" should be renamed "More", with that
"More" menu presenting the same Skip / Schedule / Delete choices.

The behavior must remain consistent across the existing multi-platform action
paths (iOS bottom bar + swipe reveal, macOS action cluster, and the watch
swipe/action surface), keeping their shared gating and localized strings in
sync. Two design decisions are open: what "a menu in the middle" is (the
existing `confirmationDialog` vs a custom centered menu) and whether the
existing `enableActionButtons` toggle still gates the new swipe behavior.