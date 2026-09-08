# Design Discussion

## Current State

The app surfaces **skip** as a direct one-tap action on every platform, gated only by `canMutate` (entitlement or count < 100, `ReminderStore.swift:167-172`):

- **iOS**: cluster button (`ContentView.swift:526-536`, id `skipButton`, `circle.slash` `.orange`) in the bottom bar when `showsActionButtons` is true (`:680-687`); trailing swipe (`:480-487`, no id, matched by label in tests); also in the nudge sheet. macOS: always-visible bar button with keyboard shortcut `s` (`:344-355`). Watch: button in action row (`WatchReminderView.swift:130-139`, id `skipButton`). Widget: `Button(intent: SkipReminderIntent)` (`NextThingWidget.swift:141-158`).
- **enableActionButtons** toggle (`InterfaceSettingsView.swift:87-97`, id `showActionButtonsToggle`) stored in `.standard` UserDefaults (`ContentView.swift:96-97`, default `false`). It toggles the iOS bottom-bar cluster on/off but doesn't change skip itself — swipe, watch, macOS, and widget skip are all unaffected.
- **The toggle has NO sync to watch** — watch has no `enableActionButtons` key, no `PayloadKey` entry, no push/receive plumbing. Both iOS test seams (`--ui-testing` at `AppViewModel.swift:291`, `--seed` at `:350`) force it `true` after reset so existing UI tests always see the cluster.
- **No multi-option action menu exists on iOS or macOS.** The watch uses `confirmationDialog` for refresh/delete (`WatchReminderView.swift:214-228`) and nudge-delete (`:230-243`). The nudge sheet (`ContentView+iOS.swift:59-86`) is the only 3-action surface (reschedule/delete/view-in-reminders) but is tightly coupled to the 6th-skip interrupt — `nudgedReminderHasDueTime` (`:91-101`) and the "This reminder keeps coming back" message are nudge-specific.
- **Reschedule** (`ReminderStore.swift:344-367`) is called only from the nudge flow (`ContentViewModel.rescheduleNudgedReminder(to:)` at `ContentViewModel.swift:205-212`). It's `#if os(watchOS) return false` (`ReminderStore.swift:350-352`) — EventKit is read-only on watch. **Delete** (`:285-307`) is called from the context menu (iOS), macOS bar button, and nudge sheet; the watch branch fires a relay `sendMessage` to the phone (`:292-296`).

## Desired End State

1. **Toggle moves to `AppGroup.defaults`** and syncs to watch via the existing `SkippedReminderSyncService` pipeline (new `PayloadKey`, `pushAll` insert, `apply(context:)` decode, watch receive hook). Off by default everywhere. Name stays `enableActionButtons` to avoid a migration.

2. **When the toggle is OFF**: behavior is completely unchanged on every platform — direct skip on tap, existing buttons, no menu.

3. **When the toggle is ON**:
   - **iOS (iPhone + iPad)**: tapping the skip button (cluster or trailing swipe) presents a `.confirmationDialog` with three options: **Skip**, **Reschedule**, **Delete**. The skip button itself keeps its `circle.slash` icon, `.orange` tint, and `skipButton` id.
   - **macOS**: the skip button becomes a `Menu` with the same three options: **Skip**, **Reschedule**, **Delete**. The standalone **Delete button is removed** from the bar (`ContentView.swift:360-369`). Keyboard shortcut `s` still triggers the menu. Complete and Skip remain in the bar (but Skip is now a Menu when toggle is on).
   - **watch**: the skip button presents a `confirmationDialog` (matching the existing watch pattern at `WatchReminderView.swift:214-228`) with Skip, Reschedule, Delete. Reschedule relays to the phone via `sendMessage` with a new `PayloadKey.rescheduleReminderIdentifier`, mirroring the delete-relay pattern at `ReminderStore.swift:292-296` and `SkippedReminderSyncService.swift:230-237`.
   - **Widget**: **unchanged** — always direct skip. Widgets can't present menus.

