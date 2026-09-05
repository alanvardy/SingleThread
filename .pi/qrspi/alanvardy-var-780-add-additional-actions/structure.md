# Structure Outline

## Approach

Move `enableActionButtons` into `AppGroup.defaults` and sync it to watch, then build a toggle-gated 3-action menu (Skip / Reschedule / Delete) on every platform that supports interactive presentation — iOS confirmationDialog, macOS Menu, watch confirmationDialog — extracting the nudge sheet's DatePicker into a reusable `RescheduleSheet` along the way. Toggle-off is behaviorally identical to today.

---

## Stage1: Storage & Sync Foundation

Move `enableActionButtons` from `UserDefaults.standard` to `AppGroup.defaults`, add it to the watch-sync pipeline (PayloadKey + pushAll + apply(context:)), and create the watch-side state holder. Update both test seams so seeded launches set the toggle in the new location. **Zero UI changes** — toggle-off path is unchanged.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThread/ContentView.swift`
- `SingleThread/ContentView+Settings.swift`
- `SingleThread/ContentViewModel.swift`
- `SingleThread/AppViewModel.swift`
- `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
- `SingleThreadWatch/WatchAppViewModel.swift`
- **New**: `SingleThreadWatch/ShowEnableActionButtonsState.swift`

**Key changes**:
- `PayloadKey.enableActionButtons` — new enum case (wire value `"enableActionButtons"`)
- `pushAll()` — insert `enableActionButtons` value into snapshot context (always, like showUndatedReminders)
- `apply(context:)` — decode the new key, call `onEnableActionButtonsReceived`
- `ShowEnableActionButtonsState` — `@Observable` class, init from `.standard` (default `false`), `apply(_:)` persists + publishes (mirrors `ShowDateState.swift` pattern)
- `ContentView.swift:96-97` — `@AppStorage("enableActionButtons")` → `@AppStorage("enableActionButtons", store: AppGroup.defaults)`
- `ContentViewModel.swift:52-61` — `UserDefaults.standard.bool(forKey:)` → `AppGroup.defaults.bool(forKey:)`
- `AppViewModel.seededStore(_:)` (`:350`) — `UserDefaults.standard.set(true, …)` → `AppGroup.defaults.set(true, …)`
- `AppViewModel.makeStore` (`:291`) — same change for `--ui-testing` path
- `AppViewModel.handlePreferencesChanged` (`:432-449`) — add `enableActionButtons` to the five-key diff set
- `UITestingSeed.resetPersistedState()` (`:60-92`) — ensure `enableActionButtons` is in both `.standard` and `AppGroup.defaults` reset lists (it already is at `:86`; verify the key name matches)
- `WatchAppViewModel.wireStateReceiveHooks` (`:222-248`) — add `showEnableActionButtonsState.apply(value)` hook
- `WatchAppViewModel.setupSyncService` — add `onEnableActionButtonsReceived` handler to the service builder (defaults: `.standard`)

**Tests**:
- **New**: `ShowEnableActionButtonsPreferenceTests.swift` — nil-key reads `false` (default-off), set(true)/set(false) round-trip, serialized (shares UserDefaults)
- **Update**: `SkippedReminderSyncServiceTests.swift` — push context includes `enableActionButtons` key + value; receive decodesit and fires hook
- **Update**: `WatchSyncPipelinelTests.swift` — `apply(context:)` with the new key persists to `.standard`; absent key is a no-op
- **Existing must stay green**: `ActionButtonTests.swift` (reads toggle — now from AppGroup)

**Verify**: `make test` (unit suite) passes for this stage; `./scripts/test.sh --unit-only` as final gate.

**Toggle migration note**: existing users who had `enableActionButtons = true` in `.standard` will lose the setting on first launch after this change (reverts to `false`). Options:
- Accept the reset (toggle is off by default; likely few users had it on)
- ⭐ Add a one-shot migration: if `.standard` has the key and `AppGroup.defaults` does not, copy the value. This is ~3 lines in `AppViewModel.init` or `SingleThreadApp.init`. If chosen, add a unit test for the migration path.

---

## Stage2: Store Methods & Gate Logic

Add the watch→phone reschedule relay method on `SkippedReminderSyncService` (mirroring the delete relay), wire the phone-side receive handler, and extract a pure `showActionMenu` gate function that views consume.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- `SingleThread/AppViewModel.swift`
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
- **New**: `SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift` (or inline in ReminderStore)

