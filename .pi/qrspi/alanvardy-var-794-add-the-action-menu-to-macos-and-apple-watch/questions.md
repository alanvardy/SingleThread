# Research Questions

## Context

Focus on the SingleThread shared iOS/macOS app target and the SingleThreadWatch
app, plus the SingleThreadCore sync service. Relevant areas: the settings
layer (`SettingsBindings.swift`, `ContentView+Settings.swift`,
`SettingsView.swift`, `InterfaceSettingsView.swift`), the action-button UI
(`ContentView+ActionMenu.swift`, `ActionMenuGate.swift`), the phone↔watch
preferences sync pipeline (`SkippedReminderSyncService.swift`,
`ShowEnableActionButtonsState.swift`, `WatchAppViewModel.swift`,
`AppGroup.swift`), and the unit/UI test suites plus CI configuration that cover
these areas.

## Questions

1. **Settings data flow on iOS vs macOS**: In `SettingsBindings.swift`, `ContentView+Settings.swift` (`makeSettingsBag` / `settingsSheetWritebacks`), how is a settings field defined, threaded into the settings sheet, and persisted to the App Group suite on each platform? Which fields exist on iOS vs macOS, which are wired only under `#if os(iOS)`, and how do the write-backs reach `AppGroup.defaults`?

2. **Shared settings view layer**: `SettingsView.swift` builds `InterfaceSettingsView` with 7 bindings on iOS but 3 on macOS, and the file is compiled into both builds. How do the `#if os()` branches differ, what happens to rows/bindings macOS never passes, and is there any existing precedent for a settings row that exists on both platforms but is only reachable on one?

3. **macOS action-button mechanics**: How does the macOS action-button area of `ContentView+ActionMenu.swift` decide between showing a menu vs direct skip, where does it read its gate value from (including `ActionMenuGate.swift`), and what keyboard shortcuts are attached to the menu and its items? Is the macOS gate value the same App-Group-backed value iOS writes?

4. **watchOS app structure and state holders**: Enumerate the watchOS SwiftUI views and `@Observable` state holders in `SingleThreadWatch`. Which state holders mirror shared preferences, where does each persist (App Group suite vs `.standard`), and how do persisted values drive the watch UI (e.g. `canShowActionMenu`, action buttons in `WatchReminderView`)?

5. **Phone↔watch preferences sync**: In `SkippedReminderSyncService.swift` and its wiring, which payload keys travel phone→watch via `pushAll()`, which watch→phone messages exist, and how are received preference values persisted on the watch? When a value is changed on one side, what happens on the next push from the other side — and how does the phone observe App Group changes (`setupSyncObservation` / `lastEnableActionButtons`)?

6. **Test and CI coverage for these areas**: Which unit tests cover the settings bindings, the action-menu gate, and enableActionButtons sync (e.g. `SettingsViewTests`, `ActionMenuGateTests`, `EnableActionButtonsSyncTests`)? How do the watch UI tests drive app state (launch-argument seams like `--ui-testing`, `--ui-testing-action-menu` in `SingleThreadWatchUITests`), and what does CI run for macOS and watchOS (`scripts/test.sh`, `.github/workflows/ci.yml`) — including whether any macOS UI-test invocation exists?