4. **Reschedule UI is extracted** from the nudge sheet into a general-purpose reusable view (e.g. `RescheduleSheet`). The nudge sheet reuses it. The DatePicker logic for date-only vs date+time (`ContentView+iOS.swift:91-113`) stays intact.

5. **Verification**: unit tests (toggle defaults, menu gate, sync payload round-trip); iOS UI tests (confirmationDialog appears, each action works, toggle persists across relaunch); watch UI tests (dialog appears when toggle synced, actions work); macOS tests (Menu rendered, Delete button removed). All existing tests must pass unchanged — the toggle-off path is behaviorally identical to today.

## Patterns to Follow

- **Toggle storage + sync**: mirror `showDate`/`showCompletionGlow`/etc. — typed preference struct in Core (`ShowDatePreference.swift:8-23` pattern), `@AppStorage(store: AppGroup.defaults)` on iOS (`ContentView.swift:115-133` pattern), `PayloadKey` entry (`SkippedReminderSyncService.swift:278-293`), `pushAll` conditional insert (`:176-213`), `apply(context:)` decode (`:320-376`), watch `wireStateReceiveHooks` apply (`WatchAppViewModel.swift:222-248`). The watch does NOT get a Settings UI toggle — it follows phone state (same as `showDate` etc.).
- **Toggle-off = no-op**: gate every new code path behind the toggle value so the off path is identical to today. This is how `showsActionButtons` already gates the cluster vs mic-only (`ContentViewModel.swift:52-61` → `ContentView.swift:686-689`).
- **Settings wiring**: `SettingsBindings` bag property (`SettingsBindings.swift:18-45` pattern), `InterfaceSettingsView` toggle row (`InterfaceSettingsView.swift:87-97` pattern, id `<feature>Toggle`), `settingsSheetWritebacks` onChange (`ContentView+Settings.swift:9-46`), live re-read by ViewModel (`ContentViewModel.swift:52-61`).
- **A11y ids**: `<action>Button` pattern for menu actions (`skipButton` already exists; add `rescheduleButton`, ensure `deleteButton` is present). `nudge<Action>Button` pattern for reschedule-specific ids.
- **Strings**: cross-target strings via `SharedStrings` (`LocalizedString+Shared.swift`); "Reschedule" and "Reschedule to" already exist in the nudge sheet; "Delete" is already `SharedStrings.deleteAction` (`:23`); only new string = maybe "Reschedule Reminder" a11y label.
- **File organization**: extract the reschedule sheet into its own file; if `ContentView.swift` or `ContentView+iOS.swift` grow past budgets (650/800 lines), split into another `ContentView+*.swift` extension with the documented header comment.
- **Tests**: unit (Swift Testing, no `test` prefix) for gate logic + sync payload roundtrip; UI tests (XCTest) for end-to-end flows. Reuse `flipToggle`/`assertTogglePersists` from `SingleThreadUITestCase.swift:28-60`. Watch UI tests match dialog actions by label (`SingleThreadWatchUITests.swift:20-24` pattern). Seed both test seams for the new toggle default — update `UITestingSeed.resetPersistedState` (`UITestingSeed.swift:86`) and `AppViewModel.seededStore` (`:350`).
- **macOS delete removal**: when toggle is ON, the standalone Delete button (`ContentView.swift:360-369`) is hidden/removed. When toggle is OFF, it stays. This is a conditional view, not a permanent removal.

## Design Decisions

1. **iOS action presentation: `.confirmationDialog`** — popover on iPad, action sheet on iPhone. Watch already uses this pattern (`WatchReminderView.swift:214-228`). Handles destructive actions naturally. Actions addressable by label in UI tests (watch precedent). Attached to the existing skip button so the tap target doesn't move.

2. **macOS action presentation: `Menu`** — idiomatic macOS SwiftUI for "one button, several options." Attached to the skip button. Delete button is removed from the bar when the toggle is ON so it's not duplicated. Keyboard shortcut `s` still triggers the menu (focus lands on the skip button → menu).

