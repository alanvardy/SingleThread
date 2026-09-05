# Design Discussion — Collapse 6 `Show*Preference` → `BoolPreferenceStore`

## Current State

Six near-identical structs in `SingleThreadCore` each wrap a single `Bool` in
`UserDefaults`, differing **only** in key string and absent-value fallback
(research Q2):

| Struct | Key | Fallback | API |
|---|---|---|---|
| `ShowDatePreference` | `"showDate"` | `true` | `isEnabled` / `set` |
| `ShowRecurrencePreference` | `"showRecurrence"` | `true` | `isEnabled` / `set` |
| `ShowAlarmsPreference` | `"showAlarms"` | `true` | `isEnabled` / `set` |
| `ShowCompletionGlowPreference` | `"showCompletionGlow"` | `true` | `isEnabled` / `set` |
| `ShowListPreference` | `"showList"` | `false` | `isEnabled` / `set` |
| `ShowUndatedRemindersPreference` | `"showUndatedReminders"` | `false` | `load` / `save` |

Every struct declares its own `private let defaults`/`key` and copies the same
init body (`ShowDatePreference.swift:11-13,29-30`; identical in all six). Read
is always `object(forKey:) as? Bool ?? <fallback>` — never `bool(forKey:)`
(research Q2). No protocol, base class, or typealias ties them together.

The sibling `SortOptionStore` (`SortOption.swift:22-47`) is the only existing
generic-shaped store (parameterized `key` + default), using `load/save`. The
var-759 audit explicitly calls it "the canonical prototype" for this
consolidation (finding T4.4, `audit/findings.md:80-84`).

Separately, iOS `ContentView.swift:115-133` has six `@AppStorage` declarations
mirroring these keys — these are SwiftUI property wrappers driving `$binding`
and `.onChange`, not duplicates of the struct logic, and are out of scope.

Each key has three representations today (research Q1 cross-cutting):
1. A `Show*Preference` struct (Core — iOS VM, widget, sync service)
2. An `@AppStorage` mirror (iOS — ContentView + settings sheet)
3. A `Show*State` holder (watchOS — `@Observable`, hardcoded `.standard`)

Fallbacks are consistent across all three: true×4 (date/recurrence/alarms/glow),
false×2 (list/undated).

## Desired End State

One generic `BoolPreferenceStore` struct in `SingleThreadCore` replaces all six
`Show*Preference` structs. The new type is parameterized by key and default
fallback value, exposes `var isEnabled: Bool` / `func set(_:) -> Void`, and
accepts the same `init(defaults: UserDefaults, key: String)` pattern as the
existing six — with `defaults:` defaulting to `AppGroup.defaults`. A companion
`BoolPreferenceKey` provides named constants for the six keys.

**Verification**: all six keys round-trip identically in unit tests (absent-value
fallback for both true-default and false-default keys, set/read round-trip both
polarities, custom-key injection via `.standard` + UUID); full CI gate
(`./scripts/test.sh`) passes; no user-visible behavior change.

## Patterns to Follow

### Adopt

- **`SortOptionStore` shape** (`SortOption.swift:22-47`): init with `defaults:` +
  `key:` (the key defaulting to a shared constant `SortOption.defaultsKey :18`),
  read/write in the same method. This is the established template for a
  key-parameterized store in Core.
- **`object(forKey:) as? Bool ?? fallback`** — every preference reads this
  way today (research Q2); `bool(forKey:)` collapses nil→false and would
  lose the true-default/false-default distinction.
- **Nonisolated Sendable** — Core is Swift 6 with `MainActor` isolation
  off(`research.md Q6`). The new struct holds only `UserDefaults` + `String`,
  both Sendable; no `@MainActor` annotation needed.
- **Unit test pattern**: UUID key on `.standard`, `defer removeObject`, assert
  absent fallback first, then set/read both polarities (e.g.
  `ShowAlarmsPreferenceTests.swift:8-15`). Port to parameterized tests over
  the six keys.
- **`make check`** (`./scripts/test.sh`, `conventions.md:1`) as the final
  gate — identical to CI.

### Avoid

- **`load()/save()` API** — `SortOptionStore` uses it, but five of six
  existing structs use `isEnabled`/`set`. Choosing `load/save` would churn
  5× callers; `isEnabled`/`set` churns only `ShowUndatedRemindersPreference`'s
  two callers.
