# Design Discussion

Full audit of state across the SingleThread codebase. The audit **is** the work
product; it informs a later, separately-ticketed refactor.

## Current State

The app spans four targets — iOS (`SingleThread/`), watchOS
(`SingleThreadWatch/`), a widget extension (`SingleThreadWidget/`), and a
shared SPM package (`SingleThreadCore/`) — with state held across four
surfaces: two `UserDefaults` suites, `@Observable` stores, transient
view-local `@State`, and cross-process WatchConnectivity payloads.

**Persisted state — two suites, 23 keys.** `AppGroup.suiteName` is
`group.app.alanvardy.SingleThread` (`AppGroup.swift:8`) and
`AppGroup.defaults = UserDefaults(suiteName:) ?? .standard`, recomputed per
access and un-cached (`AppGroup.swift:10-14`). When the group entitlement is
absent (watchOS, previews, fresh simulators) the initializer returns `nil` and
group keys collapse into `.standard` — so the *same logical key* lives in one
container on iOS and another on watchOS. 12 keys live in `.standard` (declared
as `@AppStorage` in `ContentView.swift:72-109`); 11 in `AppGroup.defaults`
(`ContentView.swift:115-132` plus the `ReminderSkip` /
`ExcludedListStore` / `CompletionCounterStore` / `PendingCompletionStore`
stores). Several keys have dual read paths — `@AppStorage` plus a raw read
(`enableActionButtons`, `notificationsEnabled`,
`notificationIntervalHours`, `allowsLandscape`, `appearanceMode`, plus every
`show*` key via wrapper structs).

**In-memory stores.** Every observable store is `@Observable final class`
(no `ObservableObject` anywhere); the widget target has no view model at all
(views only — `NextThingWidget.swift`). `ReminderStore` mirrors persisted
state (`sortOption`, `showsUndatedReminders`, `skippedIDs`, `excludedListTitles`,
`completionCounter`, `pendingCompletions`) beside transient state
(`reminders`, `hasHidden`, `authorizationStatus`, `skipGeneration`) —
`ReminderStore.swift:55-70,106,464`. `EntitlementStore` is StoreKit-derived,
never persisted (`hasResolvedEntitlement`/`isEntitled` set adjacently at
`EntitlementStore.swift:104-105`). The watch `WatchAppViewModel` is a plain
(unedited) class holding six `Show*State` holders that each double-persist
received show-* values (`ShowDateState.swift:25-28` — see Decisions).

**Combinatorial clusters.** The research identified four clusters where
multiple Bools/Ints jointly describe one phenomenon: (1) the watch
completion-transition — `isShowingCompletionTransition`, `transitionReminder?`,
glow `isActive`, and `completionTransitionBuffer` (`WatchReminderViewModel.swift:43-55`);
(2) the empty / all-done / first-card branch ordering — three targets implement
it in *different orders* (`ContentView.swift:355-455`, `WatchReminderView.swift:77-91`,
`NextThingWidget.swift:55-95`); (3) the entitlement gate —
`canMutate = isEntitled || count < 100` with the literal, never-named cap
(`ReminderStore.swift:145`); (4) dictation, where `DictationViewModel` (UI) and
`ReminderDictation` (recorder) can disagree on "is recording"
(`DictationViewModel.swift:62-87` vs `ReminderDictation.swift:93,153`).

**Cross-process sync.** `SkippedReminderSyncService` (`#if os(iOS) || os(watchOS)`)
pushes a latest-wins snapshot via `updateApplicationContext`
(`SkippedReminderSyncService.swift:167-199`) and relays complete/delete via
`sendMessage`. Receive is replace-not-union (`:311-314`). The watch double-persists
received show-* keys — once via the service's `.standard`-backed stores and again
via the `Show*State.apply()` hook. `PendingCompletionStore` is the relay safety
valve (300 s expiry, prune-on-reload). `completionCount` is incremented by the
phone (and widget — `ReminderIntents.swift:20-29`), written by the watch's receive
hook, capped `< 100` — but watch pushes a snapshot read from its *own* `.standard`
counter, which can echo a stale value back (`WatchAppViewModel.swift:161`).

