# Findings — Severity-Ranked

## Tier Classifications

| Tier | Label | Criteria |
|---|---|---|
| T1 | Reachable Contradiction/Data Loss | A reachable code path produces state the app cannot correctly interpret, or data can be silently lost |
| T2 | Cross-Target Divergence | Two targets disagree on what a key means or where it lives; same logical value lands in different containers depending on process |
| T3 | Dual-Read-Path Drift | Two read paths for the same key can observe different values within the same process lifetime |
| T4 | Hygiene / Naming / Doc Drift | Naming, documentation, or structural issues that don't directly cause incorrect behavior |

## T1: Reachable Contradictions

### T1.1 — Completion-transition: `isDictating` outlives `isRecording`
**Tier**: T1
**Evidence**: `DictationViewModel.swift:62`, `DictationViewModel.swift:87`, `ReminderDictation.swift:93`, `ReminderDictation.swift:94`, `ReminderDictation.swift:153`
**Description**: The UI can show a "Recording" indicator for up to 1 second while the microphone is not capturing audio. `startDictation()` sets `isDictating = true` at `DictationViewModel.swift:62` and only clears it at `:87`, the final statement of the function — after the parse/add phases and the 1 s feedback sleep (`:81-82`). The recorder, by contrast, sets `isRecording = true` at `ReminderDictation.swift:93` and tears down with `defer { tearDownRecording() }` at `:94`, so `isRecording` returns to `false` (`:153`) as soon as the transcribe scope exits (`transcribe` is awaited at `DictationViewModel.swift:66`) — before the parse/add/sleep phases. During the gap `isDictating = true ∧ isRecording = false`: the bottom bar's dictation branch (`ContentView.swift:615`) renders the pulsing `recordingIndicator` (`:623`) while no speech is being captured. Note on naming: this is the dictation cluster; the "completion-transition" label is the plan's T1.1 slot designation — see the cluster mapping below (the watch completion-transition cluster itself proved contradiction-free in `clusters.md`).
**Action**: Pull `isDictating = false` into the `isRecording` teardown path so the UI never shows "Recording" when the mic is off. Separate ticket.

### T1.2 — Watch counter echo: stale `.standard` value pushed to phone's App Group
**Tier**: T1
**Evidence**: `WatchAppViewModel.swift:161`, `WatchAppViewModel.swift:186`
**Description**: On a group-registered watch, the phone writes `completionCount` into the App Group, and the watch's receive hook also writes to `AppGroup.defaults` (`WatchAppViewModel.swift:186`). But `pushAll()` reads the counter from the watch service's `.standard`-backed `CompletionCounterStore` (`WatchAppViewModel.swift:161`), which can hold a stale value from a prior receive cycle. The stale value can echo back to the phone's App Group, effectively rolling the count back.
**Action**: Unify the watch counter to a single container. Requires the group-registered watch harness (new test target). Separate spike ticket.

## T2: Cross-Target Divergence

### T2.1 — AppGroup-vs-`.standard` namespace collapse
**Tier**: T2
**Evidence**: `AppGroup.swift:13-14`, `WatchAppViewModel.swift:155-161`, `ContentView.swift:115-132`
**Description**: `AppGroup.defaults` is literally `.standard` when the group entitlement is absent (watchOS, previews, unregistered simulators). The watch explicitly pins 7 stores to `.standard` (`WatchAppViewModel.swift:155-161`). On iOS, 11 keys live in the group container (`ContentView.swift:115-132`); on watchOS, the same logical keys live in `.standard` — the same logical value exists under one name across two containers depending on process. This is the root cause of the counter echo (T1.2) and the watch double-persistence (T2.3).
**Action**: Top refactor candidate. Decide target topology (single suite? group on both? hybrid?) in a design-phase spike. The group-registered watch harness is a prerequisite. Separate spike + refactor tickets.

### T2.2 — Branch ordering divergence: widget checks empty before allSkipped
**Tier**: T2
**Evidence**: `ContentView.swift:353-390`, `WatchReminderView.swift:79-88`, `NextThingWidget.swift:62-94`
**Description**: iOS checks `allSkipped` first (`ContentView.swift:358`) and renders empty-state copy only afterwards (`:372-373`); the widget checks `store.reminders.isEmpty` first (`NextThingWidget.swift:74` → `.empty(hasHidden)` at `:77`) and derives `.allDone` from a bare `visibleReminders.first` guard (`:83-86`) rather than the shared `allSkipped` computed property; the watch orders ghost → `allSkipped` → first card → empty (`WatchReminderView.swift:79-88`). Semantically equivalent today (no unreachable path — `allSkipped` requires non-empty reminders per `ReminderStore.swift:138-139`), but structurally divergent — future changes to one branch ordering may miss the others.
**Action**: Converge on a single `ListContent` enum (see Enum Sketch 3). Deferred to refactor ticket.

