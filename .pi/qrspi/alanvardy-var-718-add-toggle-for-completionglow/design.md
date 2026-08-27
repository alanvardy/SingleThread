# Design Discussion — CompletionGlow Toggle

## Current State

The app shows a brief full-screen green flash ("CompletionGlow") after a reminder
is completed, on the iPhone/macOS app and the Apple Watch. Today it is always on
and cannot be disabled.

- `CompletionGlow` is a self-contained `@MainActor @Observable public final class`
  in `SingleThreadCore` (`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift:13`).
  It holds `isActive` (`:21`), an injectable `duration` (`:25`, for tests), and a
  `trigger()` that flips `isActive = true` then schedules a `Task.sleep(duration)`
  auto-dismiss (`:30-42`).
- The iOS/macOS view model owns an instance and triggers on success:
  `ContentViewModel.completionGlow` (`SingleThread/ContentViewModel.swift:36`) and
  `completeCurrentReminder()` calls `completionGlow.trigger()` only when
  `store.completeCurrentReminder()` returns true (`:106-109`).
- The watch mirrors this identically: `WatchReminderViewModel.completionGlow`
  (`SingleThreadWatch/WatchReminderViewModel.swift:33`) and `completeCurrentReminder()`
  (`:44-50`).
- Each view gates its overlay on `isActive`:
  `ContentView` `.overlay { if viewModel.completionGlow.isActive { completionGlowOverlay } }`
  (`SingleThread/ContentView.swift:81-83`), fade animation honors Reduce Motion (`:86-87`),
  overlay is a decorative `Color.green.opacity(0.3)` that passes touches through and is
  accessibility-hidden (`:467-474`). The watch view mirrors this
  (`WatchReminderView.swift:84-90`, `:139-146`).
- macOS shares `ContentView` and `ContentViewModel` (`SingleThread/SingleThreadApp.swift:9-13`);
  the Complete action button routes through the same `completeCurrentReminder()`
  (`ContentView.swift:212`). No `#if os(macOS)` guard exists on the glow path.
- The widget does **not** render the glow and never touches `CompletionGlow`
  (research Q7; `SingleThreadWidget/NextThingWidget.swift`).

There is an established pattern for "show X" display preferences that this feature
should copy exactly:

- Four structs (`ShowDatePreference`, `ShowListPreference`, `ShowRecurrencePreference`,
  `ShowAlarmsPreference`) share one shape: `init(defaults: UserDefaults = AppGroup.defaults,
  key: String = "...")`, read-only `isEnabled`, and `set(_:)` — e.g.
  `ShowDatePreference.swift:11,15-21` with missing key → `true`.
