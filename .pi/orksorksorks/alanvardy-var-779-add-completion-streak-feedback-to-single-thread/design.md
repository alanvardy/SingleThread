# Design Discussion — Completion Momentum Feedback

## Current State

Single Thread has a single-card interface backed by `ReminderStore` (an
`@MainActor @Observable` class owning the `EKEventStore`). One completion
path drives every downstream surface: `completeReminder(identifier:)`
(`ReminderStore.swift:220-256`) finds the reminder, sets `isCompleted`,
saves, then `completionCounter.increment()` (:246), `undoStore.retain` (:247),
`resetSkipCount(for:)` (:248), and a settle + reload (:250-251). iOS renders
through `ContentViewModel` (`ContentViewModel.swift:20+225`) → `ContentView`.

Persisted counters today are all **undated**:

- `CompletionCounterStore` (`CompletionCounterStore.swift:16-58`) — a single
  lifetime integer under key `"completionCount"` (`AppGroup.defaults`),
  mutated only by complete (:246), undo (:278, clamped ≥0 :44-46), and the
  `--seed` seam (`AppViewModel.swift:299-303`).
- `SkipCountStore` — window-relative, pruned by window membership
  (`ReminderStore.swift:634-643`), not day-relative.

No day-aware persistence or streak/consecutive logic exists anywhere (grep for
`streak|consecutive` finds only an unrelated text-dedup accumulator,
`TranscriptionAccumulator.swift:62`). The only date-window logic is
`ReminderDateFilter` (`ReminderDateFilter.swift:26-62`), which computes
`endOfToday` from `Calendar.current` + `Date()` device-local (:27-36).

Existing transient feedback surfaces (`research.md` Q3):

- **Completion glow** — `CompletionGlow.swift` (`@Observable`, `isActive`,
  `duration 0.5s`, auto-dismiss `dismissTask` :32-40); triggered in
  `ContentViewModel.completeCurrentReminder()` (:159-163) gated on
  `showCompletionGlow.isEnabled`; rendered `ContentView.swift:553-562`
  (`Color.green`, `.allowsHitTesting(false)`, hidden from a11y unless
  `isGlowUITesting` :339-340). Preference `BoolPreferenceKey.swift:9`
  (fallback true), toggle `ReminderSettingsView.swift:82-92`.
- **Creation feedback bubble** — `CreationFeedback.swift:7-33`, auto-clears
  after 1 s via `Task.sleep` (`DictationViewModel.swift:85-86`), rendered in
  the bottom bar (`ContentView.swift:582-591,641-642`), **not** preference-gated.
- **Undo overlay** — `ContentView.swift:212-225`, gated on
  `undoStore.hasUndoableReminder` (in-memory single-level `UndoStore.swift:4-32`).
- **Empty-state card** — `EmptyStateCard.swift:11-50`, copy from
  `ContentViewModel` (`allDoneStateCopy` :112-116).

`completionCount` is already watch-synced via `pushAll`
(`SkippedReminderSyncService.swift:208`), **but there is no post-completion
push** on the phone (`AppViewModel.swift:404-415`), and the watch shows no
completion-count surface of any kind.

## Desired End State

Completing a reminder on iOS shows a transient, auto-dismissing momentum
overlay on the single card — *"You've cleared N today"* — driven by a new
per-calendar-day completion counter. No streak, no day history, no watch
surface, no persistent badge.

**Verify by**:

1. Complete a reminder → counter for today increments; overlay shows the
   correct "N today" and auto-dismisses.
2. First completion on a new calendar day resets N to 1 (day-marker rollover).
3. Undo (undo button) decrements today's N, clamped at 0.
4. Counter and day marker persist across relaunch (AppGroup.defaults).
5. Preference toggle disables the overlay (like `showCompletionGlow`).
6. Unit tests cover: increment same-day, day rollover, decrement clamp,
   store re-creation, `ReminderStore` integration (complete + undo), and the
   `--seed`/`resetPersistedState` seams. No new watch sync keys or UI tests.

## Patterns to Follow

- **Transient auto-dismiss overlay → mirror `CompletionGlow`.** `@Observable`
  model with `trigger()`/`isActive`/`duration` and a `dismissTask` that
  re-sets on re-trigger (`CompletionGlow.swift:27-40`); trigger from
  `ContentViewModel.completeCurrentReminder()` alongside the existing glow
  trigger (`ContentViewModel.swift:159-163`); render a subtle overlay with
  `.allowsHitTesting(false)` and an `.animation(.easeInOut…)` fade like
  `ContentView.swift:553-562`. Coexists with the glow (glow is a background
  tint; the overlay is foreground text).
- **Counter store → mirror `CompletionCounterStore`** (`CompletionCounterStore.swift:16-58`):
  a dedicated store class defaulting to `AppGroup.defaults`, with
  `increment` / `decrement` (clamped ≥0) / `resetForTesting`, and integrate
  through `ReminderStore`'s complete and undo branches (`ReminderStore.swift:246`,
  `:278`) so the `canMutate` freemium gate (`:176-177`) is inherited for free.
- **Day boundary → mirror `ReminderDateFilter`'s device-local day**
  (`ReminderDateFilter.swift:27-36`): derive "today" from `Calendar.current`,
  persist a start-of-day marker, and compare lazily on next increment. No UTC,
  no rolling window.