### T2.3 — Watch double-persistence on show* receive
**Tier**: T2
**Evidence**: `SkippedReminderSyncService.swift:338-359`, `ShowDateState.swift:21-23,28`
**Description**: Received `showDate`/`showList`/`showRecurrence`/`showAlarms`/`showCompletionGlow` values are written twice into `.standard` — once by the service store (`SkippedReminderSyncService.swift:338-359`, stores injected `.standard` per T2.1) and again by the hook's `Show*State.apply()` (`ShowDateState.swift:22-23`, identical in all five; each state holder constructs its own `.standard`-backed preference at `:28`). Redundant but currently harmless because both writers target the same key-suite pair.
**Action**: Collapse to one write path during the sync-contract refactor.

### T2.4 — `showCompletionGlow` straddles suites
**Tier**: T2
**Evidence**: `ContentView.swift:132`, `AppViewModel.swift:247`, `ShowCompletionGlowState.swift:27`
**Description**: iOS writes `showCompletionGlow` to App Group (`ContentView.swift:132`), but the reset seam removes it from `.standard` (`AppViewModel.swift:247`). On watchOS, the key lives in `.standard` (`ShowCompletionGlowState.swift:27`). The key effectively exists in different suites depending on the writing process.
**Action**: Resolved by the suite-migration refactor (T2.1).

## T3: Dual-Read-Path Drift

### T3.1 — 12 keys with dual read paths
**Tier**: T3
**Evidence**: `ContentViewModel.swift:45-46` (`enableActionButtons`), `AppViewModel.swift:127` (`notificationsEnabled`), `AppViewModel.swift:131-132` (`intervalHours`), `AppDelegate.swift:53-56` (`allowsLandscape`), `AppearanceMode.swift:80` (`appearanceMode`), `ShowDatePreference.swift:20` (`showDate`), `ShowListPreference.swift:20` (`showList`), `ShowRecurrencePreference.swift:20` (`showRecurrence`), `ShowAlarmsPreference.swift:20` (`showAlarms`), `ShowCompletionGlowPreference.swift:20` (`showCompletionGlow`), `ShowUndatedRemindersPreference.swift:19` (`showUndatedReminders`), `SortOption.swift:35` (`sortOption`)
**Description**: 12 keys (`enableActionButtons`, `notificationsEnabled`, `notificationIntervalHours`, `allowsLandscape`, `appearanceMode`, and the 7 show* keys) are read through both `@AppStorage` (which SwiftUI observes) and a raw `UserDefaults.*` call. In normal operation both read the same underlying value, but `@AppStorage` refreshes on `UserDefaults.didChangeNotification` while raw reads reflect the value at call time. A write that lands after `@AppStorage`'s last observed notification but before a raw read could produce a transient divergence.
**Action**: Converge each key to a single read path during the refactor. Deferred.

## T4: Hygiene

### T4.1 — Magic literal `100` for freemium cap
**Tier**: T4
**Evidence**: `ReminderStore.swift:145`, `WatchAppViewModel.swift:27`, `ReminderStoreGateTests.swift:25,31,45,58,83,132`, `ReminderStoreTests.swift:591`, `SingleThreadUITestsFlows.swift:640,662,674,701`
**Description**: The freemium cap `100` is a bare literal scattered across 7+ sites with no named constant. The boundary is strict `<` (`ReminderStore.swift:145` — gate closes at exactly 100), and any future refactor must preserve this semantics.
**Action**: Extract `static let freemiumCap = 100` to a single source of truth. Deferred to the refactor ticket. Tests that reference the literal must update to use the constant.

### T4.2 — Doc drift: `AppGroup.swift` comment stale
**Tier**: T4
**Evidence**: `AppGroup.swift:3-4`, `AppGroup.swift:8`
**Description**: The `AppGroup` doc comment (`AppGroup.swift:3-4`) lists only skipped-reminder identifiers as the payload; the suite actually carries 11 group keys (the `@AppStorage` group declarations at `ContentView.swift:115-132` plus the store-backed `skippedReminderIdentifiers`, `excludedListTitles`, `completionCount`, `pendingCompletionIdentifiers`).
**Action**: Update doc comment to list all payload keys or link to the inventory. Deferred.

