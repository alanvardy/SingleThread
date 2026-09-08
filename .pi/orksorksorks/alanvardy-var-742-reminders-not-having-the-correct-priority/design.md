# Design Discussion

## Current State

- **There is no intermediate model.** `ReminderStore.reminders: [EKReminder]` caches raw EventKit objects (`ReminderStore.swift:43`). `ReminderDisplay` is a transient per-render snapshot (`ReminderDisplay.swift:8-21`); it's never stored back.
- **Single priority mapping point:** `ReminderPriority.level(for:)` at `ReminderSkip.swift:50-58`. Maps `Int` → `Level?`: only `1` → `.high`, `5` → `.medium`, `9` → `.low`; all other values → `nil` (treated as no priority). This feeds both display (`marker(for:)` → `!!!`/`!!`/`!`/`""`, `:71-80`) and sorting (`rank(for:)` → 0/1/2/nil, `:82-90`).
- **The bug:** Some reminders — intermittently, on both platforms — show no priority marker even though Apple Reminders shows they have one. The user suspected the skip gesture, but analysis shows skip is identifier-only and never touches `EKReminder` objects (`ReminderStore.swift:253-260`, `ReminderSkip.swift:12-23`).
- **Likely root cause — CalDAV priority range gap:** `EKReminder.priority` is an `NSInteger`; RFC 5545 defines the range 0–9 (1–4 = high, 5 = medium, 6–9 = low, 0 = none). Third-party CalDAV servers (Google, Fastmail, etc.) can sync priorities outside `{0,1,5,9}` — values like `3` or `7` land as raw integers in EventKit but our switch at `ReminderSkip.swift:53-58` drops them to the `default: nil` branch. Both platforms share this code (`SingleThreadCore`), explaining the cross-platform nature of the bug.
- **Both display and sorting are affected** — a priority-7 reminder gets no marker AND sorts as "no priority," pushing it behind prioritized reminders when sorting by priority (`ReminderSort.swift:14-30`).
- **Skip-to-clear race:** `skipCurrentReminder()` fires an async `Task` with a 200 ms sleep before `applySkipSet` (`ReminderStore.swift:256-260`). If `reload(clearSkipped: true)` runs during that window (`:328-331`), the skip applies AFTER the clear, re-hiding a just-unhidden reminder.
- **No UI test asserts rendered priority marker** — only ordering (`testSkipAdvancesToNextReminder`, `SingleThreadUITestsFlows.swift:53-70`) and unit-level mapping are covered (`ReminderSkipTests.swift:98-142`). No test on either platform asserts the marker text, color, or accessibility label is visible on screen.

## Desired End State

1. **Priority mapping covers the full RFC 5545 range.** `ReminderPriority.level(for:)` maps 1–4 → `.high`, 5 → `.medium`, 6–9 → `.low`. Display markers, sort ranks, and accessibility labels all reflect these values. A reminder with priority 3 renders `!!!` in red, priority 7 renders `!` in green.
2. **Skip-to-clear race is closed.** A `reload(clearSkipped: true)` reliably prevents a concurrently-pending skip from re-applying.
3. **UI tests assert visible priority rendering.** At least one UI test on each platform confirms the priority marker text appears on screen for a seeded reminder.
4. **Instrumentation confirms the hypothesis before the fix ships.** A temporary log in `ReminderDetail.init` confirms that non-`{0,1,5,9}` priority values are the culprit.

### Verification

- `ReminderPriority.level(for: 2)` returns `.high`; `level(for: 7)` returns `.low`. Unit test.
- `ReminderPriority.marker(for: 3)` returns `"!!!"`; `marker(for: 8)` returns `"!"`. Unit test.
- `ReminderPriority.rank(for: 4)` returns `0`; `rank(for: 6)` returns `2`. Unit test.
- `ReminderDisplay(reminder:).priorityMarker` is non-empty for priorities 2–4, 6–8. Unit test.
- iOS UI test: seeds a priority-3 reminder and asserts the `"!!!"` marker text exists.
- Watch UI test: seeds a priority-7 reminder and asserts the `"!"` marker text exists.
- Skip race: a unit test that fires skip immediately followed by `reload(clearSkipped: true)` and verifies the reminder is NOT re-hidden.
- Temporary `os_log` of `reminder.priority` raw values in `ReminderDisplay.init` (reverted before merge).

## Patterns to Follow

