# Design Discussion

## Current State

The three-action menu (Skip / Reschedule / Delete) exists on all three platforms but is only toggleable from iOS Settings. The `enableActionButtons` flag is an `@AppStorage("enableActionButtons", store: AppGroup.defaults)` property gated behind `#if os(iOS)` in `ContentView.swift:96-97`, with its toggle row identically gated in `InterfaceSettingsView.swift:86-97`. macOS reads the flag raw from App Group at `ContentView+ActionMenu.swift:91`; watchOS reads it through `ShowEnableActionButtonsState` (`ShowEnableActionButtonsState.swift:15,24`) populated by the phone→watch sync pipeline (`SkippedReminderSyncService.swift:448-452` → `WatchAppViewModel.swift:273-276`). Both macOS and watchOS produce the correct action-menu UI when the flag is true — the menu code is ungated and fully wired (`ContentView+ActionMenu.swift:70-173` for macOS, `WatchReminderView.swift:81-85,129-157,283-286` for watch). The gap is purely in the settings layer: no toggle exists on macOS, and watchOS has no local control surface. The existing iOS toggle is the sole entry point for new users to enable the feature.

## Desired End State

A macOS user can toggle the action menu on/off from the macOS settings sheet without running the iOS app. The watch receives the flag from the phone via the existing sync pipeline and presents the action menu when enabled — no watch-side toggle (phone-authoritative design). The toggle-off path (direct Skip button on macOS, direct skip on watch) is behaviorally identical to today.

**Verification**: `./scripts/test.sh` passes (all platforms). On macOS: opening the settings sheet shows a "Show action buttons" toggle row; toggling it changes the bottom-bar skip/delete buttons vs. menu immediately. On watch: after the iOS toggle is set and sync delivers the value, the action-menu confirmation dialog appears when tapping Skip.

## Patterns to Follow

- **Platform gating: compile out, don't stub.** `#if os(iOS)` blocks at both binding declaration and row statement (`InterfaceSettingsView.swift:13-28,:59-120`) — macOS call sites never pass those bindings. When moving `enableActionButtons` to shared code, remove the `#if` guards but keep the pattern for the five remaining iOS-only fields.
- **Settings write-back chain.** Control edit → `@Binding` → ephemeral `SettingsBindings` bag (`SettingsView.swift:178`) → `settingsSheetWritebacks` `.onChange` bridge → `@AppStorage` setter (`ContentView+Settings.swift:8-43`). The bag is single-instance per sheet-open and nilled on dismiss (`ContentView.swift:286-291,:336`). Follow this exactly — don't introduce a new persistence path.
- **Bag carries all 19 fields unconditionally.** `SettingsBindings.swift:4-13` documents that iOS-only fields exist on macOS "never wired or read." `enableActionButtons` is already in the bag at `:66` — this ticket adds it to the macOS wiring, not to the bag itself.
- **App Group discipline.** Every watch-shared value must round-trip through `AppGroup.defaults`, never `.standard` (`AGENTS.md`; `AppGroup.swift:12-17`). `enableActionButtons` already uses `store: AppGroup.defaults` on iOS (`ContentView.swift:96`); macOS must persist to the same suite.
- **Watch sync: receive-only for preferences.** The watch sets `sends* = false` for all show-* preferences (`WatchAppViewModel.swift:192-193`), and `enableActionButtons` is already pushed unconditionally from the phone (`SkippedReminderSyncService.swift:209`). Do not add a watch→phone preference path — maintain the existing asymmetry.
- **Testing through state seams, not view bodies.** As demonstrated by `ActionButtonTests.swift:6-13` (test the gate, not the rendered `_ConditionalContent`) and `ShowEnableActionButtonsStateTests.swift` (test the state holder, not the watch UI). New tests follow this pattern.
- **Existing keyboard shortcuts are unchanged.** The four macOS shortcuts (`ContentView+ActionMenu.swift:105,:122,:129,:144`) continue to work identically — the toggle only swaps the bottom bar between menu and direct-button layouts; the keyboard shortcuts belong to whichever layout is active.

### Patterns NOT to Follow