- They persist into `AppGroup.defaults` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:5-11`).
- The phone mirrors them as `@AppStorage(..., store: AppGroup.defaults)` in `ContentView`
  (`:175-183`), passes them into `ReminderCardView` (`:319-320`), and exposes them as
  `Toggle` rows in `ReminderSettingsView` (`SingleThread/ReminderSettingsView.swift:18-44`).
- The iPhone→watch transport is `SkippedReminderSyncService` (`SingleThreadCore/.../SkippedReminderSyncService.swift`),
  which carries all four show* prefs in one `pushAll()` application context keyed on
  `sends*` flags (`:133-157`), decodes/persists them in `apply(context:)` (`:261-337`),
  and fires per-pref hooks (`onShowDateReceived` etc., `:284-303`). The phone sends
  (`AppViewModel.swift:24-59`, observer at `:173-180`, diff check at `:182-192`); the
  watch is receive-only (`WatchAppViewModel.swift:115`) and applies each value through an
  `@Observable` `Show*State` holder (`ShowDateState.swift:8-28`, wiring at
  `WatchAppViewModel.swift:128-139`).

## Desired End State

A user can turn the CompletionGlow off (and back on) from Settings, and the preference
applies everywhere the glow renders:

- A new `ShowCompletionGlowPreference` struct in `SingleThreadCore`, key
  `"showCompletionGlow"`, defaulting to **enabled** when the key is absent, persisted in
  `AppGroup.defaults` — a byte-for-byte sibling of `ShowDatePreference`.
- A `Toggle("Completion glow", systemImage: "sparkles")` row in `ReminderSettingsView`
  alongside the four existing show toggles, backed by a new `showCompletionGlow`
  `@AppStorage` in `ContentView` and a new field in `SettingsBindings`.
- `ContentViewModel.completeCurrentReminder()` and
  `WatchReminderViewModel.completeCurrentReminder()` read the preference at trigger time
  and skip `completionGlow.trigger()` when disabled. This covers iOS, macOS (shared
  `ContentView`/`ContentViewModel`), and watch in one rule.
- The preference propagates phone→watch through the existing `SkippedReminderSyncService`
  pipeline (new payload key + `sendsShowCompletionGlow` flag + receive hook + a
  `ShowCompletionGlowState` watch holder), so the watch's glow respects the phone's setting.

### Verification

- Unit: a `ShowCompletionGlowPreferenceTests` suite (missing→enabled, set/round-trip) via
  UUID-keyed `UserDefaults`; extend `CompletionGlowViewModelTests` to assert the glow stays
  inactive when the preference is disabled and triggers when enabled (using an injected
  UUID-keyed preference, mirroring the `InMemoryEventStore` + fake-transcriber seams).
- Unit (sync): extend `SkippedReminderSyncServiceTests` for the new push key + receive/hook,
  and `WatchSyncPipelineTests` for watch receive + relaunch survival.
- UI: a settings toggle test asserting the preference flips, plus a completion-glow UI
  flow (enabled vs disabled) via the `--seed '<json>'` seam.

## Patterns to Follow

- **Preference struct shape** — copy `ShowDatePreference` exactly: default `AppGroup.defaults`,
  `isEnabled` computed from `object(forKey:) as? Bool`, `set(_:)`
  (`ShowDatePreference.swift:11-21`). Do NOT use the `load()/save(_:)` shape of
  `ShowUndatedRemindersPreference`; that is a different (undated-reminders) family.
- **`@AppStorage` mirror + `SettingsBindings`** — every App Group preference is mirrored in
  `ContentView` (`:175-183`) and carried through `SettingsBindings`
  (`SettingsBindings.swift:15-59`) with the bag written back on change
  (`ContentView.swift:121-149`). Add `showCompletionGlow` to both.
- **DI seam for view-model logic** — inject the preference into `ContentViewModel.init` with
  a default argument, matching `speechTranscriber`/`backgroundImage` (`ContentViewModel.swift:13-21`),
  so unit tests can pass a UUID-keyed store without touching real defaults.
- **Sync service extension** — follow the `showDate` precedent end-to-end: defaulted init
  param + `sends*` flag (`SkippedReminderSyncService.swift:28-40`), `PayloadKey` string
  (`:222-235`), `pushAll()` gated on the flag (`:144-145`), `apply()` decode + persist +
  hook (`:284-288`), and a `nonisolated(unsafe) var onShowCompletionGlowReceived` hook with
  the same write-once-before-activate doc note (`:99-107`).
- **Phone-side observation** — add the new key to `handlePreferencesChanged`'s diff check and
  baselines (`AppViewModel.swift:182-204`) so toggling pushes a fresh snapshot.
- **Watch state holder** — copy `ShowDateState` (`ShowDateState.swift:8-28`): `@Observable`,
  seed from a `.standard`-backed preference, `apply(_:)` persists + republishes; wire the
  hook in `WatchAppViewModel` like `:128-130` and pass the holder into
  `WatchReminderViewModel` like the four existing (`WatchReminderViewModel.swift:11-30`).

### Patterns to NOT follow

- Do **not** attach `showPreferenceChanged()` / a widget-timeline reload to the new toggle:
  the widget does not render the glow, and `showPreferenceChanged()` exists solely to reload
  widget timelines (`SettingsViewModel.swift:19-22`). (Note `showList` already omits the hook —
  `ReminderSettingsView.swift:24-27` — which is the correct precedent here.)
- Do **not** read the preference via a `UserDefaults.standard.bool(forKey:)` computed property
  like `showsActionButtons`/`backgroundDisplayed` (`ContentViewModel.swift:41-52`): that pattern
  is `.standard`-backed and iOS-only, and would bypass the App Group / sync pipeline.
- Do **not** store in `.standard`; the sync observer watches `AppGroup.defaults` only
  (`AppViewModel.swift:173-180`), so `.standard` would strand the watch.

## Design Decisions

1. **Preference model**: new `ShowCompletionGlowPreference` struct, key `"showCompletionGlow"`,
   missing → `true`, in `AppGroup.defaults`. It matches the existing family, defaults to today's
   always-on behavior, and slots into the existing sync observation unchanged.
2. **Gate location**: gate at trigger time inside `completeCurrentReminder()`
   (`ContentViewModel.swift:106-109`, `WatchReminderViewModel.swift:44-50`). This keeps the
   decision in the view-model layer, covers iOS/macOS/watch uniformly, and matches the task's
   "suppressed after a successful completion" wording — no orphaned dismiss task runs.
3. **View-model read**: inject `showCompletionGlow: ShowCompletionGlowPreference =
   ShowCompletionGlowPreference()` into `ContentViewModel.init` and read `.isEnabled` at
   trigger time. The default arg keeps every existing call site untouched and gives tests a
   UUID-keyed seam.
4. **Settings surface**: a `Toggle("Completion glow")` row in `ReminderSettingsView` next to the
   four show toggles. Discoverable, semantically consistent, minimal UI surface.
5. **Watch sync**: full phone→watch sync mirroring the four show* prefs — new store param +
   `sendsShowCompletionGlow` flag + `PayloadKey` + `apply()` decode + `onShowCompletionGlowReceived`
   hook + `ShowCompletionGlowState` watch holder. Required because the watch renders the glow
   (`WatchReminderView.swift:84-90`) and has no local settings UI.

## What We're NOT Doing

- No widget changes: the widget neither renders the glow nor needs a timeline reload.
- No macOS-specific code: the shared `ContentView`/`ContentViewModel` covers macOS with no
  `#if os(macOS)` work.
