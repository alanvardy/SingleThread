# Combinatorial Clusters & Cross-Target Divergence

> **Plan-drift corrections applied** (re-verified against source at implementation time):
> All line numbers below were re-checked against the actual files. Notable deltas from plan.md:
> `CompletionGlow.duration` is declared at `CompletionGlow.swift:27` (not `:26`);
> `WatchReminderViewModel.swift:70` sets the flag and `:67` snapshots the reminder (plan had the
> order/cites as "set flag, snapshot" at `:66-67`); the timed clear lives in the `Task` at
> `:73-84` and clears the pair at `:82-83`; the fail path clears only `transitionReminder` at
> `:86` (flag never set) — the `false,≠nil` row proof is corrected accordingly (transient
> window, no distinct render). The watch upgrade prompt is defined at `WatchReminderView.swift:135-147`
> (plan `:139-153`); the no-reminders subtitle is `:163` (plan `:169`); the App Group
> declarations are `ContentView.swift:115-133`; the widget entry-state build is
> `NextThingWidget.swift:68-98`; the phone preference observer is `AppViewModel.swift:366-398`;
> `Show*State.apply()` is `:21-24` with its `.standard` preference at `:28`.

## Cluster 1: Completion-Transition (watchOS)

### State Vector
| Field | Type | Source |
|---|---|---|
| `isShowingCompletionTransition` | Bool | `WatchReminderViewModel.swift:47` |
| `transitionReminder` | `EKReminder?` | `WatchReminderViewModel.swift:51` |
| `CompletionGlow.isActive` | Bool | `CompletionGlow.swift:21` |

### Reachability Matrix

| `isShowingCompletionTransition` | `transitionReminder` | `glow.isActive` | Reachability | Renders |
|---|---|---|---|---|
| false | nil | inactive | **reachable** (resting state; guard at `:66` passes, ghost branch at `WatchReminderView.swift:79` skipped) | Normal card |
| true | ≠nil | active | **reachable** (complete path, glow enabled, no re-entry) | Ghost card + green overlay (`WatchReminderView.swift:79-81,97-98`) |
| true | ≠nil | inactive | **reachable** (buffer window: glow expired via `CompletionGlow.swift:39`, card still shown until `:82-83`) | Ghost card without glow overlay |
| true | nil | — | **unreachable** (proven: the only flag write `:70` sits inside the guarded block after the snapshot `:67`; the snapshot is non-nil exactly when `store.completeCurrentReminder()` can succeed — `ReminderStore.swift:227` — so flag=true implies `transitionReminder ≠ nil`) | N/A |
| false | ≠nil | — | **not reachable as a rendered state** (proven: `transitionReminder` has exactly one writer, `:67`; every completion of that line resolves to either flag=true on the same guarded path `:68-70` or an immediate nil clear at `:86` — never a settled `false ∧ ≠nil` vector, and the ghost branch requires the flag at `:79-80`, so any MainActor sub-state during the `:68` await renders identically to the resting row) | Normal card (identical to `false,nil`) |
| — | — | active when glow disabled | **unreachable** (proven: `trigger()` is gated behind `showCompletionGlowState.isEnabled` at `:68-69`; with the gate off neither `:71` nor any other path calls `trigger()`, whose only `isActive=true` write is `CompletionGlow.swift:33`) | N/A |

### Transition Path
1. User taps Complete → guard `!isShowingCompletionTransition` (`:66`) → snapshots `store.visibleReminders.first` as `transitionReminder` (`:67`)
2. If `store.completeCurrentReminder()` succeeds ∧ `showCompletionGlowState.isEnabled` (`:68-69`) → sets flag true (`:70`), triggers glow (`:71`)
3. Timed clear at `completionGlow.duration + completionTransitionBuffer` (`:72`): after the sleep the `Task` (`:73-84`) clears both flag and reminder (`:82-83`); if completion fails → `transitionReminder = nil`, no flag, no glow (`:85-86`)
4. Ghost-card buttons stay live (act on the next visible reminder) except Complete (blocked by the `:66` guard)

**Documentation Drift**: `AppViewModel.swift:211` comment claims production glow is 0.25 s; actual default is 0.50 (`CompletionGlow.swift:27`)

## Cluster 2: Empty / All-Done / First-Card Branch Ordering