**Test seams.** `--seed` writes `completionCount` into the App Group *unclamped*
(`AppViewModel.swift:294`), the one seam writing a value outside production's
counter domain (`CompletionCounterStore.swift:24-47`). `UITestingSeed` resets a
23-key list across both suites; `isEntitled` is in the list but production never
writes it (no-op cleanup, not a divergence).

## Desired End State

A read-only audit report — the immediate deliverable — that:

1. **Inventories** every persisted and shared in-memory state value across all
   four targets, with its read/write sites and encoding/fallback.
2. **Identifies** reachable invalid and contradictory state combinations
   (completion-transition, branch-ordering, entitlement gate, dictation).
3. **Ranks findings by risk severity** (see Decisions), ending in a
   prioritized action list that `/5_plan` can consume directly.
4. **Assesses** every bare-Bool/Int cluster for enum-modeling, with concrete
   enum sketches for the highest-value candidates and advisory pointers for the
   rest.
5. **Flags the AppGroup-vs-`.standard` namespace divergence as the top refactor
   candidate** without redesigning the sync contract here.

Verification: the audit is correct when every key cited maps to a real
declaration + read + write triplet with `file:line`, every contradictory
combination is traceable to a reachable code path, and the severity ranking
orders data-loss/divergence findings above hygiene findings.

## Patterns to Follow

- **Canonical store wrapper**: `init(defaults: UserDefaults = AppGroup.defaults, key:)`
  + `load()`/`save()` — `SortOptionStore.swift:22-49` is the prototype; every
  `Show*Preference`/`ShowUndated`/counter/skip/exclude store mirrors it. The
  audit should recommend converging on this shape everywhere.
- **Enum round-trip with fallback**: `rawValue` round-trip with a `else return
  .default` guard on missing *or* unrecognized values — `SortOption.swift:34-39`,
  `AppearanceMode.swift:79-86`. This is the pattern any new enum conversions
  should follow (plus round-trip tests, which today exist only for `SortOption`
  and `AppearanceMode`).
- **Presentation separation**: presentation stays on the enum for app-target
  enums, in an extension for Core's SwiftUI-free `SortOption`
  (`SortOption+Presentation.swift`). Follow this for any enum that Core owns.
- **Layered write path**: sheets → transient `SettingsBindings` bag →
  `.onChange` → `@AppStorage` → `.onChange` → `handle…` → store → closure
  hooks → persistence + `pushAll()` + `WidgetCenter.reloadAllTimelines()`
  (`ContentView+Settings.swift:13-41`, `ContentView.swift:222-233`). New state
  should honor this layering rather than add raw writes.
- **Exhaustive `switch` over transient state enums**: the widget's
  `NextThingEntry.State` (`NextThingWidget.swift:10-14`) is built per timeline
  and consumed by exhaustive `switch` (`:140`) — the model for turning bare
  flag clusters into single enums.

### Patterns NOT to follow (do not reproduce)

- **6 × duplicated `Show*Preference` structs** with hand-written, per-key
  fallbacks that differ (true/true/true/false/false/true/true). Consolidation
  is a refactor candidate, not something to extend.
- **Dual `@AppStorage` + raw-read paths** (e.g. `enableActionButtons`) — a direct
  divergence source; new keys should have a single read path.
- **Magic literal `100`** for the freemium cap, scattered across
  `ReminderStore.swift:145` and `WatchAppViewModel.swift:27`; the audit flags it,
  the fix names it.
- **Direct property assignment bypassing hooks** (`store.sortOption =`,
  `store.showsUndatedReminders =` at composition roots and service receive-side
  saves) — documented as bypassing persistence and sync.
- **Double-persistence on the watch receive path** (`Show*State.apply()` writing
  what the service store already wrote) — a redundant write the refactor should
  collapse to one path.

## Design Decisions

