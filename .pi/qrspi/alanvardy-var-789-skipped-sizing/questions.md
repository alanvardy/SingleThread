# Research Questions

## Context

Two areas of the codebase are in scope: the iOS reminder list and card rendering in `SingleThread/` (row layout in `ContentView.swift`, card plate styling in `ReminderCardView.swift`/`CardPlate.swift`, sheet presentations), and skip-count persistence in `SingleThreadCore/` (`SkipCountStore`, `ReminderStore`). Focus on how these components are currently sized, laid out, and tested on iPhone vs iPad.

## Questions

1. **Reminder card width flow** — Trace how a reminder card's width is determined in the list: from the `List` row in `ContentView.swift` through the `.cardPlate` modifier to `ReminderCardView`. What frames, paddings, and alignment modifiers are at play, and is there any stretch-to-full-width mechanism on the plate or its subcomponents?

2. **Skip-count data flow** — How is the skip count persisted and surfaced? Where do the "Skipped X times" nudge label and its threshold come from, and is the displayed text static or derived from the stored count?

3. **Sheet sizing on iPad vs iPhone** — How are the sheet presentations (the post-skip management sheet and the reschedule sheet) sized on iPad versus iPhone? What presentation styles, detents, containers (`NavigationStack`, `VStack` frames), and content-alignment modifiers control their dimensions, and what would make one display with large blank areas above/below its content?

4. **Adaptive layout patterns** — What existing patterns in the codebase handle iPad vs iPhone differences in card sizing (e.g. `EmptyStateCard.maxContentWidth`, size-class checks, content-hugging plus centering)? Which of these are applied to the reminder card versus the empty/all-done states, and which are not?

5. **Test coverage and seams for card/nudge flows** — Which unit and UI tests currently cover the reminder card layout, the skip-nudge banner, and the sheets that follow a skip? What deterministic launch seams (`--seed`, `--ui-testing`) exist to drive these flows, and do any tests assert on iPad-specific layout?