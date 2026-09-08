# Structure Outline

## Approach

Introduce an `@Observable @MainActor` ViewModel layer between the SwiftUI view
structs and `ReminderStore`, moving presentation state, `.onChange`/`.task`
side effects, the dictation lifecycle, and the app-entry composition root out of
the views — while preserving the closure-hook architecture, launch-arg seams,
and every rendered accessibility label. Each phase delivers one end-to-end
vertical slice (store → ViewModel → view → its tests) that ships green on its
own.

---

## Phase 1: Store-derived `allSkipped` (foundation)

Move the pure store-derived `allSkipped` predicate into `ReminderStore` and
point both view surfaces at it. Establishes the "store owns store-derived
computed props" pattern the rest of the refactor leans on.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/ContentView.swift`, `SingleThreadWatch/WatchReminderView.swift`,
`SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
- `ReminderStore.allSkipped: Bool` — new computed:
  `!reminders.isEmpty && visibleReminders.isEmpty` (moved from
  `ContentView.swift:253-255`; identical to `WatchReminderView.swift:78-80`).
- `ContentView` / `WatchReminderView` — delete their private `allSkipped`
  computed; read `store.allSkipped`.

**Verify**: `make test` (new `ReminderStoreTests.allSkipped` truth-table passes,
`SingleThreadTests` still pass); `make ui-test` (empty/skipped states render the
same "No Reminders"/"All Done" labels); `make watch-ui-test`.

---

## Phase 2: `DictationViewModel` (dictation lifecycle)

Extract the 4 `@State` vars and 38-line `startDictation()` flow
(`ContentView.swift:235-238,521-558`) into a dedicated ViewModel with an
injectable `SpeechTranscribing` seam. Lives in the iOS app target because
`SpeechTranscriber` is app-target code.

**Files**: `SingleThread/DictationViewModel.swift` (new),
`SingleThread/ContentView.swift`, `SingleThreadTests/MicrophoneToggleTests.swift`,
`SingleThreadTests/ReminderDictationTests.swift`

**Key changes**:
- `@MainActor @Observable final class DictationViewModel` — new:
  - `private(set) var isDictating = false`, `dictationText = ""`,
    `dictationError: String?`, `creationFeedback: CreationFeedback?`
  - `var canDictate: Bool` — moved from `ContentView.swift:257-260`
  - `init(speechTranscriber: any SpeechTranscribing, store: ReminderStore)`
  - `func startDictation() async` — moved verbatim from `ContentView`
- `ContentView` — drop the 4 `@State` + `startDictation()`; hold a
  `DictationViewModel`; mic button calls `await dictationViewModel.startDictation()`.
  (In Phase 3 the reference relocates into `ContentViewModel`.)

**Verify**: `make test` — `MicrophoneToggleTests` + `ReminderDictationTests`
rewritten to construct `DictationViewModel` directly with `FakeTranscriber`
(same assertions). `make build`. Note: dictation is unit-tested only (TCC/speech
can't be driven in UI tests) — say so in the PR.

---

## Phase 3: `ContentViewModel` (main-view presentation + orchestration)

Move `ContentView`'s mixed-dependency presentation state and its
`.task`/`.onChange` reactions into a `ContentViewModel`; `ContentView` becomes a
display + event-forwarding shell. `@AppStorage` wrappers stay in the view (they
are the `SettingsView` binding source), but reactions delegate to the VM.

**Files**: `SingleThread/ContentViewModel.swift` (new),
`SingleThread/ContentView.swift`, `SingleThreadTests/ActionButtonTests.swift`,
`SingleThreadTests/BackgroundCardTests.swift`,
`SingleThreadTests/SingleThreadTests.swift`

**Key changes**:
- `@MainActor @Observable final class ContentViewModel` — new:
  - `var showsActionButtons: Bool` (iOS) — moved from `ContentView.swift:71-76`;
    reads `enableActionButtons` from `UserDefaults.standard` directly (not
    `@AppStorage`) so the existing `ActionButtonTests` seam stays valid.
  - `var backgroundDisplayed: Bool` — moved from `:78-80`; reads
    `backgroundEnabled` + `backgroundImage.imageData`.
  - `let dictation: DictationViewModel`
  - `init(store: ReminderStore, backgroundImage: BackgroundImageStore,
    speechTranscriber: any SpeechTranscribing)`
  - `func task() async` — seed `showsUndatedReminders` + `store.start()` +
    `backgroundImage.refreshIfNeeded(maxAge: 3600)` (from `:111-115`)
  - `func handleShowUndatedReminders(_ value: Bool) async`
  - `func handleSortOption(_ option: SortOption)`
  - `func handleAppearanceMode(_ mode: AppearanceMode)` (from `:123-128`)
- `ContentView` — remove computed props, `canDictate` (now on
  `DictationViewModel`), and inline `.task`/`.onChange` bodies; hold a
  `ContentViewModel`; call VM methods from `.task`/`.onChange`.

**Verify**: `make test` — `ActionButtonTests`, `BackgroundCardTests`,
`SingleThreadTests` rewritten to construct `ContentViewModel` and assert
`showsActionButtons`/`backgroundDisplayed`/`emptyStateCopy`. `make ui-test`
(same launch args, same accessible labels, accessibility audit passes).

---

## Phase 4: `SettingsViewModel` (settings reactions)

Move `SettingsView`'s 5 inline `.onChange` → `AppDelegate`/`WidgetCenter`
reactions into a `SettingsViewModel`. `SettingsView` stays a pure `@Binding`
pass-through; its `.onChange` closures call VM methods.

**Files**: `SingleThread/SettingsViewModel.swift` (new),
`SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`,
`SingleThreadTests/SettingsViewModelTests.swift` (new)

**Key changes**:
- `@MainActor @Observable final class SettingsViewModel` — new:
  - `func allowsLandscapeChanged(_ value: Bool)` → `AppDelegate.applyLock`
  - `func showDateChanged(_ value: Bool)` → `WidgetCenter.shared.reloadAllTimelines()`
  - `func showRecurrenceChanged(_ value: Bool)` → `WidgetCenter.shared.reloadAllTimelines()`
  - `func showAlarmsChanged(_ value: Bool)` → `WidgetCenter.shared.reloadAllTimelines()`
- `SettingsView` — add `viewModel: SettingsViewModel` init param (defaulted);
  replace inline `.onChange` closures (`:171-172,198-199,209-210,217-218`) with
  VM method calls. Binding contract unchanged.

**Verify**: `make test` (`SettingsViewTests` + new `SettingsViewModelTests`);
`make build` (macOS + iOS variants compile); `make ui-test`.

---

## Phase 5: `AppViewModel` (iOS/macOS composition root)

Move `SingleThreadApp.init`'s composition-root logic — store factory, sync
service wiring, hook plumbing, and the duplicate `@AppStorage` → `pushAll`
reactions — into an `AppViewModel`. `SingleThreadApp` shrinks to creating the
VM and handing it to `ContentView`.

**Files**: `SingleThread/AppViewModel.swift` (new),
`SingleThread/SingleThreadApp.swift`

**Key changes**:
- `@MainActor @Observable final class AppViewModel` — new:
  - `let store: ReminderStore`, `let backgroundImage: BackgroundImageStore`,
    `private(set) var syncService: SkippedReminderSyncService?`
  - `init(arguments: [String] = ProcessInfo.processInfo.arguments)` — owns
    `makeStore(arguments:)` (moved from `SingleThreadApp.swift:132-176`), all 9
    hook wirings (`:24-72`), and the `showDate`/`showRecurrence`/`showAlarms` →
    `pushAll()` reactions (`:83-93`).
  - `func pushShowDateChange()` / `pushShowRecurrenceChange()` /
    `pushShowAlarmsChange()` → `syncService?.pushAll()`
- `SingleThreadApp` — `init` becomes `let viewModel = AppViewModel()`; body
  composes `ContentView(viewModel: viewModel.contentViewModel)`. Delete the
  duplicate `@AppStorage` showDate/showRecurrence/showAlarms keys
  (`:111-118`).

**Verify**: `make ui-test` (all flows + accessibility audit pass unchanged);
`make test` (`SkippedReminderSyncServiceTests` still pass); `make watch-ui-test`
(end-to-end sync: phone push → watch applies). Manual: toggle Show Date in
Settings on the phone and confirm the watch card updates without relaunch.

---

## Phase 6: Watch ViewModels (watchOS mirror)

Mirror the iOS slices on watchOS: a `WatchReminderViewModel` for presentation +
refresh, and a `WatchAppViewModel` for the watch composition root.

**Files**: `SingleThreadWatch/WatchReminderViewModel.swift` (new),
`SingleThreadWatch/WatchAppViewModel.swift` (new),
`SingleThreadWatch/WatchReminderView.swift`,
`SingleThreadWatch/SingleThreadWatchApp.swift`

**Key changes**:
- `@MainActor @Observable final class WatchReminderViewModel` — new:
  - `var isRefreshing = false`, `var isShowingRefreshConfirmation = false`
    (from `WatchReminderView.swift:70-71`)
  - `init(store: ReminderStore, showDateState: ShowDateState,
    showRecurrenceState: ShowRecurrenceState, showAlarmsState: ShowAlarmsState)`
  - `func task() async`, `func refresh()` (from `:224-230`)
- `@MainActor @Observable final class WatchAppViewModel` — new:
  - `let store: ReminderStore` + `showDateState`/`showRecurrenceState`/
    `showAlarmsState`
  - `init(arguments: [String])` — owns `uiTestingStore(arguments:)`
    (`SingleThreadWatchApp.swift:87-125`), sync-service wiring + receive hooks
    (`:30-53`), and the `--ui-testing-live-excluded` seam (`:64-72`).
- `WatchReminderView` / `SingleThreadWatchApp` — become shells; read
  `store.allSkipped`; no behavior change.

**Verify**: `make watch-build`; `make watch-ui-test` (same launch args, same
labels); full gate `./scripts/test.sh` (format + lint + build + periphery +
unit + iOS UI + watch UI).

---

## Testing Checkpoints

- **After Phase 1** — `ReminderStore.allSkipped` exists and both views read it;
  `ReminderStoreTests` covers the truth table; all existing suites still green.
- **After Phase 2** — dictation state machine lives in `DictationViewModel`;
  `MicrophoneToggleTests` + `ReminderDictationTests` construct the VM directly
  with `FakeTranscriber`; `ContentView` has no `@State` dictation vars.
- **After Phase 3** — `ContentView` has no computed presentation props and no
  inline `.task`/`.onChange` bodies; `ActionButtonTests`/`BackgroundCardTests`/
  `SingleThreadTests` assert on `ContentViewModel`; UI labels unchanged.
- **After Phase 4** — `SettingsView` has no inline `AppDelegate`/`WidgetCenter`
  `.onChange` calls; reactions live in `SettingsViewModel`.
- **After Phase 5** — `SingleThreadApp.init` only constructs `AppViewModel`;
  duplicate `@AppStorage` sync keys removed; sync + widget reload behavior
  unchanged end-to-end.
- **After Phase 6** — watch views/app are shells; `./scripts/test.sh` fully
  green (the definitive gate).

## Notes

- **Horizontal concern, called out explicitly**: the only cross-phase work that
  *looks* horizontal is test rewriting — but each phase rewrites only the tests
  tied to that slice, so it stays vertical. There is no standalone "rewrite all
  tests" phase.
- **Phase 2 → 3 churn**: the `DictationViewModel` reference is held by
  `ContentView` in Phase 2, then relocated into `ContentViewModel` in Phase 3.
  Phase 2 can be merged into Phase 3 if the two-phase split feels heavier than
  the churn it saves.
- **Open decision for `/5_plan`**: how `AppViewModel` observes the
  `showDate`/`showRecurrence`/`showAlarms` changes to fire `pushAll()` without
  duplicate `@AppStorage` keys (Defaults observation vs. forward from
  `SettingsViewModel`/`ContentViewModel`). External behavior is identical either
  way; the plan must pick one.
