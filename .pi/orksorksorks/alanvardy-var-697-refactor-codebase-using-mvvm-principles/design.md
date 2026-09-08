# Design Discussion

## Current State

SingleThread is a SwiftUI iOS + watchOS + macOS Reminders client. The app works but
presentation logic and cross-cutting orchestration are concentrated in the SwiftUI
view structs and app entry point:

- **`ContentView`** (`SingleThread/ContentView.swift`, 635 lines) owns dictation
  state (`@State isDictating/dictationText/dictationError/creationFeedback`
  `:235-238`), the 38-line `startDictation()` flow (`:521-558`), 4 computed
  presentation properties (`showsActionButtons:71-76`, `backgroundDisplayed:78-80`,
  `allSkipped:253-255`, `canDictate:257-260`), 5 `.onChange`/`.task` side effects
  (`:111-128`), and 14 `@AppStorage` wrappers that serve as binding sources for
  `SettingsView` (`:193-232`).

- **`SettingsView`** (`SingleThread/SettingsView.swift`, 333 lines) is already a
  pure `@Binding` pass-through ("Owns no state" `:58-59`) but carries 5
  `.onChange` → AppDelegate/WidgetCenter reactions inline (`:171-172`,
  `:198-199`, `:209-210`, `:217-218`).

- **`SingleThreadApp.init`** (`SingleThreadApp.swift:17-78`) is the composition
  root: creates the store (`makeStore`:132-176), builds `SkippedReminderSyncService`
  + wires 9 store hooks (`:24-72`), creates `BackgroundImageStore` (`:74`), and
  holds duplicate `@AppStorage` keys for sync observation (`:83-118`).

- **`WatchReminderView`** (`SingleThreadWatch/WatchReminderView.swift`, 309 lines)
  holds computed `allSkipped` (`:78-80`) and store action calls inline (`:100`,
  `:113`, `:175`).

- **`SingleThreadWatchApp.init`** (`SingleThreadWatchApp.swift:10-72`) mirrors the
  iOS pattern: store creation, sync service wiring, `showDateState`/etc ownership.

- **`ReminderStore`** (`SingleThreadCore/.../ReminderStore.swift`, 382 lines) is
  the canonical `@Observable @MainActor` model. It already owns `visibleReminders`
  (`:99-107`), `hasHidden` (`:46`), `hasHiddenFor` (`:109-112`), and all mutating
  methods with closure hooks (`onSkipSetChanged:62`, `onRemindersChanged:82`, etc.).

## Desired End State

A ViewModel layer between SwiftUI views and the `ReminderStore` model, following
these MVVM conventions:

- **Views** become display + event-forwarding shells: layout, accessibility labels,
  `@AppStorage` bindings for SettingsView, and `.onAppear`/`.task` calls delegated
  to ViewModel methods. No inline `.onChange` side effects. No `@State` dictation
  state machines. No computed presentation properties beyond formatting.

- **ViewModels** (`@Observable @MainActor` classes) own: computed presentation
  state, `.onChange` → service reactions, dictation lifecycle, and testable
  orchestration logic. One ViewModel per view surface.

- **AppViewModel** (`@Observable @MainActor`) owns the composition root currently
  in `SingleThreadApp.init`: store creation, sync-service wiring, hook → service
  plumbing, and test seams. `SingleThreadApp.init` shrinks to creating
  `AppViewModel` and passing it into `ContentView`.

- **ReminderStore** gains the pure store-derived computed properties currently on
  `ContentView` (`allSkipped`).

- **Verification**: existing unit tests (`ActionButtonTests`, `BackgroundCardTests`,
  `MicrophoneToggleTests`, `ReminderDictationTests`, `SingleThreadTests`) pass
  against ViewModels instead of view structs. UI tests (`SingleThreadUITests/`)
  pass unchanged — same launch args, same accessible labels.

## Patterns to Follow

### Good patterns (match these)

