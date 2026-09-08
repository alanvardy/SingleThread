# Research Questions

## Context

Focus on how the reminder card's container/background is styled and layered
over the app's root background on iOS, and how that rendering may differ
between device families. Relevant areas: the reminder card and its plate
(`SingleThread/ReminderCardView.swift`), the `List` row / scroll-content and
its background configuration in `SingleThread/ContentView.swift`, the
`backgroundDisplayed` gate in `SingleThread/ContentViewModel.swift`, the
decorative background photo layer (`SingleThread/BackgroundImageStore.swift`),
the appearance/scheme handling (`AppearanceMode.swift`, `AppDelegate.swift`,
`Color+CrossPlatform.swift`), the hardening of these seams under test
(`SingleThreadTests/BackgroundCardTests.swift`), and the `make simverify`
gate (`scripts/simverify.sh`).

## Questions

1. How is the reminder card's container rendered in `ReminderCardView.swift`?
   What is drawn behind the card text, under what conditions (the
   `showsOverPhoto` parameter), and how do the `.padding`/`.background`/
   `.fill` modifiers compose to produce the container?

2. How is the `List` configured around the reminder card in
   `ContentView.swift` — the row background (`listRowBackground`),
   `listStyle`, `scrollContentBackground`, separators, and paddings? Is there
   any code path or styling that would behave differently on iPad versus
   iPhone?

3. What does `ContentViewModel.backgroundDisplayed` gate on, and how does
   that flag flow into both the card's `showsOverPhoto` and the `List` row
   background? Under what conditions is the container expected to become
   transparent vs. opaque?

4. How do the root view's layers composite — the `Color.systemBackground`
   base, the `BackgroundPhotoLayer` (including its fade/opacity), and the
   `List` — and how does `Color.systemBackground` resolve under light vs.
   dark scheme (`Color+CrossPlatform.swift`, `AppearanceMode.swift`,
   `AppDelegate.swift`)?

5. How is the `colorScheme` / appearance mode applied and read at render
   time, and how does that interact with the card plate's light/dark fill
   chosen in `ReminderCardView.swift`?

6. How is the container/background rendering verified today — what do the
   `BackgroundCardTests` assert, why is the rendered look documented as
   manual-only, and how does the `make simverify` gate (`SimulatorManualVerification.md`)
   drive the iOS Simulator appearance checks?