### State Vector
| Field | Type | Source |
|---|---|---|
| `reminders` (store) | `[EKReminder]` | `ReminderStore.swift:55` |
| `hasHidden` | Bool | `ReminderStore.swift:62` |
| `allSkipped` | computed Bool | `ReminderStore.swift:138-139` |
| `authorizationStatus` | `EKAuthorizationStatus` | `ReminderStore.swift:65` |

`allSkipped = !reminders.isEmpty && visibleReminders.isEmpty` (`ReminderStore.swift:138-139`)

### iOS Branch Order (`ContentView.swift:353-461`, behind auth gate `:339-351`)

| `reminders` | `allSkipped` | `hasHidden` | Reachability | Renders |
|---|---|---|---|---|
| non-empty | false | — | **reachable** (normal) | First visible reminder card (`ContentView.swift:390`) |
| non-empty | true | — | **reachable** (all visible reminders skipped) | All-Done card (`:358`), refreshable with `clearSkipped: true` (`:370`), no bottomBar |
| empty | false | false | **reachable** (fresh install) | `emptyStateCopy(hasHidden: false)` → "No Reminders yet" (`:373`, `ContentViewModel.swift:58-75`) |
| empty | false | true | **reachable** (all hidden, none visible) | `emptyStateCopy(hasHidden: true)` → "Nothing due" (`ContentViewModel.swift:58,61`) |
| `empty ∧ allSkipped=true` | — | — | **unreachable** (proven: `allSkipped` requires `!reminders.isEmpty` at `ReminderStore.swift:138-139`) | N/A |

**Branch priority**: `allSkipped` checked first (`:358`) — wins over `hasHidden` when reminders non-empty but all skipped.

### Watch Branch Order (`WatchReminderView.swift:77-91`)

| Condition | Renders |
|---|---|
| `isShowingCompletionTransition` ∧ `transitionReminder` (ghost) | Ghost card (`:79-81`) |
| `visibleReminders.first` exists | First card (`:84-85`) |
| else (empty) | No-Reminders (`:86-88`), subtitle `hasHidden ? "Nothing due…" : "No Reminders yet"` (`:163`) |

Watch checks the ghost before `allSkipped`/empty — a fresh completion renders the ghost even when `visibleReminders` is already empty.

### Widget Branch Order (`NextThingWidget.swift:62-98`)
**Different from iOS and watch**: auth checked first, empty checked *before* all-skipped.

| Condition | Entry State | Order |
|---|---|---|
| `authorizationStatus ≠ .fullAccess` | `.noAccess` | 1st (`:68-69`) |
| `reminders.isEmpty` | `.empty(hasHidden)` | 2nd (`:74-77`) — checked **before** all-skipped |
| `allSkipped == true` (guard `visibleReminders.first` nil, only reachable from non-empty) | `.allDone` | 3rd (`:83-86`) |
| has visible first card | `.reminder(ReminderDisplay)` | 4th (`:94`) |

**Divergence**: the widget checks `isEmpty` before the `visibleReminders.first` guard that yields `.allDone`, while the iOS `ContentView` checks `allSkipped` before `reminders.isEmpty`. Because `allSkipped` requires non-empty reminders (`ReminderStore.swift:138-139`), the widget produces no unreachable path today — the ordering flip is semantically equivalent but structurally divergent (risk: future changes to one branch ordering may miss the others).

Rendering consumes `NextThingEntry.State` via exhaustive `switch` (`:140`) — enum defined `:10-14`.

## Cluster 3: Entitlement Gate

### State Vector
| Field | Type | Source |
|---|---|---|
| `EntitlementStore.isEntitled` | Bool | `EntitlementStore.swift:54` |
| `EntitlementStore.hasResolvedEntitlement` | Bool | `EntitlementStore.swift:60` |
| `completionCounter.count` | Int | `CompletionCounterStore.swift:23-24` |
| `canMutate` | computed Bool | `ReminderStore.swift:144-145` |

`canMutate = entitlementStore.isEntitled || completionCounter.count < 100` (strict `<`, no named constant)

### Reachability Matrix — iOS Bottom Bar (`ContentView.swift:625-637`)