### T4.3 — Doc drift: `AppViewModel.swift:211` glow duration wrong
**Tier**: T4
**Evidence**: `AppViewModel.swift:211`, `CompletionGlow.swift:27`
**Description**: The `--ui-testing-glow` comment at `AppViewModel.swift:211` claims the production glow is 0.25 s; the actual default is 0.50 (`CompletionGlow.swift:27`).
**Action**: Correct the comment. Deferred.

### T4.4 — 6 duplicated `Show*Preference` structs
**Tier**: T4
**Evidence**: `ShowDatePreference.swift:20`, `ShowListPreference.swift:20`, `ShowRecurrencePreference.swift:20`, `ShowAlarmsPreference.swift:20`, `ShowCompletionGlowPreference.swift:20`, `ShowUndatedRemindersPreference.swift:19`, `SortOption.swift:35`
**Description**: Six near-identical structs each with hand-written `init(defaults:key:)` + `isEnabled`/`set` + per-key fallback values that differ (`showDate`/`showRecurrence`/`showAlarms`/`showCompletionGlow` default `true`; `showList`/`showUndatedReminders` default `false`). `SortOptionStore` (`SortOption.swift:22-49`) is the canonical prototype. This is a structural/hygiene issue only — no data-loss risk: every wrapper reads the same key-suite pair its caller writes.
**Action**: Consolidate into a single generic `BoolPreferenceStore` parameterized by key + default. Deferred to refactor ticket.

### T4.5 — `--seed` writes unclamped `completionCount`
**Tier**: T4
**Evidence**: `AppViewModel.swift:294`, `CompletionCounterStore.swift:24,29,36,41`
**Description**: The `--seed` seam writes `completionCount` directly (`AppViewModel.swift:294`) without clamping. Production only ever writes `count+1` (increment, `CompletionCounterStore.swift:29`), `max(0,count-1)` (clamped decrement, `:36`), or reset-0 (`:41`); the raw read is 0-defaulted (`:24`). Negative values read as 0-equivalent and huge values are gated-off under `count < 100` (`ReminderStore.swift:145`), but the persisted value itself is outside production's domain. The seed seam exists to set up gating scenarios (e.g. 99 for near-cap, 100 for gated); the unclamped write is intentional but undocumented.
**Action**: Document the seed's unclamped-count behavior. Optionally clamp in the seed path to the counter's domain. Deferred.

## Cluster → Finding Mapping

| Stage-3 cluster | Finding(s) |
|---|---|
| completion-transition (watch ghost card / glow) | **T1.1** (plan slot designation) — no reachable contradiction exists (matrix fully proven in `clusters.md`); the cluster's only actionable issue is the glow-duration doc drift as **T4.3** |
| branch ordering (empty / all-done / first-card) | **T2.2** |
| entitlement gate | **T4.1** |
| dictation | **T1.1** |

## Prioritized Action List

All items below are deferred to future/separate tickets (decision #1) — none is in scope for this read-only audit:

1. **Spike**: Group-registered watch harness — prerequisite for verifying cross-container behavior (T1.2, T2.1). Requires new test target + pbxproj changes.
2. **Spike**: Sync contract redesign — decide the target topology for App Group vs `.standard`, the union-vs-replace semantics, and the watch counter source-of-truth.
3. **Refactor**: Unify suite topology (T2.1, T2.4).
4. **Refactor**: Collapse 6 × `Show*Preference` into generic `BoolPreferenceStore` (T4.4).
5. **Refactor**: Converge dual-read-path keys to single read path (T3.1).
6. **Refactor**: Fix `isDictating`/`isRecording` overlap (T1.1).
7. **Refactor**: Unify watch counter container (T1.2).
8. **Refactor**: Extract `ListContent` enum for branch ordering (T2.2).
9. **Refactor**: Collapse watch double-persistence to single write (T2.3).
10. **Refactor**: Name the freemium cap constant (T4.1).
11. **Hygiene**: Fix doc comments — `AppGroup.swift:3-4` (T4.2), `AppViewModel.swift:211` (T4.3).
12. **Hygiene**: Document `--seed` unclamped count (T4.5).