---
name: ai-sorting
description: How SingleThread's AI sort/ranking subsystem works end to end — rules storage, the coordinator, refresh triggers, the App Group notification invariant, and the testing seams. Use when changing sorting, AI ranking, sort rules, or reminder ordering.
---

# AI sorting / ranking

The AI sort feature re-ranks the visible reminder list using on-device
Foundation Models, with a rules string the user edits.

## Data flow

1. **Rules storage** — `AISortRulesStore` persists the rules text in the App
   Group `UserDefaults` (`AppGroup.defaults`). `SettingsBindings` owns the
   store; `AISortRulesView` is the editor UI.
2. **Refresh trigger** — `AppViewModel` observes rule-text edits and reminder
   changes and calls `refreshAIRanking(force:)` (debounced).
3. **Coordinator** — `AISortCoordinator(ranker:debounce:)` (`SingleThreadCore`)
   calls the injected `AIReminderRanking`. Production uses
   `FoundationModelsReminderRanker`; tests inject a fake.
4. **Ordering** — `ReminderStore.visibleReminders` applies the AI order when a
   ranking is available, and otherwise falls through to the `.priority` chain
   (`ReminderSort.areInIncreasingOrder(…, using: .priority)`).

## App Group notification invariant

`AppGroup.defaults` is a single cached `static let` instance
(`.init(suiteName:) ?? .standard`). This matters: each `UserDefaults(suiteName:)`
call returns a **fresh** object, and `didChangeNotification`'s `object` is the
instance that changed — so if `defaults` were a computed property,
`object:`-filtered observers would **never** fire and rule edits would silently
never re-rank. Guard: `AppGroupTests.defaultsIsAStableInstance` (do not weaken
it). See the Persistence section of `AGENTS.md`.

## UX contract

When the model is unavailable (no Foundation Models, simulator, denial), the
feature **silently falls back** to `.priority` order — it does not error or
block the list. Preserve that: a missing ranking is a normal state, not a
failure to surface.

## Testing seams

- Inject a fake `AIReminderRanking` into `AppViewModel`/`AISortCoordinator` —
  never exercise Foundation Models in unit tests.
- The coordinator's `debounce` is injectable (default `.milliseconds(500)`);
  set it to zero/short in tests instead of sleeping.
- Cover the rules round-trip (`AISortRulesStoreTests`), the view wiring
  (`AISortRulesViewTests`), and the fallback-to-`.priority` path.

## Regression guard

`scripts/check-appgroup-notify.sh` probes the observer invariant (cached
instance + `object:` filter) and is the cheap check to run after touching
`AppGroup` or the refresh triggers.