**Key changes**:
- `PayloadKey.rescheduleReminderIdentifier` — new enum case (wire value `"rescheduleReminderIdentifier"`)
- `SkippedReminderSyncService.requestRescheduleReminder(identifier:dueDateComponents:)` — calls `sendMessage([PayloadKey.rescheduleReminderIdentifier: identifier, "dueDateComponents": encodedComponents])` (mirror `requestDeleteReminder` at `:230-237`)
- `SkippedReminderSyncService` init — add `sendsReschedule: Bool` parameter (default `true` on phone, `false` on watch)
- `AppViewModel.init` — wire `onRescheduleReminderReceived` hook → `await store?.rescheduleReminder(identifier:to:)`
- `ActionMenuGate.showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:) → Bool` — pure function: `enableActionButtons && canMutate && hasVisibleReminder` (the toggle-on path; toggle-off returns `false` → identical to today)

**Tests**:
- **New**: `SkippedReminderSyncServiceTests` additions — `requestRescheduleReminderSendsMessage` (sendMessage fired with correct keys), `receiveRescheduleReminder` (apply context fires hook)
- **New**: `ActionMenuGateTests.swift` — four-combination table: toggle on/off × canMutate true/false × hasReminder true/false → expected boolean (paralleling `ReminderStoreGateTests` pattern)
- **Existing must stay green**: all store tests, `EventKitStoringTests.reschedule` suite

**Verify**: `make test` passes; `swift test --filter ActionMenuGateTests` (or equivalent xcodebuild invocation) green before proceeding.

---

## Stage3: Extract RescheduleSheet

Extract the nudge sheet's DatePicker + reschedule logic into a standalone reusable `RescheduleSheet` view. The nudge sheet delegates to it (passing the nudge-specific message as optional overlay). No new behavior — pure extraction.

**Files**:
- **New**: `SingleThread/RescheduleSheet.swift`
- `SingleThread/ContentView+iOS.swift` (nudge sheet → delegate to RescheduleSheet)
- `SingleThread/ContentView.swift` (may move `rescheduleDate` @State, `nudgedReminderHasDueTime`)

**Key changes**:
- `RescheduleSheet` — `struct RescheduleSheet: View` with init params:
  - `reminder: EKReminder?` (for date-only vs date+time detection)
  - `onReschedule: (DateComponents) async -> Bool` (closure, returns success)
  - `onCancel: () -> Void`
  - `nudgeMessage: String? = nil` (optional — shown above DatePicker when nudge)
  - Accessibility ids: `rescheduleDatePicker`, `rescheduleConfirmButton`, `rescheduleCancelButton`
- Internal: `@State private var date: Date`, `displayedComponents: DatePickerComponents` based on `reminder?.dueDateComponents?.hour != nil`
- Nudge sheet (`ContentView+iOS.swift:59-86`) — replace inline DatePicker + reschedule button with `RescheduleSheet` call, pass `nudgeMessage: "This reminder keeps coming back."`
- Adjust `ContentViewModel.rescheduleNudgedReminder(to:)` or add a general `rescheduleReminder(identifier:to:)` that the sheet calls

**Tests**:
- **Existing must stay green**: `SkipNudgeUITests.swift` — banner→reschedule flow unchanged (test matches by `nudgeRescheduleButton` id, which RescheduleSheet will expose)
- **New**: `RescheduleSheetTests.swift` (if the sheet has testable logic beyond DatePicker binding) — verify `displayedComponents` logic: date-only reminder → `.date`, timed reminder → `[. .date, .hourAndMinute]`

**Verify**: `make test` + `make ui-test` (nudge UI tests still pass with the extracted sheet). The nudge `reschedule` flow in `SkipNudgeUITests.swift:55-84` must stay green.

---

## Stage4: Platform Action Menus

Build the toggle-gated action menu on each platform. All three platforms share the same gate function from Stage 2 and the `RescheduleSheet` from Stage 3. **Toggle-off path is behaviorally identical to today.**

### 4a: iOS — confirmationDialog

**Files**:
- `SingleThread/ContentView.swift`
- `SingleThread/ContentView+iOS.swift`

**Key changes**:
- `ContentView.swift` — add `@State private var isShowingActionMenu = false`, `@State private var isShowingRescheduleSheet = false`
- Attach `.confirmationDialog(…)` to the skip button in the cluster (`:526-536`), gated behind `showsActionMenu` (Stage 2 function)
- Dialog actions: **Skip** (`.default`, id `skipButton` — same id as the trigger, system handles), **Reschedule** (`.default`, id `rescheduleButton` → sets `isShowingRescheduleSheet = true`), **Delete** (`.destructive`, id `deleteButton`)
- `.sheet(isPresented: $isShowingRescheduleSheet)` presents `RescheduleSheet`
- Settlings bindings writeback (`ContentView+Settings.swift:9-46`) — `enableActionButtons` onChange already triggers @AppStorage persist; no additional writeback needed (the toggle is read live by `ContentViewModel`)