3. **Toggle storage: `AppGroup.defaults` + watch sync** — follows the showDate/showCompletionGlow/etc. pipeline exactly. New `PayloadKey.enableActionButtons`, inserted into `pushAll` snapshot, decoded in `apply(context:)`, applied via new `ShowEnableActionButtonsState` or a plain `@AppStorage` on the watch side. Watch has no Settings UI toggle — state follows phone, same as all five show-* prefs.

4. **Widget: unchanged** — always direct skip. Widgets can't present menus and removing the skip button would break the primary widget action. This is a platform constraint, not a design bug.

5. **Reschedule UI: extract from nudge sheet** — the nudge sheet's DatePicker logic (`ContentView+iOS.swift:91-113`, date-only vs date+time) moves into a reusable `RescheduleSheet` view. The nudge sheet delegates to it (passing the nudge-specific message as optional overlay). The new confirmationDialog/Menu triggers it for general reschedule. On watch, reschedule is a store-level no-op (`ReminderStore.swift:350-352`); the watch menu shows it but either relays to phone (extending the delete-relay pattern at `:292-296`) or shows a descriptive alert.

6. **Nudge flow: unchanged** — the 6th-skip nudge still fires independently. The nudge sheet still offers Reschedule/Delete/View-in-Reminders. The new menu is a separate path for voluntary (non-nudge) multi-action access.

## What We're NOT Doing

- **Not adding a Settings UI toggle on watch** — there's no Settings on watch, and showDate/etc. already follow this phone-leads model.
- **Not changing the nudge interrupt** — the 6th-skip nudge is independent; this feature is about voluntary multi-action access.
- **Not changing swipe behavior** — the trailing swipe stays a direct skip. Only the explicit button tap opens the menu.
- **Not touching the context menu** (`ContentView.swift:451-471`) — it stays View-in-Reminders + Delete with its existing styling.
- **Not adding a "Delete" option to widget** — widgets are static intent buttons.
- **Not migrating the preference key** — we keep `enableActionButtons` (already exists, default `false`) but move it to `AppGroup.defaults`. Both test seams already reset + set it to `true`;we update the reset list and the set target.
- **Not changing macOS keyboard shortcuts** — `s` still triggers skip (via the menu when toggle is ON).
- **Not adding new sorts/filters/animations** — scope is strictly the action menu.

## Open Risks1. **Watch reschedule relay (RESOLVED)**: Reschedule on watch uses `sendMessage` relay to phone — new `PayloadKey.rescheduleReminderIdentifier` + `requestRescheduleReminder` method on `SkippedReminderSyncService`, mirroring the delete relay at `ReminderStore.swift:292-296` and `SkippedReminderSyncService.swift:230-237`. The reschedule payload includes the `calendarItemIdentifier` and target `dueDateComponents`. Phone-side `onRescheduleReminderReceived` hook calls `store?.rescheduleReminder(identifier:to:)`.

2. **macOS Menu + keyboard shortcut interaction**: `Menu` with `.keyboardShortcut("s")` on the parent button — does the shortcut open the menu or trigger the first (default) action? Needs verification on macOS 26.

3. **confirmationDialog on iPad**: popover source must be the button frame. The existing skip button has a stable `skipButton` id — `confirmationDialog` should anchor to it. If iPad popover positioning is off, may need explicit `.popover(attachmentAnchor:)` or similar.

4. **Toggle migration**: moving `enableActionButtons` from `.standard` to `AppGroup.defaults` means existing users who turned it on will lose their setting (it'll revert to `false`). Mitigation: read from `.standard` once on first launch and migrate to `AppGroup.defaults`, then stop reading from `.standard`. Or accept the reset (toggle is off by default, likely few users have it on).

5. **Removing macOS Delete button when toggle is OFF**: the Delete button must remain visible when the toggle is off (backward compatibility). The conditional view adds a branch in the macOS bar layout — test both states.

6. **UI test addressing**: confirmationDialog actions on iOS may not have reachable ids(like watch dialogs). Label-matching (`app.buttons["Skip"]`) may be needed; the existing `ActionButtonsUITests.swift` and `SkipNudgeUITests.swift` patterns should transfer.