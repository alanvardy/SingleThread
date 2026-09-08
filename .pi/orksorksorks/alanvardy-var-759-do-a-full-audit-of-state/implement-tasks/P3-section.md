
### Changes

#### 1. Create `audit/clusters.md`
**File**: `.pi/qrspi/<branch>/audit/clusters.md`
**Action**: create

**Content structure**:

```markdown
# Combinatorial Clusters & Cross-Target Divergence

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
| false | nil | inactive | **reachable** (resting state) | Normal card |
| true | ≠nil | active | **reachable** (complete path, glow enabled, no re-entry) | Ghost card + green overlay (`WatchReminderView.swift:79-81,97-98`) |
| true | ≠nil | inactive | **reachable** (buffer window: glow expired, card still shown) | Ghost card without glow overlay |
| true | nil | — | **unreachable** (proven: no path sets `isShowingCompletionTransition` without also setting `transitionReminder` — both set together under guard :66-67) | N/A |
| false | ≠nil | — | **unreachable** (proven: `transitionReminder` only set when flag is true, cleared together :78-81) | N/A |
| — | — | active when glow disabled | **unreachable** (proven: glow gate `showCompletionGlowState.isEnabled` :69; disabled → never set :68-69,85-86) | N/A |

### Transition Path
1. User taps Complete → guard `!isShowingCompletionTransition` (:66) → sets flag true, snapshots `store.visibleReminders.first` as `transitionReminder` (:67)
2. If `showCompletionGlowState.isEnabled` → `glow.trigger()` (:69)
3. Timed clear at `glow.duration + completionTransitionBuffer` (:72-84) → both flag and reminder set nil (:78-81); if complete fails → nil + no glow (:85-86)
4. Ghost-card buttons live (act on next visible reminder) except Complete (blocked by :66 guard)

**Documentation Drift**: `AppViewModel.swift:211` comment claims production glow is 0.25 s; actual default is 0.50 (`CompletionGlow.swift:26`)

## Cluster 2: Empty / All-Done / First-Card Branch Ordering

### State Vector
| Field | Type | Source |
|---|---|---|
| `reminders` (store) | `[EKReminder]` | `ReminderStore.swift:55` |
| `hasHidden` | Bool | `ReminderStore.swift:62` |
| `allSkipped` | computed Bool | `ReminderStore.swift:138-140` |
| `authorizationStatus` | `EKAuthorizationStatus` | `ReminderStore.swift:65` |

`allSkipped = !reminders.isEmpty && visibleReminders.isEmpty`

### iOS Branch Order (`ContentView.swift:355-455`, behind auth gate `:339-349`)

| `reminders` | `allSkipped` | `hasHidden` | Reachability | Renders |
|---|---|---|---|---|
| non-empty | false | — | **reachable** (normal) | First visible reminder card (:390) |
| non-empty | true | — | **reachable** (all visible reminders skipped) | All-Done card (:358), refreshable with `clearSkipped: true` (:371-374), no bottomBar |
| empty | false | false | **reachable** (fresh install) | "No Reminders yet" (:373) |
| empty | false | true | **reachable** (all hidden, none visible) | `emptyStateCopy(hasHidden: true)` → "Nothing due" (`ContentViewModel.swift:58-74`) |
| `empty ∧ allSkipped=true` | — | — | **unreachable** (proven: `allSkipped` requires `!reminders.isEmpty` at `ReminderStore.swift:138-140`) | N/A |

**Branch priority**: `allSkipped` checked first (:358) — wins over `hasHidden` when reminders non-empty but all skipped.

### Watch Branch Order (`WatchReminderView.swift:77-91`)

| Condition | Renders |
|---|---|
| `isShowingCompletionTransition` (ghost) | All-Done card (:82-83, def :155-160) |
| `visibleReminders.first` exists | First card (:84-85) |
| else (empty) | No-Reminders (:86-88), subtitle `hasHidden ? "Nothing due…" : "No Reminders yet"` (:169) |

### Widget Branch Order (`NextThingWidget.swift:55-95`)
**Different from iOS and watch**: auth checked first, empty checked *before* all-skipped.

| Condition | Entry State | Order |
|---|---|---|
| `authorizationStatus ≠ .fullAccess` | `.noAccess` | 1st (:55-58) |
| `allSkipped == true` (but only reachable from non-empty) | `.allDone` | 3rd (:83-87) — checked **after** `.empty` |
| `reminders.isEmpty` | `.empty(hasHidden)` | 2nd (:74-79) — checked **before** `.allDone` |
| has visible first card | `.reminder(ReminderDisplay)` | 4th (:89-95) |

**Divergence**: widget checks `isEmpty` before `allSkipped`, but `allSkipped` requires non-empty (so no unreachable path). However, the ordering *flips*: on iOS, `allSkipped` outranks empty-subtitle selection; on widget, `isEmpty` outranks `allSkipped` in the entry state enum — semantically equivalent but structurally divergent (risk: future changes to one branch ordering may miss the others).

Rendering consumes `NextThingEntry.State` via exhaustive `switch` (:140) — enum defined :10-14.

## Cluster 3: Entitlement Gate

### State Vector
| Field | Type | Source |
|---|---|---|
| `EntitlementStore.isEntitled` | Bool | `EntitlementStore.swift:54` |
| `EntitlementStore.hasResolvedEntitlement` | Bool | `EntitlementStore.swift:60` |
| `completionCounter.count` | Int | `CompletionCounterStore.swift:24-27` |
| `canMutate` | computed Bool | `ReminderStore.swift:144-145` |

`canMutate = entitlementStore.isEntitled || completionCounter.count < 100` (strict `<`, no named constant)

### Reachability Matrix — iOS Bottom Bar (`ContentView.swift:615-645`)

| `hasResolvedEntitlement` | `isEntitled` | `count` | `canMutate` | Renders |
|---|---|---|---|---|
| false | false | any | false | `EmptyView()` (:626-627) — unresolved, show nothing |
| true | false | < 100 | true | Mic/action cluster (:628-633) |
| true | false | ≥ 100 | false | Upgrade prompt (:629-630, `UpgradePromptButton` `PurchaseSettingsView.swift:174-196`) |
| true | true | any | true | Mic/action cluster |

### Reachability Matrix — Watch Card (`WatchReminderView.swift:219-224`)

| `canMutate` | `entitlementState.isEnabled` | Renders |
|---|---|---|
| false | false | Static "Upgrade on your iPhone" (:219-224, def :139-153) |
| true | false | Live buttons (silent no-op mutations) |
| false | true | Live buttons (silent no-op mutations) |
| true | true | Live buttons (functional) |

**Boundary**: at exactly 100 the gate closes — `count < 100` not `<= 100`. Test coverage: `ReminderStoreGateTests.swift:18-38`.

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
| false | false | "" | nil | nil | **reachable** (idle) | Mic button |
| true | true | live text | nil | nil | **reachable** (actively recording) | Live text + pulsing recording indicator (`ContentView.swift:615-622`) |
| true | false | partial | nil | nil | **reachable** (gap: mic tore down, parse/add/sleep still running — `isDictating` only cleared in `finally` :87) | "Recording" indicator shown but mic not capturing |
| true | — | — | ≠nil | nil | **reachable** (error during dictation) | Error wins render (`ContentView.swift:606-610`) |
| true | — | — | — | `.success`/`.failure` | **reachable** (feedback window, 1 s after speech ends :81-82) | Feedback icon while still dictating (`ContentView.swift:612-613`) |
| false | true | — | — | — | **unreachable** (proven: `isRecording` true only while `prepareRecording` succeeds :93; teardown resets :94, :153; no path sets `isRecording` without `isDictating` first) | N/A |

**Key finding**: `isDictating` remains true during the 1 s feedback window after speech ends (`finally` block :87), so the UI shows "Recording" when the mic is not capturing. `isRecording` is false during parse/add phases after teardown (:94) but `isDictating` still true.

**`showMicrophoneButton=false`**: suppresses mic-holders only, not error/recording/feedback branches. Watch has no dictation UI.

## Divergence Sites: App Group vs `.standard`

### Divergence Site Index (11 sites)

| # | Site | Description | Source |
|---|---|---|---|
| 1 | Phone service store construction | `AppViewModel.swift:31-37` — service built with default (App Group) stores | `AppViewModel.swift:31-37` |
| 2 | Watch service explicit `.standard` | `WatchAppViewModel.swift:155-161` — 7 stores injected `.standard`, `SkippedReminderStore()` left default | `WatchAppViewModel.swift:155-161` |
| 3 | Phone @AppStorage pinned App Group | `ContentView.swift:115-132` — 11 keys use `store: AppGroup.defaults` | `ContentView.swift:115-132` |
| 4 | Phone preference observer diffs group only | `AppViewModel.swift:380-392` — `UserDefaults.didChangeNotification` on `AppGroup.defaults`, diffs only 5 `lastShow*` | `AppViewModel.swift:368-400` |
| 5 | Widget reads true App Group | `NextThingWidget.swift:61-73` — widget runs with group entitlement, no fallback | `NextThingWidget.swift:59-73` |
| 6 | Watch launch restore `.standard` | `WatchAppViewModel.swift:31,37` — `SortOptionStore().load()`/`ShowUndatedRemindersPreference(defaults: .standard)` | `WatchAppViewModel.swift:30-37` |
| 7 | Watch count asymmetry | Service counter `.standard` (:161) vs receive write `AppGroup.defaults` (:186) vs UI-test seed `AppGroup.defaults` (:27) vs store default `AppGroup.defaults` | `WatchAppViewModel.swift:27,161,186` |
| 8 | Phone seed unclamped count | `AppViewModel.swift:294` — `AppGroup.defaults.set(count)` unclamped | `AppViewModel.swift:294` |
| 9 | Reset clears both suites | `UITestingSeed.swift:52-58` — wipes both `.standard` and App Group | `UITestingSeed.swift:52-58` |
| 10 | PendingCompletionStore doc | `PendingCompletionStore.swift:7-11` — notes watchOS no-App-Group fallback | `PendingCompletionStore.swift:7-11` |
| 11 | Test stores isolate suites | `EntitlementSyncTests.swift:124-127` — UUID keys "never touches `AppGroup.defaults`" | `EntitlementSyncTests.swift:124-127` |

### Watch Double-Persistence Detail

For five `show*` keys on the watch receive path (excluding `showUndatedReminders` and `showCompletionGlow` which each have their own pattern):

1. Service store writes `.standard` via `SkippedReminderSyncService.swift:337-359` (stores injected `.standard`)
2. Hook's `Show*State.apply()` writes `.standard` again via `preference.set(value); isEnabled = value` (`ShowDateState.swift:25-28`, identical in all five)

Each `Show*State` constructs its own `Show*Preference(defaults: .standard)` (:30) independently of the service store — same key, same suite, two writers.

### Watch Counter Echo Risk

Watch `pushAll()` reads counter from its `.standard` store at `WatchAppViewModel.swift:161`. Phone receive writes counter to `AppGroup.defaults` at `WatchAppViewModel.swift:186`. On a group-registered watch, these are different containers — the watch can echo a stale `.standard` counter value back to the phone's App Group.

## Open Areas (Not Asserted)

| Area | Reason |
|---|---|
| Group-registered watch behavior | All watch tests run `.standard` because `AppGroup.defaults` falls back (`AppGroup.swift:10-14`); real cross-container divergence is unverifiable on simulator |
| Second `EntitlementStore` on watch | `WatchAppViewModel.swift:162` — a never-read instance inside the service; interplay with `canMutate` only partially traced |
| `--ui-testing-live-excluded` interaction | `WatchAppViewModel.swift:237-246` injects WC context 5 s post-launch; phone-side receive hooks only partially traced |
| Phone receipt of non-`pushAll` contexts | Watch `allSends* = false` (`WatchAppViewModel.swift:154-163`); unverified whether any other path could push a mis-handled context |
```

### Verification

#### Automated
- [ ] Every `reachable` combo's `path` note resolves in `factbase.tsv` — grep each cited `file:line` from every reachable row
- [ ] Every `unreachable(proven)` claim: the stated impossibility is verified by checking no write path exists in `factbase.tsv` that could produce the claimed vector (e.g. `empty ∧ allSkipped`: `allSkipped` requires `!reminders.isEmpty` per `ReminderStore.swift:138-140`)
- [ ] All four cluster matrices have zero bare `undefined` cells (only the four listed open areas are marked undefined)
- [ ] All 11 divergence sites carry `file:line` citations that resolve in Stage 2's `inventory.md`
- [ ] `bash audit/verify-citations.sh` still exits 0

#### Manual
- [ ] Walk the completion-transition reachability path: read `WatchReminderViewModel.swift:66-86`, verify the `true,nil` row is correctly proven unreachable
- [ ] Walk the allSkipped impossibility: read `ReminderStore.swift:138-140`, confirm `allSkipped` requires non-empty reminders
- [ ] Verify widget branch ordering divergence: compare `NextThingWidget.swift:55-95` against `ContentView.swift:355-455` and `WatchReminderView.swift:77-91`
- [ ] Spot-check 3 divergence site citations against source

---