- **`bool(forKey:)`** — would collapse nil to false, erasing the distinction
  between "never set" and "explicitly turned off" that three of the structs
  deliberately preserve (`ShowDatePreference.swift:3-7`.
- **New protocols or base classes** — unnecessary for six types that differ
  only in key string and fallback boolean.
- **Touching `@AppStorage`** — those are SwiftUI bindings, not duplicated
  logic; replacing them requires custom `DynamicProperty` plumbing with zero
  benefit.

## Design Decisions

1. **API shape: `isEnabled`/`set`** — five of six existing structs use it;
   only `ShowUndatedRemindersPreference`'s `load/save` callers need updating.
   Preserves the idiom that most of the codebase already expects.

2. **Naming: `BoolPreferenceStore`** — aligns with the `*Store` convention
   used by every non-show* type (`SortOptionStore`, `ExcludedListStore`,
   `SkipCountStore`); the sync service already names its params `showDateStore`
   etc. even when the concrete type was a `*Preference`.

3. **Key constants: `BoolPreferenceKey` enum** — string-typed, `Sendable`,
   one case per key. Prevents silent typo divergence across the six call sites
   (widget, sync service, AppViewModel, watch states). `BoolPreferenceStore`
   takes `key: String` for flexibility (custom-key injection in tests), but
   production callers use the enum.

4. **`@AppStorage` left alone** — they're SwiftUI property wrappers driving
   `$binding` and `.onChange`. The structs serve non-SwiftUI code (widget,
   AppViewModel diffing, sync service, watch states). No overlap to collapse.

5. **Single-commit migration** — mechanical rename across all 15+ files.
   Adding the generic store alongside the old six would leave dead code and
   two parallel conventions; the research has exhaustively mapped every call
   site so there are no unknowns.

6. **`ShowUndatedRemindersPreference` gets the same treatment** — its
   `load/save` API is the only reason it's an "outlier" (research Q2). Under
   the unified `isEnabled`/`set` API it becomes just another
   `BoolPreferenceStore` instance with key `"showUndatedReminders"` and
   fallback `false`. The special path through `ReminderStore` (`didSet →
   fetch predicate widens, `ReminderStore.swift:134-139`) is unchanged — the
   `ReminderStore` property stays, it just reads `store.isEnabled` instead
   of `store.load()`.

## What We're NOT Doing

- **Not touching any `@AppStorage` declaration** in `ContentView.swift`.
- **Not changing the `ReminderStore.showsUndatedReminders` property** or its
  fetch-predicate side effects.
- **Not adding a protocol/hierarchy** to cover the other `*Store` types
  (`ExcludedListStore`, `SkipCountStore`, etc.) — they store non-Bool types
  and have different read/write shapes.
- **Not resolving the `UserDefaults` container split** (`AppGroup.defaults`
  vs `.standard` — that's T2.1/T2.4, deferred in the var-759 audit).
- **Not fixing the watch double-persistence** (T2.3, `plan.md:514-519`) —
  adding `BoolPreferenceStore` doesn't change how `SkippedReminderSyncService`
  + `Show*State` each write; the double-write is a separate concern.
- **Not adding widget or watch-UI tests** — the widget has no test bundle at
  all (`research.md Q4`), and adding one is a `pbxproj`/ scheme operation
  flagged as non-trivially in AGENTS.md.
- **Not extracting `sortOption` into this store** — it's not a Bool.

## Open Risks

- **`--reset-glow-preference` seam mismatch** (`AppViewModel.swift:285-287`):
  removes from `.standard` while the glow key lives in `AppGroup.defaults`.
  The generic store doesn't fix this, but it doesn't make it worse either.
  If the fixture relies on this mismatch working, it'll still work.
- **Watch `Show*State` holders**: each has `private let prederence =
  Show*Preference(defaults: .standard)` hardcoded (`ShowDateState.swift:28`).
  The generic store accepts `defaults:` — this is a mechanical s/ShowDatePreference/BoolPreferenceStore/
  substitution with no behavior change.
- **Widget raw read** (`NextThingWidget.swift:71`) uses `bool(forKey:)` on
  `"showUndatedReminders"` directly, bypasing the struct. The generic store
  can't stop this. Low risk — the raw read matches the store's key+fallback
  by coincidence, and changing it to use the store is a one-line improvement
  but optional.
- **`function_body_length` gate**: `SkippedReminderSyncService.init` already
  suppresses this warning (`:298-300`). Adding a 7th store param (the generic
  replaces 6 concrete params) shouldn't change line count meaningfully, but
  the init is already near the limit.