- **Do not duplicate `ActionMenuGate.showsActionMenu` on watch.** The watch currently inlines the AND at `WatchReminderView.swift:81-85` rather than calling the shared helper (`ActionMenuGate.swift:7-13`). This is pre-existing and out of scope — don't refactor it in this ticket.
- **Do not add a macOS UI test.** No macOS UI-test invocation exists anywhere (`conventions.md` — test.sh, ci.yml, Makefile), and the target already declares `macosx` support (`project.pbxproj:907,:931`) without being run. Adding one is a separate infrastructure concern.
- **Do not refactor the six-field `#if os(iOS)` block.** Only `enableActionButtons` moves to shared code. `allowsLandscape`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours` remain iOS-only with no macOS wiring.

## Design Decisions

1. **Watch authority model — phone-authoritative relay**: The watch reads `enableActionButtons` from the phone via the existing sync pipeline. No watch-side toggle. No `sendMessage` relay. The phone's `@AppStorage(store: AppGroup.defaults)` write → `didChangeNotification` → `handlePreferencesChanged` → `pushAll` → watch `didReceiveApplicationContext` → `ShowEnableActionButtonsState.apply` chain (`AppViewModel.swift:450-492` → `SkippedReminderSyncService.swift:209,:448-452` → `WatchAppViewModel.swift:273-276`) is the single truth path. The watch action menu is already fully implemented behind this flag — the "new control surface" is the menu becoming reachable without watch-side code changes.

2. **Watch toggle location — none (on the phone)**: No toggle UI on watchOS. The iOS Settings row is the sole control point. This is the simplest path and avoids cluttering `WatchReminderView`. If watch-side settings are needed in the future, a `WatchSettingsView` can be introduced then — but that's a separate feature.

3. **macOS scope — minimal `enableActionButtons` only**: Move only the `enableActionButtons` `@AppStorage` declaration, binding pass, write-back, and toggle row from `#if os(iOS)` to unconditional or `#if os(iOS) || os(macOS)`. The five remaining iOS-only fields stay gated. ~4 sites change:
   - `ContentView.swift:96` — move `@AppStorage` declaration out of `#if os(iOS)`
   - `ContentView+Settings.swift:24,:72-85` — add write-back `.onChange` to macOS branch and pass `enableActionButtons:` in the macOS `makeSettingsBag` call
   - `SettingsView.swift:51-55` — add `enableActionButtons: $bindings.enableActionButtons` to the macOS `InterfaceSettingsView` navigation link
   - `InterfaceSettingsView.swift:19-20,:86-97` — move `@Binding` declaration and toggle row out of `#if os(iOS)`

4. **Testing — unit tests only**: Extend `SettingsViewTests.swift` to assert the macOS action-buttons row is present with correct label and caption. Add a macOS-gated write-back test verifying the `.onChange` bridge persists to `AppGroup.defaults`. No watch UI test — the state transition is unit-testable through `ShowEnableActionButtonsState`, and the end-to-end appearance is already covered by existing watch UI tests that use `--ui-testing-action-menu`.

5. **Sync pipeline — no `sendsEnableActionButtons` guard**: The `pushAll()` payload at `SkippedReminderSyncService.swift:209` continues to include `enableActionButtons` unconditionally. The phone's `lastEnableActionButtons` diff guard (`AppViewModel.swift:479-492`) already suppresses identical-value pushes. Adding a guard is complexity with zero functional win.

## What We're NOT Doing

- **No watch-side toggle UI** — the phone is the single authority for this flag.
- **No watch→phone preference messages** — the sync asymmetry (phone sends preferences, watch receives them) remains unchanged.
- **No refactoring of the five remaining iOS-only settings** — `allowsLandscape`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`, `notificationIntervalHours` stay gated.
- **No macOS UI test** — macOS gets unit-test coverage only, consistent with the existing CI and test.sh configuration.
- **No `ActionMenuGate` deduplication on watch** — the inlined AND at `WatchReminderView.swift:81-85` is pre-existing and out of scope.
- **No new `SkippedReminderSyncService` init parameters** — the `sendsEnableActionButtons` guard is not added.
- **No bag struct changes** — `SettingsBindings` already carries `enableActionButtons` unconditionally at line 66; no new fields or conditional compilation changes needed.

## Open Risks

- **App Group fallback on real macOS hardware.** `AppGroup.defaults` resolves to `.standard` when the suite is unavailable (`AppGroup.swift:16-17`). On a real Mac outside the simulator, the App Group suite should be available (the macOS target has the entitlement, `SingleThread.entitlements:9-11`), but this has not been verified on physical hardware. If the suite is unavailable, `enableActionButtons` silently lands in `.standard` and won't be shared with the iOS app.
- **macOS toggle interaction with the iOS toggle.** If both iOS and macOS write to the same App Group key, the last write wins. The `didChangeNotification` observer on the phone (`AppViewModel.swift:450-458`) will see macOS-originated changes and push them to the watch — no conflict, but no locking either. This is the existing behavior for all App Group keys and hasn't caused issues.
- **Watch action-menu UX without a local disable path.** A watch user who finds the action menu distracting must reach for their phone to disable it. This is the explicit design choice (phone-authoritative) but may generate user feedback.