- **Preference gating → reuse `BoolPreferenceStore`** (`BoolPreferenceKey.swift:9`,
  fallback true) + a settings toggle, matching `showCompletionGlow`
  (`SettingsBindings.swift:149-157`). The creation bubble is the one surface
  that is **not** gated — for a repeating reinforcement, gate it.
- **Test seams → follow the store-test recipe** (`conventions.md`): store class +
  `@Suite(.serialized)` store tests with UUID-key isolation + `defer`
  cleanup (like `CompletionCounterStoreTests.swift`, `SkipCountStoreTests.swift`);
  integration tests through `ReminderStoreTests.swift` (rendezvous on hooks,
  `noopSettle`); add the new key(s) to `resetPersistedState`
  (`UITestingSeed.swift:117-142`) so seeded/UI-test launches start clean.

**Do NOT follow**: the watch-sync checklist (PayloadKey/pushAll/apply/
`Show*State` holder) — out of scope here; the `.standard` fallback trap
(`AppGroup.swift:12-17` — always use `AppGroup.defaults`); and the un-gated
creation-bubble pattern for the overlay itself.

## Design Decisions

1. **Mechanism: daily completion count ("cleared N today")** — chosen over a
   streak (net-new day-history persistence, no precedent) and over both
   (clutter). A single "day marker + today count" pair is the smallest new
   state that satisfies the ticket.
2. **Day = calendar day (`Calendar.current`)** — chosen over a rolling
   24-hour window. Matches `ReminderDateFilter.endOfToday` semantics
   (`ReminderDateFilter.swift:27-36`); no new time concept to explain.
   Persist the day marker as a `startOfDay` date; on increment, if the stored
   marker ≠ today's `startOfDay`, reset N to 1 and write the new marker.
3. **Surface: transient overlay on completion** — a new `@Observable`
   momentum-overlay model mirroring `CompletionGlow`'s trigger/auto-dismiss,
   rendered as subtle foreground text on the card and triggered from
   `ContentViewModel.completeCurrentReminder()` next to the glow trigger. Gated
   behind a new `BoolPreferenceStore` toggle (default true), toggled in
   `ReminderSettingsView` alongside the glow toggle. Preference-gated per the
   codebase convention (unlike the un-gated creation bubble).
4. **Persistence: new `DailyCompletionStore` (iOS-only)** — mirrors
   `CompletionCounterStore` shape, defaults to `AppGroup.defaults`, keys for
   the day marker + today count. **Not** added to `PayloadKey`/`pushAll`/`apply`
   and no watch holder — the watch shows no completion-count surface and the
   ticket targets the single-card (iOS) interface. Note `completionCount`
   already has no post-completion push (:208 vs `AppViewModel.swift:404-415`),
   so skipping watch sync for the new counter is consistent.
5. **Undo & freemium: decrement today's count, clamped ≥0** — chosen to mirror
   the established `completionCounter.decrement(clamp)` behavior
   (`CompletionCounterStore.swift:44-46`, `ReminderStore.swift:278`). No
   freemium tie beyond the existing `canMutate` gate, which the complete path
   already enforces before the counter is touched.

## What We're NOT Doing

- **No streak** — no consecutive-day history, no "longest streak" record.
- **No watch surface or sync keys** — no `PayloadKey` additions, no watch
  `Show*State` holder, no `wireStateReceiveHooks` change.
- **No persistent badge** on the single card — clutter is the ticket's explicit
  concern; the feedback is transient only.
- **No touching `completionCount` (lifetime) or the 100-free cap**
  (`EntitlementStore.swift:45-48`).
- **No haptics/sounds/toasts** — no sensory mechanisms exist today
  (`research.md` Q3); the overlay is the entire mechanism.
- **No UTC/timezone-independent day tracking** — device-local only, consistent
  with the rest of the app. No per-completion day attribution.

## Open Risks

- **Glow + overlay sequencing**: both fire on completion. If they visually
  collide, stagger or combine copy — resolve in implementation with a quick
  sim check; the overlay is foreground text and should layer above the glow's
  background tint without interaction.
- **a11y**: `completionGlow` is hidden from VoiceOver unless a `--ui-testing`
  flag is set (`ContentView.swift:339-340`). Decide whether the momentum
  overlay should be announced; brief VoiceOver announcements on rapid
  completions could be noisy. Default to mirroring the glow (hidden, or
  announce only when empty/rare) — flag for implementation.
- **Day-rollover laziness**: the marker is only compared on the next increment,
  so an app left sitting across midnight shows the stale count until the next
  completion. Acceptable (no background rollover); note in plan.
- **Undo day-attribution**: `UndoStore` is in-memory single-level, so undo
  always happens moments after the completion it reverses; crossing midnight
  between complete and undo is an edge case where undo decrements the *new*
  day's count. Accepted simplification (no per-completion day attribution).
- **Lifetime vs. today divergence**: `completionCount` (lifetime) can exceed
  today's N; harmless unless some UI ever shows both — none does today.
- **Timezone change mid-day**: shifts the day boundary device-local, same as
  `ReminderDateFilter`; untested in the codebase beyond the UTC seam
  (`SingleThreadTests.swift:242,246`).