- **`@Observable @MainActor` for mutable state holders**: `ReminderStore`
  (`ReminderStore.swift:5-7`), `ShowDateState` (`ShowDateState.swift:9`) — all
  ViewModels follow this. iOS app target has `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` so `@MainActor` is redundant there but include it for clarity and
  Core-package compatibility.

- **Closure hooks for cross-layer communication**: `ReminderStore` exposes optional
  closures (`onSkipSetChanged:62`, `onRemindersChanged:82`, etc.) that the app
  layer wires — never reads UserDefaults/WidgetKit itself (`:56-58`). ViewModels
  extend this pattern: they consume store hooks and call into sync/Widget services.

- **Preference-store protocol pattern**: `ShowDatePreference`, `ShowRecurrencePreference`,
  `ShowAlarmsPreference` each wrap a `UserDefaults` suite + key (`ShowDatePreference.swift:10-17`).
  ViewModels use these for typed read/write instead of raw `UserDefaults` strings.

- **Test seams via init injection**: `ReminderStore.init` accepts injectable stores
  and pre-seeded state (`ReminderStore.swift:14-34`). `ContentView.init` has a
  preview-only overload (`ContentView.swift:565+`). ViewModels mirror this: init
  accepts store + fakes, tests construct ViewModels directly.

- **`@AppStorage` stays in views for SettingsView binding chain**: `SettingsView`
  is a pure `@Binding` consumer (`SettingsView.swift:58-59`). `@AppStorage` is
  SwiftUI-only; keep the binding source in `ContentView` but delegate reaction
  logic to ViewModel methods.

### Patterns to avoid

- **Inline `.onChange` side effects calling AppDelegate/WidgetCenter from views**:
  `ContentView.swift:123-128`, `SettingsView.swift:171-172,198-199,209-210,217-218`.
  These move to ViewModel methods.

- **Duplicate `@AppStorage` keys in App struct for observation**: `SingleThreadApp`
  holds `showDate`/`showRecurrence`/`showAlarms` (`SingleThreadApp.swift:111-118`)
  solely for `.onChange` → `pushAll`. AppViewModel owns these directly via
  preference-store reads, eliminating the duplication.

- **`@State` dictation machine in a view**: `ContentView.swift:235-238` — 4 `@State`
  vars + 38-line `startDictation()` (`:521-558`). Moves to `DictationViewModel`.

## Design Decisions

1. **ViewModel granularity — one per view**: `ContentViewModel`, `SettingsViewModel`,
   `WatchReminderViewModel`. Each view gets its own ViewModel. `SettingsViewModel`
   owns the `.onChange` → WidgetCenter/AppDelegate reactions currently inline in
   `SettingsView`. `WatchReminderViewModel` owns watch-specific presentation
   (`allSkipped`, `noRemindersState`) and refresh logic.

2. **Store-derived computed props move into `ReminderStore`**: `allSkipped` (pure
   store derivation, `ContentView.swift:253-255`) moves to `ReminderStore` as a
   computed `var`. Mixed-dependency properties (`showsActionButtons:71-76`,
   `backgroundDisplayed:78-80`) stay in `ContentViewModel` — they depend on
   `@AppStorage`/`BackgroundImageStore` outside the store's domain.

3. **Dedicated `DictationViewModel`**: Owns `isDictating`, `dictationText`,
   `dictationError`, `creationFeedback` state and the `startDictation()` flow
   (`ContentView.swift:235-238,521-558`). Accepts `SpeechTranscribing` via init
   (test seam for `FakeTranscriber`). `ContentViewModel` holds a reference.
   Existing `MicrophoneToggleTests` and `ReminderDictationTests` rewrite to
   construct `DictationViewModel` directly.

