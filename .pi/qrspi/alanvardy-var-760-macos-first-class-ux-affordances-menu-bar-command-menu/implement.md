# Implementation Summary

Ticket: var-760 — macOS first-class UX affordances (menu bar, command menu, notifications)
Branch: `alanvardy-var-760-macos-first-class-ux-affordances-menu-bar-command-menu`
PR: #159

> **Post-rebase integration**: while this branch was in flight, `origin/main` absorbed the var-792 branch
> (which had received this ticket's `NotificationScheduler.swift` + `NotificationSchedulerTests.swift` through a
> cross-worktree stash incident and then **evolved them** into a key-injected scheduler API with
> `UserNotificationCentering` + `FakeUserNotificationCenter` extracted into Core) and the var-796 branch
> (which **deleted the iOS notification UI tests**). The conflict resolution adopted main's merged scheduler +
> iOS wrappers wholesale and kept only this ticket's unique macOS work, adapted to main's API. See plan.md's
> integration note for detail.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| base  | `3463ee9` | macOS first-class UX affordances (ticket base commit, replayed on new main) |
| —     | `1640acc` | chore: questions for var-760 |
| 1     | `dc14c3d` | Phase 1: NotificationScheduler foundation — **superseded by main** (adopted main's merged `NotificationScheduler` + scheduler tests; this commit now carries only the QRSPI plan.md) |
| 2     | `abb21b9` | Phase 2: AppViewModel rewiring + macOS scheduling triggers — iOS wrappers from main; this ticket contributes the shared scheduler property, the `scheduleNotificationsForMacOS()` trigger on `onRemindersChanged`, and the macOS enabled-key default |
| 3     | `2fa80b5` | Phase 3: App commands — `CommandMenu` (Reminder Complete/Skip, Appearance System/Light/Dark Picker), About/Quit app-menu groups via `appCommands` (`@CommandsBuilder`), `@State` view model + `@AppStorage` appearance |
| 4     | `8cde055` | Phase 4: MenuBarExtra — live next-reminder dropdown (`MenuBarExtraOptions`) + headless content tests |
| docs  | `6c970eb` | docs: implementation summary + plan checkboxes |

## Automated Checks

- [x] `make mac-build` passes (post-rebase, against main's evolved codebase)
- [x] `make mac-test` passes — `MenuBarExtraOptionsTests` (this ticket) + main's `NotificationSchedulerTests`/`UserNotificationCenteringTests` all green; only the 2 pre-existing local StoreKit `EntitlementStoreTests` fail (identical on clean main; CI's `mac-tests` job passes them)
- [x] `make test` passes (iOS unit run — shared scheduler + iOS notification wrappers compile and pass on iOS)
- [x] `make format` + `make lint` pass (0 violations, `--strict`)
- [x] Full gate: previously run on the pre-rebase head (only the same 2 StoreKit tests failed); post-rebase phase-verified via mac-build/mac-test/make test. (Full `./scripts/test.sh` re-run still warranted by CI on the new head.)
- [ ] ~~iOS notification UI regression suite~~ — **superseded**: the suites were deleted on main by var-796 before this branch landed; iOS scheduling semantics are guarded by `NotificationSchedulerTests` + the iOS unit run.

## Deviations from the plan (documented)

1. **Scheduler foundation adopted from main** (see integration note): main's merged `NotificationScheduler` API is `scheduleIfNeeded(reminderCount:, hasHidden:)` / `cancelAll()` / `requestPermissionIfNeeded()` with key-injected `UserDefaults`; the plan's own scheduler design was superseded by the merged evolution of this ticket's own Phase 1 files (post-stash-incident).
2. **macOS "always enabled"** via a macOS-only `UserDefaults.standard.register(defaults: ["notificationsEnabled": true])` in `registerDefaults` instead of passing `enabled: true` (main's API reads the key itself). A denied macOS permission prompt still flips the key off, matching iOS semantics.
3. **macOS permission options** are `.alert + .badge` (main's unified `requestPermissionIfNeeded()`), not the plan's `.alert, .sound` — a consequence of adopting main's scheduler; one unified behavior.
4. **`appCommands` uses `@CommandsBuilder`** (Phase 3): the plan's multi-`CommandGroup`/`CommandMenu` free function doesn't compile without the SwiftUI result-builder attribute.
5. **MenuBarExtra is always-present, empty-content when nothing due** (Phase 4): the plan's primary "hide entirely" conditional scene crashes the Swift 6 compiler (internal error in the `@SceneBuilder`); applied the plan's documented fallback.
6. **iOS UI-test verification impossible post-var-796** (was: 8 notification UI tests pass unchanged) — suites deleted on main; documented in plan.md.

## Manual Verification Items (from the plan)

- [ ] Phase 2: `make mac-run` — on first launch with a due reminder, macOS shows the notification permission prompt; after granting and with a signed/entitled build (design Open Risk: sandbox + hardened runtime), a notification is scheduled for the due reminder.
- [ ] Phase 3: `make mac-run` — Application menu has "About SingleThread" (opens the About sheet) and "Quit SingleThread" (exits); the Reminder menu's Complete/Skip mutate the current reminder; the Appearance Picker switches System/Light/Dark and the change applies immediately.
- [ ] Phase 4: `make mac-run` — the menu-bar item (always present under the compiler-crash fallback) shows the next due reminder's title/actions when one is due and an empty menu when none is due; Completing/Skipping mutates the reminder and clears the strip; "Open SingleThread" activates and fronts the window.

## Observations for review

- **StoreKit local quirk**: the 2 `EntitlementStoreTests` fail on the local macOS host only (StoreKit sandbox); CI is authoritative.
- **Stash caution**: a concurrent var-792 worktree shared `refs/stash` during this work (one crossing incident, all work recovered). Avoid `git stash` on this repo until that branch finishes.
- Periphery ran clean in the earlier full gate; no dead code introduced by this ticket's deltas.
- No macOS UI tests per var-788 decision; no `UNUserNotificationCenterDelegate`/foreground banner per resolved amendment 3; no WidgetKit macOS work, no new persistence keys, no repeating timer.