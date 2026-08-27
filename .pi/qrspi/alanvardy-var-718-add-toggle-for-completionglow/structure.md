# Structure Outline

## Approach

Add a `ShowCompletionGlowPreference` struct (copying the proven `ShowDatePreference`
shape exactly), gate `completionGlow.trigger()` behind `.isEnabled` in both view models,
add a Toggle row in settings, and sync the preference phone→watch through the existing
`SkippedReminderSyncService` pipeline. Each layer below is fully tested before the next
is started.

---

## Stage 1: Preference Struct (Core Model)

Delivers a byte-for-byte sibling of `ShowDatePreference` — missing key → `true`,
persisted in `AppGroup.defaults`. Every other layer reads from this.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ShowCompletionGlowPreference.swift` (new)

**Key changes**:
- `public struct ShowCompletionGlowPreference` — init defaults to `AppGroup.defaults`, key `"showCompletionGlow"`, `isEnabled: Bool` (nil → `true`), `set(_ enabled: Bool)`

**Tests**: `SingleThreadTests/ShowCompletionGlowPreferenceTests.swift` (new)
- `missingKeyDefaultsToEnabled` — UUID-keyed `UserDefaults.standard`, assert `isEnabled`
- `setFalseRoundTrips` / `setTrueRoundTrips` — write + read-back
- `missingKeyIsNotFalse` — guard against `bool(forKey:)` returning false for nil

**Verify**: `swift test --filter ShowCompletionGlowPreferenceTests` (or `./scripts/test.sh`; this suite passes in isolation)

---

## Stage 2: Settings Persistence Plumbing (iOS/macOS)

Adds `showCompletionGlow` to `SettingsBindings` and the `ContentView` `@AppStorage` /
write-back / bag-creation so toggling persists to `AppGroup.defaults`. No UI yet — just
the data-flow pipes, testable via `SettingsBindings` init defaults and the `makeSettingsBag`
shape.

**Files**: `SingleThread/SettingsBindings.swift`, `SingleThread/ContentView.swift`

**Key changes**:
- `SettingsBindings` — new `init(showCompletionGlow: Bool = true)` param + `var showCompletionGlow: Bool` property
- `ContentView` — `@AppStorage("showCompletionGlow", store: AppGroup.defaults) private var showCompletionGlow = true`
- `ContentView.makeSettingsBag()` — pass `showCompletionGlow: showCompletionGlow`
- `ContentView` sheet `.onChange` write-back — `bag.showCompletionGlow` → `showCompletionGlow`

**Tests**: extend existing `SettingsViewTests` with a structural assert that `SettingsBindings` carries the key; smoke-test `makeSettingsBag()` captures the `@AppStorage` value.

**Verify**: `./scripts/test.sh` — all existing + new unit tests green

---

## Stage 3: Settings UI (Toggle Row)

Exposes the toggle in `ReminderSettingsView` alongside the four existing show-* rows.
No `.onChange` → widget-reload hook (the widget doesn't render the glow). This layer
makes the preference user-visible.

**Files**: `SingleThread/ReminderSettingsView.swift`, `SingleThread/ContentView.swift`

**Key changes**:
- `ReminderSettingsView` — new `@Binding var showCompletionGlow: Bool` param + `Toggle(isOn: $showCompletionGlow) { Label("Completion glow", systemImage: "sparkles") }` row (**no** `.onChange` hook — no widget timeline reload)
- `ReminderSettingsView` Preview — add `.constant(true)` for the new binding
- `ContentView` settings sheet — `$bag.showCompletionGlow` wired to `ReminderSettingsView`
- `ReminderSettingsView` call-site in `SettingsView` — pass the new binding through (requires `SettingsView` to thread it from `SettingsBindings`)

**Files also touched**: `SingleThread/SettingsView.swift` (thread the new binding through)

**Tests**: structural `SettingsViewTests` assert the toggle row label appears; manual visual check that `Toggle` renders in the Reminder settings form

**Verify**: build + run on simulator; open Settings → Reminder → toggle flips and value survives sheet dismiss / relaunch

---

## Stage 4: View-Model Gate (Behavior)

Injects the preference into both view models and gates `completionGlow.trigger()` behind
`.isEnabled`. On iOS/macOS this reads from `AppGroup.defaults`; on watch it reads from a
new `ShowCompletionGlowState` holder (`.standard`-backed, sync unwired until Stage 5).

**Files**:
- `SingleThread/ContentViewModel.swift`
- `SingleThreadWatch/WatchReminderViewModel.swift`
- `SingleThreadWatch/ShowCompletionGlowState.swift` (new)

**Key changes**:
- `ContentViewModel.init` — new param `showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference()`; property `private let showCompletionGlow: ShowCompletionGlowPreference`
- `ContentViewModel.completeCurrentReminder()` — guard `if showCompletionGlow.isEnabled { completionGlow.trigger() }`
- `AppViewModel.contentViewModel` — passes `showCompletionGlow: ShowCompletionGlowPreference()` (default arg covers existing callers)
- `ShowCompletionGlowState` (new, watch) — `@Observable`, `isEnabled` seeded from `ShowCompletionGlowPreference(defaults: .standard)`, `apply(_:)` persists + republishes (exact copy of `ShowDateState`)
- `WatchReminderViewModel.init` — new param `showCompletionGlowState: ShowCompletionGlowState`; property `let showCompletionGlowState: ShowCompletionGlowState`
- `WatchReminderViewModel.completeCurrentReminder()` — guard `if showCompletionGlowState.isEnabled { completionGlow.trigger() }`
- `WatchAppViewModel` — new `let showCompletionGlowState = ShowCompletionGlowState()`; pass to `reminderViewModel` factory

**Tests**:
- Extend `CompletionGlowViewModelTests` — `glowStaysInactiveWhenPreferenceDisabled` (inject a false `ShowCompletionGlowPreference` with a UUID key), `glowTriggersWhenPreferenceEnabled` (inject true); keep existing tests working with the default
- New `ShowCompletionGlowStateTests` (watch) — `initialValueFromPreference`, `applyPersists`, `applyRepublishes`
- Extend `WatchReminderViewModel` tests if one exists — assert gate behavior

**Verify**: `./scripts/test.sh` — all unit tests green on both iOS sim + watch sim

---

## Stage 5: Phone→Watch Sync (Transport)

Wires the new preference through the existing `SkippedReminderSyncService` pipeline so
the watch respects the phone's setting — new store + `sends*` flag + `PayloadKey` +
`pushAll()` gate + `apply()` decode + hook + iPhone diff observation.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThread/AppViewModel.swift`
- `SingleThreadWatch/WatchAppViewModel.swift`