1. **Deliverable scope — read-only audit.** The audit document is the work
   product; no code changes land in this ticket. Hygiene fixes (naming `100`,
   correcting the two doc drifts — `AppGroup.swift:2-4`, `AppViewModel.swift:211`)
   and the refactor itself become separate tickets run through `/1_spec` → `/5_plan`.
   Keeps the audit auditable and controversy-free.
2. **Finding organization — by risk severity.** Four tiers: (1) reachable
   invalid/contradictory state, (2) cross-target divergence (AppGroup vs
   `.standard`), (3) dual-read-path drift, (4) hygiene/naming/doc-drift. This
   ranking is the direct input to `/5_plan`'s task ordering.
3. **Enum assessment — advisory + top candidates.** Enumerate every bare-Bool/Int
   cluster, but produce *concrete enum sketches only* for the highest-value
   clusters (watch completion-transition, entitlement gate, empty/all-done branch
   ordering); label the rest advisory with `file:line` pointers. Prevents the
   audit from metastasizing into a spec.
4. **Divergence treatment — diagnose, don't migrate.** The AppGroup-vs-`.standard`
   namespace collapse (`AppGroup.swift:10-14`) plus the watch pinning 7 stores to
   `.standard` (`WatchAppViewModel.swift:155-161`) and the watch's `.standard`
   counter echo (`:161` vs receive write `:186`) is the top finding — flagged as
   critical, but the sync contract is **not** redesigned here; that needs its own
   spike (a group-registered watch is currently untestable on simulator).
5. **Inventory depth — persisted + shared + cross-process.** `ReminderStore`,
   `EntitlementStore`, `Show*State`, dictation machines, WC payloads, counters.
   Transient view-local `@State` (`isShowingSettings`, `isShowingPurchase` —
   `ContentView.swift:257,261`) gets a one-line acknowledgment, not an
   exhaustive table.

## What We're NOT Doing

- **No code changes** — no constant renames, no doc edits, no test additions in
  this ticket (they're deferred to the refactor ticket).
- **No suite migration** — we diagnose the AppGroup/`.standard` divergence, we do
  not decide the target topology or move keys.
- **No WatchConnectivity redesign** — replace-not-union, latest-wins `pushAll`,
  and per-key receive hooks are documented as-is, not renegotiated.
- **No new build targets or pbxproj edits** — a new test target (e.g. a
  group-registered watch harness) is explicitly out of scope and must be flagged
  in the refactor ticket's design phase.
- **No exhaustive transient-`@State` inventory** — record the notable transient
  clusters (completion-transition, dictation) but skip a complete view-state table.
- **No full enum specification for every cluster** — top candidates get sketches;
  the rest get pointers.

## Open Risks

- **WatchOS with the group *registered* is untested** — `AppGroup.defaults`
  fallback means every watch test exercises `.standard`, so group-registered watch
  behavior (real cross-container divergence) is unverifiable on simulator today.
- **Two `EntitlementStore` instances on watch** — the never-read one inside the
  service (`WatchAppViewModel.swift:162`) vs `EntitlementState`; interplay with
  `canMutate` is only partially traced.
- **`--ui-testing-live-excluded`** injects a WC context 5 s post-launch
  (`WatchAppViewModel.swift:237-246`); its interaction with phone-side receive
  hooks is only partially traced.
- **Line-number variance in `UITestingSeed.persistedKeys`** (reported `:63-85`)
  — re-verify sub-line refs against the source when citing in the final audit.
- **Possible phone receipt of non-`pushAll` watch contexts** — the watch's
  receive-only service (`allSends* = false`, `WatchAppViewModel.swift:154-163`)
  sends only the 5 always-on keys; unverified whether any other path could push
  a context the phone half-wiring mis-handles.
- **The `< 100` vs `<= 100` boundary** (strictly `< 100`, gate closes at exactly
  100) is subtle and repeated in UI seeds/tests — any future refactor naming the
  constant must preserve the boundary semantics and its test coverage
  (`ReminderStoreGateTests.swift:18-38`).