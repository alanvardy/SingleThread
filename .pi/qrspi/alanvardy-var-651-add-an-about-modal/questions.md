# Research Questions

## Context

Focus on the main app target's Settings screen and how it is presented and
structured, the watch target's user-facing surface, how app identity metadata
and author attribution content are configured and rendered, the presentation
and outbound-link primitives the codebase already uses, and how settings-related
UI and view-model behavior are covered by tests. Relevant sources include
`SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`, the
`SingleThreadCore` package, `SingleThreadWatch/`, and `SingleThreadTests` /
`SingleThreadUITests`.

## Questions

1. How is the Settings screen structured and presented from the main view? Trace
   the gear-button flow in `ContentView`: what modal/presentation and navigation
   containers are used (`.sheet`, `NavigationStack`, `Form`), how the Settings
   `Form` is organized into sections, footer labels, and toolbar items, and how
   the Settings view's `init`/layout diverges between the iOS and macOS builds
   (`#if os(...)`).

2. How does the watchOS target surface secondary UI or settings today, if at all?
   Does `WatchReminderView` or `WatchAppViewModel` present any sheet/modal/settings
   or menu surface, and how does the watch app's available feature surface differ
   from the main app target?

3. How is app identity metadata (display name, `MARKETING_VERSION`,
   `CURRENT_PROJECT_VERSION`, `GENERATE_INFOPLIST_FILE`) configured, and is
   `Bundle`/`Info.plist` metadata read anywhere in the codebase? Separately, how
   does the app currently model author attribution / copyright / credit content —
   for example the "Photo by … on Unsplash" `Link` in the Settings footer and how
   `BackgroundImageStore` supplies that credit.

4. What presentation and outbound-link primitives does the codebase use, and where?
   Catalog the use of `.sheet`, `Link`, `@Environment(\.openURL)`,
   `confirmationDialog`/menus, and the styling/accessibility helpers they're combined
   with (e.g. `controlPlate`, accessibility labels/traits), so the prevailing
   conventions for a new presented surface and any external link are clear.

5. How are settings-related changes tested? What does `SettingsViewTests` assert and
   how does it inspect `view.body`? How does the `--seed '…'` launch-arg seam drive
   the end-to-end settings flow (including engaging the gear button)? How do the
   `SettingsVM`-related tests and existing tests use `#if os` guards for platform
   divergence?