- **Single source of truth for mapping.** `ReminderPriority.level(for:)` (`ReminderSkip.swift:50-58`) is the only place that converts raw Int to Level. `marker(for:)` and `rank(for:)` both delegate to it. Keep it that way.
- **Value-type snapshots for display.** `ReminderDisplay.init(reminder:)` (`ReminderDisplay.swift:11-21`) builds a transient display DTO; views read it, never mutate it. No new model layer needed.
- **Protocol-backed test seams.** `EventKitStoring` (`EventKitStoring.swift:8-45`) lets tests inject `InMemoryEventStore`; `SkipSyncSession` does the same for WatchConnectivity. New tests use these existing seams.
- **`#if os(watchOS)` / `#if os(iOS)` for platform divergence.** `ReminderStore` uses these guards for EventKit writes (iOS only) vs. local removal + relay (watchOS) (`ReminderStore.swift:168-179`, `:195-213`). Any platform-specific test seeding follows the same pattern.
- **UI tests use `--seed '<json>'`** (`UITestingSeed.swift:8-26`) for multi-reminder deterministic seeding with priority. Watch uses `--ui-testing` for a single-reminder store (`WatchAppViewModel.swift:96-133`).
- **WatchConnectivity carries state, never content** — skip IDs and preferences only (`SkippedReminderSyncService.swift:268-287`). No new sync keys needed for priority; priority data lives in EventKit on each device.
- **Avoid:** properties like `url`, `location`, `startDateComponents`, `completionDate`, `lastModifiedDate`, `timeZone`, `contactIdentifier`, `endDateComponents`, alarm details, and recurrence rules beyond the first — these are never read anywhere in the codebase (Research Q1).

## Design Decisions

1. **Priority range expansion (Q1/Q2):** Expand `ReminderPriority.level(for:)` to the full RFC 5545 range — `1...4 → .high`, `5 → .medium`, `6...9 → .low`. Keep the existing three markers (`!!!`/`!!`/`!`). This matches Apple Reminders.app's own bucketing and avoids visual noise. No new sync keys, no new model layer — a surgical change to the one mapping function.

2. **Instrumentation-first** (Q5): Add a temporary `os_log` in `ReminderDisplay.init` logging the raw `reminder.priority` value whenever it's outside `{0,1,5,9}`. The log ships in the same branch, gets tested on-device to confirm the hypothesis, then is reverted before merge. This de-risks the fix without adding permanent overhead.

3. **Skip race fix** (Q3): Add a `skipGeneration` counter to `ReminderStore`. `skipCurrentReminder()` captures the current generation before sleeping; `applySkipSet` is a no-op if the generation has changed. `reload(clearSkipped: true)` increments the generation, invalidating any pending skip. Minimal surface area, no new synchronization primitives.

4. **UI test assertions for priority rendering** (Q4): Add an assertion to the existing iOS `--seed` UI test (`SingleThreadUITestsFlows.swift`) that `app.staticTexts["!!!"]` exists when a priority-1 reminder is seeded. For watchOS, extend the `--ui-testing` seam with an optional priority parameter and add a `waitForExistence` assertion for the marker text. Both platforms get visual regression coverage.

5. **Unit test coverage for new range values:** New test cases in `ReminderPriorityTests` (`ReminderSkipTests.swift:98-142`) for boundary values: `level(for: 2)` → `.high`, `level(for: 4)` → `.high`, `level(for: 6)` → `.low`, `level(for: 8)` → `.low`. New `ReminderDisplayTests` cases confirming `priorityMarker` is non-empty for 2–4 and 6–8.

## What We're NOT Doing

- **Not adding "Urgent" support** — the iOS 26 Urgent toggle is a separate EventKit flag, orthogonal to priority.
- **Not changing the sync wire protocol** — priority is read from local EventKit on each device; no new WatchConnectivity keys.
- **Not adding a priority editing feature** — this is a display-only fix. The user can't set priority in-app.
- **Not adding 9 distinct marker levels** — stick with Apple's 3-level bucketing.
- **Not refactoring `ReminderStore` away from raw `EKReminder` cache** — that's a larger architectural change out of scope.
- **Not touching the dictation / creation path** — dictation-created reminders remain priority-0 by design.
- **Not adding priority-based filtering** — only display and sorting.

## Open Risks

- **Confirming the CalDAV hypothesis.** The instrumentation log is the proof. If on-device testing shows no non-`{0,1,5,9}` values, the root cause may be something else (e.g., stale `EKReminder` objects post-reload, or EventKit returning `0` after a specific mutation sequence). The instrumentation de-risks this.
- **`EKReminder` thread safety.** `EKReminder` is retroactively `@unchecked Sendable` (`ReminderDateFilter.swift:20-26`); cross-actor access after a concurrent mutation could theoretically return stale `priority` values. Unlikely given all access is `@MainActor`, but worth watching during instrumentation.
- **Watch UI test seam for variable priority.** The current `--ui-testing` seam hardcodes `priority = 5` (`WatchAppViewModel.swift:100`). Adding a parametric priority (e.g., `--ui-testing-priority 7`) requires a small seam change — minimal risk but needs the argument parsing logic to be clean.
- **Skip-generation counter and `skipCurrentReminderImmediately()`.** The synchronous widget path (`ReminderStore.swift:279-285`) doesn't sleep, so the race doesn't apply there. The generation counter must be a no-op for that path to avoid breaking widget skip behavior.