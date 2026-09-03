# Enum Assessment

## Overview

All bare-Bool/Int clusters are enumerated. Only the three highest-value
candidates receive full enum sketches; the rest get advisory pointers
with `file:line` citations per decision #3.

## Enum Sketch 1: CompletionTransition (watchOS)

**Replaces**: `isShowingCompletionTransition` (Bool) + `transitionReminder` (EKReminder?) + `CompletionGlow.isActive` (Bool)
**Sources**: `WatchReminderViewModel.swift:47,51`, `CompletionGlow.swift:21`
**Fact-base keys**: `isShowingCompletionTransition`, `transitionReminder`, `CompletionGlow.isActive` — all resolve as `id`s in `factbase.tsv`.

### Sketch

```swift
enum CompletionPhase: Equatable {
  case resting

  /// glowActive=true: the glow overlay is playing over the ghost card.
  /// glowActive=false: buffer window — glow expired, ghost card still shown
  /// until `completionGlow.duration + completionTransitionBuffer` elapses.
  case completing(reminder: EKReminder, glowActive: Bool)
}
```

Note: `completing(reminder:glowActive:)` captures both the glow-active and buffer (glow-expired-but-card-shown) states with a single case + Bool parameter. The `transitionReminder?` and flag Bool collapse into one optional associated value; the buffer window is expressed as the same case with `glowActive=false` rather than a second case (deliverable requirement: one case covering both sub-states, per the plan's corrected sketch intent).

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
    try? await Task.sleep(for: .seconds(completionGlow.duration + completionTransitionBuffer))
    completionPhase = .resting
  }
}
```

Advisory pseudo-code: the real watch flow (`WatchReminderViewModel.swift:66-86`) sets the transition flag only after a successful store completion and clears it unconditionally in a timed task; the sketch collapses those steps. The `completionTransitionBuffer` (0.5 s) + glow duration (0.50 s default, `CompletionGlow.swift:27`) delay references the real members.

### Patterns
- **Persistence**: none — transient watch-only state; no rawValue/CaseIterable/defaultsKey needed
- **Presentation**: extension on the enum in the watch app target (presentation-concern separation)

## Enum Sketch 2: EntitlementGate (iOS + watchOS)

**Replaces**: `isEntitled` (Bool) + `hasResolvedEntitlement` (Bool) + `completionCounter.count` (Int) + magic literal `100`
**Sources**: `EntitlementStore.swift:54,60`, `CompletionCounterStore.swift:23-25`, `ReminderStore.swift:144-145`
**Fact-base keys**: `isEntitled`, `hasResolvedEntitlement`, `completionCounter.count` — all resolve as `id`s in `factbase.tsv`; the magic literal `100` resolves via the `completionCount`/`completionCounter.count` rows (e.g. `ReminderStore.swift:145` and `ReminderStoreGateTests.swift:25`).

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
**Sources**: `ReminderStore.swift:62,138-140`, `ContentView.swift:358-455`, `NextThingWidget.swift:68-95`, `WatchReminderView.swift:77-91`
**Fact-base keys**: `allSkipped`, `hasHidden` — resolve as `id`s in `factbase.tsv`; `reminders.isEmpty` (implicit) maps to the `reminders` id (read rows at `ContentView.swift:372`, `NextThingWidget.swift:74`); per-target branch ordering maps to the `allSkipped`/`hasHidden`/`reminders` branch rows (`ContentView.swift:358,373,390`, `NextThingWidget.swift:74,83,93`, `WatchReminderView.swift:82,84,86`).

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
**Pointers**: `ShowDatePreference.swift:20` (fallback `?? true`), `ShowListPreference.swift:20` (`?? false`), `ShowRecurrencePreference.swift:20` (`?? true`), `ShowAlarmsPreference.swift:20` (`?? true`), `ShowCompletionGlowPreference.swift:19-21` (fallback `?? true`), `ShowUndatedRemindersPreference.swift:19` (`?? false`), `ShowDateState.swift:21-23` + `:28` (receive double-persistence: `apply()` writes the preference then `isEnabled` — identical in ShowListState/ShowRecurrenceState/ShowAlarmsState at `:21-23`, ShowCompletionGlowState at `:20-22`), `ContentView.swift:121-132` (@AppStorage declarations, `store: AppGroup.defaults`).

### Dictation two-machine state
**What**: `isDictating` + `isRecording` + `dictationText` + `dictationError` + `creationFeedback` — five fields across two machines.
**Why not sketched**: The core divergence (`isDictating` outliving `isRecording`) is a timing-path bug, not a state-model gap; a state enum would not fix the overlap window. The fix is structural (pull `isDictating=false` into the `isRecording` teardown path), not a refactor.
**Pointers**: `DictationViewModel.swift:22-25,62-87`, `ReminderDictation.swift:93-94,107-109,153`.

### `BackgroundFade` Int namespace
**What**: `backgroundFadePercent: Int` with step=10, clamp 0...90, no enum cases. Already has `BackgroundFade.allValues` stride (`BackgroundFade.swift:19`) + `opacity(for:)` (`:24-26`).
**Why not sketched**: The `BackgroundFade` namespace is already well-structured (case-less, Int range, computed opacity); converting to an enum would not improve type safety and would add persistence complexity for a single-key value.
**Pointers**: `BackgroundFade.swift:13-32` (defaultValue=50 `:13`, step=10 `:16`, allValues stride `:19`, opacity body `:24-26`, clamp range `minValue`/`maxValue` `:30-31`), `ContentView.swift:89` (`@AppStorage("backgroundFadePercent", store: .standard)` declaration).

### Watch refresh UI flags
**What**: `isRefreshing` + `isShowingRefreshConfirmation` — two transient Bools.
**Why not sketched**: Two-state transient UI flags with straightforward clear paths; no combinatorial risk beyond the normal `isRefreshing`→`isShowingRefreshConfirmation`→clear sequence.
**Pointers**: `WatchReminderViewModel.swift:42-43` (plan draft cited `:43-44`; actual declarations are `isRefreshing` at `:42` and `isShowingRefreshConfirmation` at `:43`).