| `hasResolvedEntitlement` | `isEntitled` | `count` | `canMutate` | Renders |
|---|---|---|---|---|
| false | false | any | false | `EmptyView()` (`:626-627`) — unresolved, show nothing |
| true | false | < 100 | true | Mic/action cluster (`:628-633`) |
| true | false | ≥ 100 | false | Upgrade prompt (`:629-630`, `UpgradePromptButton` def `PurchaseSettingsView.swift:174-196`) |
| true | true | any | true | Mic/action cluster |

### Reachability Matrix — Watch Card (`WatchReminderView.swift:219-222`)

| `canMutate` | `entitlementState.isEnabled` | Renders |
|---|---|---|
| false | false | Static "Upgrade on your iPhone" (`:219-220`, def `:135-147`) |
| true | false | Live buttons (silent no-op mutations) |
| false | true | Live buttons (silent no-op mutations) |
| true | true | Live buttons (functional) |

**Boundary**: at exactly 100 the gate closes — `count < 100` not `<= 100`. Test coverage: `ReminderStoreGateTests.swift:18-38` (below-100 entitles at `:18-21`; at-100 not-entitled gates at `:24-27`; at-100 entitled stays open at `:30-33`; `completeReminder` gated returns false at `:45-58`).

**No named constant**: literal `100` scattered across `ReminderStore.swift:145`, `WatchAppViewModel.swift:27`, `ReminderStoreGateTests.swift:25,31,45,58,83,132`, `ReminderStoreTests.swift:591`, `SingleThreadUITestsFlows.swift:640,662,674,701`.

## Cluster 4: Dictation State

### State Vector
| Field | Type | Source |
|---|---|---|
| `DictationViewModel.isDictating` | Bool | `DictationViewModel.swift:22` |
| `DictationViewModel.dictationText` | String | `DictationViewModel.swift:23` |
| `DictationViewModel.dictationError` | String? | `DictationViewModel.swift:24` |
| `DictationViewModel.creationFeedback` | `CreationFeedback?` | `DictationViewModel.swift:25` |
| `ReminderDictation.isRecording` | Bool | `ReminderDictation.swift:107` |

### Reachability Matrix

| `isDictating` | `isRecording` | `dictationText` | `dictationError` | `creationFeedback` | Reachability | Renders |
|---|---|---|---|---|---|---|
| false | false | "" | nil | nil | **reachable** (idle) | Mic button (`ContentView.swift:624`) |
| true | true | live text | nil | nil | **reachable** (actively recording; `isRecording=true` at `ReminderDictation.swift:93`, text streamed at `DictationViewModel.swift:66-67`) | Live text + pulsing recording indicator (`ContentView.swift:615-623`) |
| true | false | partial | nil | nil | **reachable** (gap: `transcribe` returned, `defer` tore the mic down at `ReminderDictation.swift:94/153`, but parse/add/1 s feedback sleep still run — `isDictating` only cleared at `DictationViewModel.swift:87`) | "Recording" indicator shown but mic not capturing |
| true | — | — | ≠nil | nil | **reachable** (error during dictation `:84-85`) | Error wins render (`ContentView.swift:606-610`) |
| true | — | — | — | `.success`/`.failure` | **reachable** (feedback window, 1 s after speech ends `:77,79,81-82`) | Feedback icon while still dictating (`ContentView.swift:613-614`) |
| false | true | — | — | — | **unreachable** (proven: `isRecording` has a single setter `ReminderDictation.swift:93` inside `transcribe`, which is only called from `startDictation` after `isDictating = true` at `DictationViewModel.swift:62`; teardown resets it at `:94/153`; the re-entry guard `:74` never sets it) | N/A |

**Key finding**: `isDictating` remains true during the 1 s feedback window after speech ends (cleared only at `:87`), so the UI shows "Recording" when the mic is not capturing. `isRecording` is false during the parse/add phases after teardown (`ReminderDictation.swift:94`) but `isDictating` is still true.

**`showMicrophoneButton=false`**: suppresses the mic branch at `ContentView.swift:624` only, not the error (`:606`), feedback (`:613`), or recording (`:615-623`) branches. Watch has no dictation UI.

## Divergence Sites: App Group vs `.standard`

### Divergence Site Index (11 sites)