- No watch-side settings UI: the watch remains receive-only for display preferences.
- No change to the glow's visual/animation behavior (duration, opacity, Reduce Motion
  handling, accessibility-hidden status) — this is a pure on/off gate.
- No new persistence mechanism or new sync transport: we reuse `AppGroup.defaults` and
  `SkippedReminderSyncService` as-is.
- No per-target divergence in default: the glow stays enabled everywhere until the user opts out.

## Open Risks

- **Watch default drift**: the watch seeds `ShowCompletionGlowState` from `.standard`
  (like the other `Show*State` holders), which is a different defaults domain than the
  phone's App Group. Until the first push arrives, the watch could briefly default to
  enabled while the phone is disabled. This already exists for the four show* prefs
  (`WatchAppViewModel.swift:26,110-114`) and is accepted there; the same behavior is expected
  here.
- **Sync observer baseline timing**: `lastShow*` baselines are initialized at property
  declaration (`AppViewModel.swift:201-204`); adding a fifth key must follow the same
  pattern or a spurious first push could occur.
- **UI test determinism**: a completion-glow UI test must assert the overlay (or its absence)
  reliably; the glow's 0.25s default duration means the disabled-state assertion is the
  robust one (overlay never appears), while the enabled-state assertion may need to catch the
  transient overlay quickly.
- **`SettingsBindings` parameter-list growth**: adding `showCompletionGlow` extends the
  already-large init; this is consistent with existing structure and acceptable, but watch
  for SwiftLint/format constraints.
