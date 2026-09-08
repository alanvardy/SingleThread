
### Changes

#### 1. Create `audit/enums.md`
**File**: `.pi/qrspi/<branch>/audit/enums.md`
**Action**: create

**Content structure**:

```markdown
# Enum Assessment

## Overview

All bare-Bool/Int clusters are enumerated. Only the three highest-value
candidates receive full enum sketches; the rest get advisory pointers
with `file:line` citations per decision #3.

## Enum Sketch 1: CompletionTransition (watchOS)

**Replaces**: `isShowingCompletionTransition` (Bool) + `transitionReminder` (EKReminder?) + `CompletionGlow.isActive` (Bool)
**Sources**: `WatchReminderViewModel.swift:47,51`, `CompletionGlow.swift:21`

### Sketch

```swift
enum CompletionPhase: Equatable {
  case resting
  case completing(reminder: EKReminder, glowActive: Bool)
  // buffer window: glow expired, card still shown
  case completing(reminder: EKReminder, glowActive: Bool) // glowActive=false = buffer
}
```

Note: `completing(reminder:glowActive:)` captures both the glow-active and buffer (glow-expired-but-card-shown) states with a single case + Bool parameter. The `transitionReminder?` and flag Bool collapse into one optional associated value.

### Transition logic sketch

```swift
private var completionPhase: CompletionPhase = .resting

func completeCurrentReminder() {
  guard completionPhase == .resting else { return }
  guard let snapshot = store.visibleReminders.first else { return }
  let glowActive = showCompletionGlowState.isEnabled
  completionPhase = .completing(reminder: snapshot, glowActive: glowActive)
  if glowActive { glow.trigger() }
  Task {
    // ... EventKit work ...
    try? await Task.sleep(for: .seconds(0.5 + 0.5))
    completionPhase = .resting
  }
}
```

### Patterns
- **Persistence**: none — transient watch-only state; no rawValue/CaseIterable/defaultsKey needed
- **Presentation**: extension on the enum in the watch app target (presentation-concern separation)

## Enum Sketch 2: EntitlementGate (iOS + watchOS)

**Replaces**: `isEntitled` (Bool) + `hasResolvedEntitlement` (Bool) + `completionCounter.count` (Int) + magic literal `100`
**Sources**: `EntitlementStore.swift:54,60`, `CompletionCounterStore.swift:24-27`, `ReminderStore.swift:144-145`

### Sketch

```swift
enum EntitlementTier {
  case unresolved
  case freemium(completionsUsed: Int, cap: Int)
  case unlimited
  // or: case premium — naming bikeshed deferred

  var canMutate: Bool {
    switch self {
    case .unresolved: false
    case .freemium(let used, let cap): used < cap
    case .unlimited: true
    }
  }
}
```

### Constants extract

```swift
extension EntitlementTier {
  static let freemiumCap = 100  // single source of truth
}
```

### Patterns
- **Persistence**: `EntitlementStore` remains StoreKit-derived (not persisted); `completionCount` remains persisted as Int; the tier is computed from `isEntitled + count < cap`
- **Presentation**: on the enum (app-target type) or in extension for Core-owned — if Core owns, present in extension
- **Round-trip**: not applicable (computed, not persisted); the `completionCount` Int retains its current `CompletionCounterStore` persistence

## Enum Sketch 3: EmptyState (iOS + widget)

**Replaces**: `allSkipped` (computed Bool) + `hasHidden` (Bool) + `reminders.isEmpty` (implicit) + per-target branch ordering
**Sources**: `ReminderStore.swift:62,138-140`, `ContentView.swift:355-455`, `NextThingWidget.swift:55-95`, `WatchReminderView.swift:77-91`

### Sketch

```swift
enum ListContent {
  case noAccess
  case empty(hasHiddenSubtle: Bool)
  case allDone
  case reminder(ReminderDisplay)
}
```

This is effectively the widget's `NextThingEntry.State` (:10-14) generalized — the widget already has this enum but only within its own process. The sketch proposes extracting it to Core so all three targets consume the same enum.

### Patterns
- **Persistence**: none — derived/computed; no rawValue/CaseIterable needed
- **Presentation**: extension in Core (Core is SwiftUI-free); each target renders the enum with exhaustive `switch` per the widget's pattern (`NextThingWidget.swift:140`)

## Advisory Pointers (Full Enum Sketches NOT Produced)

### `show*` Bool cluster (6 keys)
**What**: `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`, `showUndatedReminders` — each is a separate Bool with its own wrapper struct, fallback, and dual-read path.
**Why not sketched**: The consolidation refactor (collapsing 6 × `Show*Preference` + `ShowUndatedRemindersPreference` into a single generic struct) is a higher-priority structural cleanup; turning them into an enum adds a dimension the struct consolidation should address first.
**Pointers**: `ShowDatePreference.swift:20`, `ShowListPreference.swift:20`, `ShowRecurrencePreference.swift:20`, `ShowAlarmsPreference.swift:20`, `ShowCompletionGlowPreference.swift:19-21`, `ShowUndatedRemindersPreference.swift:19`, `ShowDateState.swift:25-28` (×5 identical double-persistence), `ContentView.swift:121-132` (@AppStorage declarations).

### Dictation two-machine state
**What**: `isDictating` + `isRecording` + `dictationText` + `dictationError` + `creationFeedback` — five fields across two machines.
**Why not sketched**: The core divergence (`isDictating` outliving `isRecording`) is a timing-path bug, not a state-model gap; a state enum would not fix the overlap window. The fix is structural (pull `isDictating=false` into the `isRecording` teardown path), not a refactor.
**Pointers**: `DictationViewModel.swift:22-25,62-87`, `ReminderDictation.swift:93-94,107-109,153`.

### `BackgroundFade` Int namespace
**What**: `backgroundFadePercent: Int` with step=10, clamp 0...90, no enum cases. Already has `BackgroundFade.allValues` stride + `opacity(for:)`.
**Why not sketched**: The `BackgroundFade` namespace is already well-structured (case-less, Int range, computed opacity); converting to an enum would not improve type safety and would add persistence complexity for a single-key value.
**Pointers**: `BackgroundFade.swift:13-36`, `ContentView.swift:89`.

### Watch refresh UI flags
**What**: `isRefreshing` + `isShowingRefreshConfirmation` — two transient Bools.
**Why not sketched**: Two-state transient UI flags with straightforward clear paths; no combinatorial risk beyond the normal `isRefreshing`→`isShowingRefreshConfirmation`→clear sequence.
**Pointers**: `WatchReminderViewModel.swift:43-44`.
```

### Verification

#### Automated
- [ ] Three enum sketches present (count sections titled "Enum Sketch N:" = 3)
- [ ] Each sketch's `replaces` fields resolve as real keys in `factbase.tsv` — grep each field name
- [ ] Advisory pointers section enumerates all remaining bare-Bool/Int clusters from research Q4: `show*` ×6, dictation, `BackgroundFade`, watch refresh flags
- [ ] `bash audit/verify-citations.sh` still exits 0

#### Manual
- [ ] Sketch 1 (`CompletionTransition`) adheres to patterns: no persistence needed (transient watch-only), presentation on extension
- [ ] Sketch 2 (`EntitlementGate`) adheres to patterns: `canMutate` computed from enum, single `freemiumCap` constant
- [ ] Sketch 3 (`EmptyState`) mirrors widget's existing `NextThingEntry.State` shape (:10-14) generalized
- [ ] No full enum sketched for advisory-pointer items — pointers only, no case lists

---