| # | Site | Description | Source |
|---|---|---|---|
| 1 | Phone service store construction | `AppViewModel.swift:32-37` — service built with default (App Group) stores | `AppViewModel.swift:32-37` |
| 2 | Watch service explicit `.standard` | `WatchAppViewModel.swift:155-161` — 7 stores injected `.standard`, `SkippedReminderStore()` left default | `WatchAppViewModel.swift:155-161` |
| 3 | Phone @AppStorage pinned App Group | `ContentView.swift:115-133` — 11 keys use `store: AppGroup.defaults` | `ContentView.swift:115-133` |
| 4 | Phone preference observer diffs group only | `AppViewModel.swift:369-370` — `UserDefaults.didChangeNotification` on `AppGroup.defaults`; `AppViewModel.swift:380-395` diffs only 5 `lastShow*` | `AppViewModel.swift:369-370,380-395` |
| 5 | Widget reads true App Group | `NextThingWidget.swift:71-73` — widget runs with group entitlement, no fallback | `NextThingWidget.swift:71-73` |
| 6 | Watch launch restore `.standard` | `WatchAppViewModel.swift:31-34` — `SortOptionStore().load()` / `ShowUndatedRemindersPreference(defaults: .standard)` | `WatchAppViewModel.swift:31-34` |
| 7 | Watch count asymmetry | Service counter `.standard` (`:161`) vs receive write `AppGroup.defaults` (`:186`) vs UI-test seed `AppGroup.defaults` (`:27`) vs store default `AppGroup.defaults` | `WatchAppViewModel.swift:27,161,186` |
| 8 | Phone seed unclamped count | `AppViewModel.swift:294` — `AppGroup.defaults.set(count)` unclamped | `AppViewModel.swift:294` |
| 9 | Reset clears both suites | `UITestingSeed.swift:54-57` — wipes both `.standard` and App Group | `UITestingSeed.swift:54-57` |
| 10 | PendingCompletionStore doc | `PendingCompletionStore.swift:8-9` — notes watchOS no-App-Group fallback (`AppGroup.swift:13-14`); store still defaults to `AppGroup.defaults` (`PendingCompletionStore.swift:21`) | `PendingCompletionStore.swift:8-9`, `AppGroup.swift:13-14`, `PendingCompletionStore.swift:21` |
| 11 | Test stores isolate suites | `EntitlementSyncTests.swift:124-127` — UUID keys "never touches `AppGroup.defaults`" | `EntitlementSyncTests.swift:124-127` |

### Watch Double-Persistence Detail

For five `show*` keys on the watch receive path (excluding `showUndatedReminders` and `showCompletionGlow`, which each have their own single-writer pattern):

1. Service store writes `.standard` via `SkippedReminderSyncService.swift:338-359` (stores injected `.standard` at `WatchAppViewModel.swift:155-160`)
2. Hook's `Show*State.apply()` writes `.standard` again via `preference.set(value); isEnabled = value` (`ShowDateState.swift:21-24`, identical in all five)

Each `Show*State` constructs its own `Show*Preference(defaults: .standard)` (`ShowDateState.swift:28`) independently of the service store — same key, same suite, two writers.

### Watch Counter Echo Risk

Watch `pushAll()` reads the counter from its `.standard` store (`WatchAppViewModel.swift:161`). The phone's receive hook writes the counter to `AppGroup.defaults` (`WatchAppViewModel.swift:186`). On a group-registered watch these are different containers — the watch can echo a stale `.standard` counter value back into the phone's App Group.

## Open Areas (Not Asserted)

| Area | Reason |
|---|---|
| Group-registered watch behavior | All watch tests run `.standard` because `AppGroup.defaults` falls back to `.standard` without the entitlement (`AppGroup.swift:13-14`); real cross-container divergence is unverifiable on the simulator |
| Second `EntitlementStore` on watch | `WatchAppViewModel.swift:162` — a never-read instance inside the service; its interplay with `canMutate` is only partially traced |
| `--ui-testing-live-excluded` interaction | `WatchAppViewModel.swift:236-248` injects a WC context 5 s post-launch; phone-side receive hooks only partially traced |
| Phone receipt of non-`pushAll` contexts | Watch `allSends* = false` (`WatchAppViewModel.swift:163-164`); unverified whether any other path could push a mis-handled context |