# Research Questions

## Context

Focus on the SingleThread iOS/macOS app (single `SingleThread` target), the
watchOS app (`SingleThreadWatch`), and the `SingleThreadCore` package.
Research centers on the settings architecture (the "Interface" section of
`SettingsView` and how toggle preferences are stored and synced to the watch),
the per-reminder action affordances (skip/complete/delete) on each platform,
the `ReminderStore` state-change operations behind those actions, the
multi-option menu/confirmation presentation patterns currently in use, and the
UI-test seams (`--seed`, `--ui-testing`) used to exercise these flows.

## Questions

1. **How are toggle-style settings wired end-to-end, and which current toggles
   are the closest exemplars?** Trace the "Interface" section of
   `SingleThread/SettingsView.swift` and `InterfaceSettingsView.swift`: the
   `@AppStorage` keys in `SingleThread/ContentView.swift` (e.g.
   `enableActionButtons`, `showCompletionGlow`, `showDate`, and which live in
   `UserDefaults.standard` vs `AppGroup.defaults`), the typed preference
   structs in `SingleThreadCore` (e.g. `ShowCompletionGlowPreference`), the
   `SettingsBindings` snapshot bag + writeback chain
   (`SingleThread/SettingsBindings.swift`, `ContentView+Settings.swift`), and
   how each toggle's `.onChange` triggers side effects (e.g.
   `SettingsViewModel`, `WidgetCenter.reloadAllTimelines()`).

2. **How do iOS/macOS-side preference changes reach the watch?** Trace
   `AppViewModel.setupSyncObservation` / `handlePreferencesChanged()` observing
   `AppGroup.defaults` `didChangeNotification`, the push side of
   `SkippedReminderSyncService` (`pushAll()`, `PayloadKey.*` strings), and the
   receive side (`Apply()` persisting values, `Show*State` `@Observable`
   holders in `SingleThreadWatch`, `WatchAppViewModel.wireStateReceiveHooks`).
   Which preferences are watch-relevant today, and what are the launch-arg
   seams (`--ui-testing-glow` etc.) that simulate a preference being on or off
   when the watch runs standalone?

3. **Where is the skip action surfaced on each platform, and how is it
   gated?** Inventory every skip affordance: iOS bottom-bar cluster + trailing
   swipe (`SingleThread/ContentView.swift`), the macOS action bar, the watch
   button (`SingleThreadWatch/WatchReminderView.swift`), the widget intent
   (`SingleThreadWidget/NextThingWidget.swift`), and the skip-nudge banner.
   Note each one's gating conditions (`showsActionButtons`,
   `canMutate`, entitlement checks), accessibility identifiers/labels, and
   which platforms have no skip surface at all — plus how the same affordances
   are styled for iPad vs iPhone.

4. **What do the three state-change operations look like in `ReminderStore`,
   and what platform constraints apply?** Trace `skipCurrentReminder()`
   (incl. the skip-count nudge threshold in `SkipCountStore`),
   `rescheduleReminder(identifier:to:)` (incl. its `#if os(watchOS)` branch
   and the nudge-sheet `DatePicker` flow in `SingleThread/ContentView+iOS.swift`,
   including how date-only vs dated reminders are handled), and
   `deleteReminder(identifier:)` (incl. the watch-side local removal + relay
   via `onDeleteReminder`/`SkippedReminderSyncService`). Capture signatures,
   EventKit write patterns, side effects (skip-count reset, settle/reload,
   completion counter, undo store), and error/entitlement gating.

5. **What multi-option action-presentation patterns exist today, and what are
   the platform constraints?** Survey the SwiftUI patterns in use across
   targets: `confirmationDialog` (watch only), `contextMenu` (iOS card),
   sheets, and `Picker`/`Menu` usages. Note per-platform constraints that
   matter for presenting 2–3 actions from a single control — e.g. watchOS
   dialog affordances and how tests interact with them (labels vs
   accessibility identifiers), destructive-role styling, and whether any
   pattern exists on macOS.

6. **How are these flows tested, and what seams exist for toggles, skip,
   reschedule, and delete?** Trace the iOS `--seed '<json>'` seam
   (`UITestingSeed`, `InMemoryEventStore`) and the `--ui-testing` seams on both
   iOS and watch, including which launch args force `enableActionButtons`.
   Locate the existing UI tests for skip, skip-nudge (reschedule/delete), and
   delete (iOS `SingleThreadUITests/`, watch `SingleThreadWatchUITests/`), the
   `flipToggle`/`assertToggilePersists` helpers, and the unit tests for the
   preference structs and `ReminderStore` operations. Note how a settings
   toggle's default-on/off state is verified in tests.

7. **What are the conventions for user-facing strings, accessibility
   identifiers, and per-file organization?** Trace `SharedStrings` in
   `SingleThreadCore` (`LocalizedString+Shared.swift`), the
   `Localizable.xcstrings` infrastructure, a11y-id naming (`*Button`,
   `*Toggle`, `settings*Row`), and the file-length/type-length budgets that
   drive `ContentView+*.swift` extension splits (`swiftlint:disable
   file_length` headers), with examples of identifiers for actions like skip,
   delete, and reschedule.