### 4b: macOS — Menu

**Files**:
- `SingleThread/ContentView.swift`

**Key changes**:
- Skip button (`:344-355`) — when `showsActionMenu`, wrap in `Menu { … } label: { … }` with `.keyboardShortcut("s")` on the Menu (or the label — verify macOS 26 behavior per open risk #2 in design.md)
- Menu items: **Skip** (`.default`, `skipButton` id), **Reschedule** (`.default` → sheet or inline DatePicker), **Delete** (`.destructive`, `.keyboardShortcut(.delete)`)
- Delete button (`:360-369`) — conditionally hidden when `showsActionMenu` is true; visible when false
- Reschedule on macOS: either present `RescheduleSheet` (if shared) or use a macOS-appropriate picker (popover with DatePicker)

### 4c: watch — confirmationDialog + Reschedule Relay

**Files**:
- `SingleThreadWatch/WatchReminderView.swift`
- `SingleThreadWatch/WatchReminderViewModel.swift`
- `SingleThreadWatch/WatchAppViewModel.swift`

**Key changes**:
- `WatchReminderView.swift:130-139` — skip button gated: when `showEnableActionButtonsState.isEnabled && canMutate`, present `.confirmationDialog` with Skip / Reschedule / Delete (matching existing pattern at `:214-228`)
- `WatchReminderViewModel` — add `@State var isShowingActionMenu = false` flag
- Reschedule on watch: calls `syncService?.requestRescheduleReminder(identifier:dueDateComponents:)` then shows a confirmation alert (EventKit is read-only on watch — no local write)
- Delete on watch: uses existing delete relay path (already in `WatchAppViewModel.swift:213-214`)
- Actions addressed by label in UI tests (ids unreachable inside watch dialogs, per precedent)

**Tests**:
- **Unit**: `ActionButtonTests.swift` — extend for menu-gate cases (toggle on + canMutate → shows menu; toggle off → direct skip; no reminder → no button)
- **iOS UI**: new `ActionMenuUITests.swift` (or extend `ActionButtonsUITests.swift`) — seed with toggle ON, tap skip → confirmationDialog appears; tap Skip → reminder advances; tap Reschedule → sheet appears, pick date, confirm → reminder rescheduled; tap Delete → reminder removed; toggle OFF → tap skip → direct skip (existing behavior). Test toggle persists across relaunch (`assertTogglePersists` pattern from `SingleThreadUITestCase.swift`)
- **Watch UI**: extend `SingleThreadWatchUITestsFlows.swift` — seed with toggle synced ON, tap skip → dialog appears by label; tap Skip → advances; tap Delete → removes; tap Reschedule → relays (verify phone-received state via unit test; UI test shows confirmation alert)
- **Existing must stay green**: all UI tests (toggle-off path identical to today), `SkipNudgeUITests.swift` (nudge sheet unchanged)

**Verify**: `make test` (unit) + `make ui-test` (iOS UI) + `make watch-ui-test` (watch UI). Manual Mac verification for Menu keyboard shortcut behavior (open risk #2).

---

## Testing Checkpoints

After each stage, these must be green before advancing:

| Stage | Checkpoint |
|---|---|
| 1| `make test` — all 552 unit tests, new preference + sync tests |
| 2| `make test` — store + gate logic tests |
| 3| `make test` + `make ui-test` — nudge flow unchanged |
| 4| `make test` + `make ui-test` + `make watch-ui-test` — all unit + platform UI tests |
| Final | `./scripts/test.sh` — full CI-identical gate (format, lint, periphery, unit, UI, watch) |

---

## File Budget Notes

- `ContentView.swift` is at 716 lines (budget 650/800) — adding confirmationDialog + Menu logic will push it over. If it exceeds 800 lines after Stage 4, split the new action-menu code into `ContentView+ActionMenu.swift` with the standard header comment citing `file_length`/`type_body_length` thresholds.
- `ContentView+iOS.swift` is at 157 lines — after RescheduleSheet extraction it will shrink (net reduction), so no split risk.
- `WatchReminderView.swift` — adding a confirmationDialog flag + dialog modifier is ~30 lines; verify against watch file_length budget if one exists.