**Key changes**:
- `SkippedReminderSyncService.init` — new params `showCompletionGlowStore: ShowCompletionGlowPreference = ShowCompletionGlowPreference()`, `sendsShowCompletionGlow: Bool = true`; stored properties
- `SkippedReminderSyncService` — new `nonisolated(unsafe) var onShowCompletionGlowReceived: ((Bool) -> Void)?` hook
- `PayloadKey` — new `static let showCompletionGlow = "showCompletionGlow"`
- `pushAll()` — gate on `sendsShowCompletionGlow`: `if sendsShowCompletionGlow { context[PayloadKey.showCompletionGlow] = showCompletionGlowStore.isEnabled }`
- `apply(context:)` — decode + persist + fire hook: `if let showCompletionGlow = context[PayloadKey.showCompletionGlow] as? Bool { showCompletionGlowStore.set(showCompletionGlow); onShowCompletionGlowReceived?(showCompletionGlow) }`
- `AppViewModel.init` (iOS) — pass `showCompletionGlowStore: ShowCompletionGlowPreference()` to `SkippedReminderSyncService`
- `AppViewModel.handlePreferencesChanged` — add `let currentShowCompletionGlow = ShowCompletionGlowPreference().isEnabled`; diff against `lastShowCompletionGlow`; add `lastShowCompletionGlow = ShowCompletionGlowPreference().isEnabled` baseline
- `WatchAppViewModel.setupSyncService` — pass `showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard)` (sends=false, watch receive-only); wire `onShowCompletionGlowReceived` → `showCompletionGlowState.apply(value)`

**Tests**:
- Extend `SingleThreadTests/SkippedReminderSyncServiceTests.swift` — `pushAllIncludesShowCompletionGlowWhenEnabled`, `pushAllOmitsShowCompletionGlowWhenDisabled`, `receiveShowCompletionGlowApplies`, `receiveShowCompletionGlowFiresHook`
- Extend `SingleThreadWatchTests/WatchSyncPipelineTests.swift` — `receiveAppliesShowCompletionGlow`, relaunch-survival test for the new key

**Verify**: `./scripts/test.sh` — all sync + watch pipeline tests green

---

## Stage 6: UI Tests

End-to-end regression guard: toggling the setting flips the preference, and the glow
appears/doesn't-appear based on the setting.

**Files**: `SingleThreadUITests/` (new or extended test)

**Key test flows** (using `--seed '<json>'` launch arg for determinism):
1. **Toggle flips in settings** — navigate to Settings → Reminder, flip "Completion glow" toggle off, dismiss sheet, re-open settings, assert toggle is off
2. **Glow disabled** — with toggle off and a seeded incomplete reminder, complete it, assert the green overlay does **not** appear
3. **Glow enabled** — with toggle on (default), complete a reminder, assert the green overlay flashes briefly

**Verify**: `make ui-test` or `./scripts/test.sh` passes the full gate including UI tests

---

## Testing Checkpoints

| After Stage | Must be green |
|---|---|
| 1 | `ShowCompletionGlowPreferenceTests` (3 tests) |
| 2 | All unit tests (SettingsBindings + ContentView plumbing survives) |
| 3 | Build succeeds; toggle renders in simulator |
| 4 | `CompletionGlowViewModelTests` (new disabled/enabled variants) + `ShowCompletionGlowStateTests` |
| 5 | `SkippedReminderSyncServiceTests` + `WatchSyncPipelineTests` (new key variants) |
| 6 | Full gate: `./scripts/test.sh` — format, lint, build, periphery, unit tests, UI tests |

**Resume**: if context resets mid-implementation, run `./scripts/test.sh` and confirm
only the **current** and **prior** stages are green. Any failure in a prior stage is a
regression — fix it before continuing.