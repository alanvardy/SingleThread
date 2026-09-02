# Task: Extract shared card-plate styling from ReminderCardView

The card-plate pattern — `RoundedRectangle(cornerRadius: 10)` + adaptive fill + a 12pt padding pair — is duplicated twice inside `ReminderCardView.swift`, and the iOS empty states use their own plate (currently `EmptyStateCard` in `ContentView.swift`) that back-references `ReminderCardView`'s static constants.

Extract the card-plate pattern into a single shared `ViewModifier` or `View` extension so it is defined once and reused across all plate sites: the populated card text plate, the swipe-prompt box, and the empty states. Spun off from VAR-751 (design decision 4).