4. **`AppViewModel` as `@Observable` composition root**: Owns `ReminderStore`,
   `BackgroundImageStore`, `SkippedReminderSyncService?`, wires all store hooks
   (`SingleThreadApp.swift:24-72`), and holds the `showDate`/`showRecurrence`/
   `showAlarms` → `pushAll` reactions (`:83-93`). `makeStore(arguments:)` moves
   from `SingleThreadApp` into `AppViewModel`. `SingleThreadApp.init` shrinks to
   creating `AppViewModel` and passing it to `ContentView`. Watch counterpart:
   `WatchAppViewModel`.

5. **Test ViewModels directly**: Unit tests construct ViewModels with injected
   store + fakes, assert on ViewModel computed properties. Example:
   `ActionButtonTests.swift:57` currently constructs `ContentView` — rewritten to
   construct `ContentViewModel` and assert `showsActionButtons`. UI tests
   (`SingleThreadUITests/`) are unchanged — they drive the real app via launch args,
   and the rendered accessible labels must stay identical.

## What We're NOT Doing

- **Not changing the data layer**: `ReminderStore`, `EventKitStoring`, preference
  stores, `SkippedReminderSyncService`, and `BackgroundImageStore` are unchanged
  except for moving `allSkipped` into the store. The closure-hook architecture
  for sync transport stays.

- **Not touching the widget extension**: `SingleThreadWidget/` reads `AppGroup.defaults`
  directly — no ViewModel change affects it.

- **Not changing SettingsView's binding contract**: SettingsView remains pure
  `@Binding` pass-through. `@AppStorage` stays in ContentView for binding plumbing.
  `SettingsViewModel` owns the reaction logic but the binding chain is unchanged.

- **Not migrating watchOS `ShowDateState`/`ShowRecurrenceState`/`ShowAlarmsState`**:
  These are already `@Observable` classes (`ShowDateState.swift:9`) acting as
  mini-ViewModels — they stay as-is. `WatchReminderViewModel` composes them.

- **Not changing UI layout, accessibility labels, or `.task`/`.refreshable`
  behavior**: Views render identically. UI tests continue to pass.

- **Not introducing a protocol layer for ViewModels**: ViewModels are concrete
  `@Observable` classes. No `ContentViewModelProtocol` — the test seam is the
  injectable init parameters, same pattern as `ReminderStore`.

## Open Risks

- **`@AppStorage` binding chain to SettingsView**: `@AppStorage` only works in
  SwiftUI views. If preference state moves to `ContentViewModel`, the 14 `$binding`
  sources for `SettingsView` need a bridging strategy. Current plan: keep
  `@AppStorage` in ContentView for the binding pipe, delegate reactions to
  ViewModel. Risk: this leaves some `@AppStorage` wrappers in ContentView,
  limiting how thin the view becomes.

- **`SpeechTranscribing` protocol dependency**: `DictationViewModel` needs a
  `SpeechTranscribing` reference. `ContentView.init` currently takes
  `speechTranscriber: any SpeechTranscribing = SpeechTranscriber()` — the
  ViewModel init mirrors this. Risk: `SpeechTranscriber` lives in the iOS app
  target, not Core, so `DictationViewModel` lives in the app target too.

- **`AppViewModel` vs `SingleThreadApp` property lifecycle**: `SingleThreadApp` is
  a `@main struct App` — its stored properties (including the new `AppViewModel`)
  persist for the app lifetime. The `@UIApplicationDelegateAdaptor` and
  `@NSApplicationDelegateAdaptor` stay on the App struct. Risk: if
  `AppViewModel` needs delegate callbacks, wiring crosses the App/ViewModel
  boundary — but current delegate methods (`AppDelegate.applyAppearance`,
  `applyLock`) are static, so this is low-risk.

- **Test rewrite scope**: `ActionButtonTests`, `BackgroundCardTests`,
  `MicrophoneToggleTests`, `ReminderDictationTests`, and `SingleThreadTests` all
  construct `ContentView` directly. Each needs rewriting to construct ViewModels.
  Risk: rewrites must preserve the exact assertions (accessibility labels, body
  descriptions) that the existing tests verify — or tests must shift to
  ViewModel-level assertions.