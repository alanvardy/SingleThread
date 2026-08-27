# Research Findings

Completion-flash (`CompletionGlow`) flow across iOS + watchOS in SingleThread,
plus the gating preference and its sync pipeline. Branches:
`alanvardy-var-724-watch-doesnt-have-completion-glow`.

## Q1: How the completion-flash type is modelled and consumed

### Findings
- `CompletionGlow` is `@MainActor @Observable public final class` in
  `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift:12-13`.
- `isActive` is `public private(set) var isActive = false` (read-only outside
  the type) at `CompletionGlow.swift:17`.
- `duration` is `public var duration: TimeInterval = 0.25` (mutable, injectable;
  doc comment says "Injectable for tests (e.g. 0.05 s)") at `CompletionGlow.swift:20`.
- `trigger()` (`CompletionGlow.swift:23-37`): sets `isActive = true`, cancels the
  prior `dismissTask`, snapshots `duration` into `seconds`, then spawns a
  non-blocking `Task` that sleeps `seconds` nanoseconds and sets
  `self?.isActive = false`. A caught cancellation ("Cancelled by a newer
  trigger") leaves `isActive` untouched. Cancellation is not thrown out — the
  error path is a no-op.
- The task is stored in `private var dismissTask: Task<Void, Never>` (`CompletionGlow.swift:40`).
- iOS `ContentViewModel` owns one instance: `let completionGlow = CompletionGlow()`
  at `SingleThread/ContentViewModel.swift:37`.
- watchOS `WatchReminderViewModel` owns one: `let completionGlow = CompletionGlow()`
  at `SingleThreadWatch/WatchReminderViewModel.swift:41`.
- iOS `duration` is set to `2.0` only under the `--ui-testing-glow`
  launch-argument UI-test seam in
  `SingleThread/AppViewModel.swift:216-220` (`contentViewModel` getter).
  Production duration stays the 0.25 default; watchOW, duration is never
  mutated by any platform code.
- **Gating asymmetry (iOS vs watch):**
  - iOS `ContentViewModel.completeCurrentReminder()` triggers the glow only if
    the store backs a real completion and the preference is on — it
    reads `showCompletionGlow.isEnabled` at call time
    (`ContentViewModel.swift:108-110`). The preference is never read for the
    watch on iOS.
  - Watch: `WatchReminderViewModel.completeCurrentReminder()` triggers only if
    `showCompletionGlowState.isEnabled` is true, where that holder is fed by the
    sync receive path (`WatchReminderViewModel.swift:53-56`). The two platforms
    gate through different objects (preference vs. sync-fed state holder), not
    shared epoch logic.
- There is **no shared/epoch-gating** between the two view models — each owns a
  separate `CompletionGlow` and its own gate object.

## Q2: How the "show completion glow" preference is persisted/read

### Findings
- `ShowCompletionGlowPreference` is a struct in
  `SingleThreadCore/Sources/SingleThreadCore/ShowCompletionGlowPreference.swift`.
- `init(defaults: UserDefaults = AppGroup.defaults, key: String = "showCompletionGlow")`
  (`ShowCompletionGlowPreference.swift:9-11`).
- `isEnabled` resolves an absent key to `true — uses `defaults.object(forKey:)
  as? Bool ?? true` (not `bool(forKey:)`) at `ShowCompletionGlowPreference.swift:16-18`;
  doc comment: "nil (missing key) → true", matching "today's always-on behavior".
- `set(_:)` writes the Bool at `ShowCompletionGlowPreference.swift:20-22`.
- `AppGroup.defaults` is `UserDefaults(suiteName: "group.app.alanvardy.SingleThread")
  ?? .standard` (`SingleThreadCore/AppGroup.swift:12-16`), falling back to
  `.standard` when the suite/unregistered simulator/preview is unavailable.
- iOS settings UI wiring:
  - `SettingsBindings` carries `var showCompletionGlow: Bool` (default `true`)
    (`SingleThread/SettingsBindings.swift:65`, and init param at
    `SettingsBindings.swift:33`).
  - `SettingsView` passes `showCompletionGlow: $bindings.showCompletionGlow` into
    `ReminderSettingsView` (`SingleThread/SettingsView.swift:46,58`).
  - `ReminderSettingsView` renders a `Toggle(isOn: $showCompletionGlow) {
    Label("Completion glow", ...) }` with **no `.onChange`** — unlike `showDate`
    / `showRecurrence` / `showAlarms`, which each call
    `viewModel.showPreferenceChanged()` on change
    (`SingleThread/ReminderSettingsView.swift:15,49-53`). The glow toggle is the
    only reminder toggle with no reload/refresh hook.
  - The bag's value is written back to ContentView's `@AppStorage` on change:
    `.onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }`
    (`SingleThread/ContentView.swift:135`).
  - ContentView declares `@AppStorage("showCompletionGlow", store: AppGroup.defaults)
    private var showCompletionGlow = true` (`SingleThread/ContentView.swift:186-187`).
- Reach into ContentViewModel: at completion, `ContentViewModel` reads its
  private `showCompletionGlow` `ShowCompletionGlowPreference` (injected in
  `init`, default `ShowCompletionGlowPreference()` using `AppGroup.defaults`)
  (`ContentViewModel.swift:17,134`).
- iOS `AppViewModel` reads the same key via `ShowCompletionGlowPreference().isEnabled`
  in `handlePreferencesChanged()` and pushes a snapshot when it diff
  (`SingleThread/AppViewModel.swift:236-258`). The watch reads the flag through
  `ShowCompletionGlowState` (Q4), which uses `.standard`, not AppGroup.

## Q3: iPhone → watch propagation of the flag

### Findings
- `SkippedReminderSyncService` in
  `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
  is `NSObject, WCSessionDelegate`; sends via `updateApplicationContext`
  (latest-wins) for settings, `sendMessage` for interactive completion/delete requests.
- Init params: `showCompletionGlowStore: ShowCompletionGlowPreference =
  ShowCompletionGlowPreference()` and `sendsShowCompletionGlow: Bool = true`
  (`SkippedReminderSyncService.swift:23,32,44`). Other `sendsShow*` flags exist
  for date/recurrence/alarms/list.
- `PayloadKey.showCompletionGlow = "showCompletionGlow"` (private enum,
  `SkippedReminderSyncService.swift:241`). Shared by sender + receiver so the
  wire keys cannot drift.
- Send path in `pushAll()` — only when `sendsShowCompletionGlow` is true:
  `context[PayloadKey.showCompletionGlow] = showCompletionGlowStore.isEnabled`
  (`SkippedReminderSyncService.swift:104-105`). `pushAll()` builds one combined
  snapshot context of all synced settings
  (`SkippedReminderSyncService.swift:81-113`).
- Receive path in `apply(context:)`: if `showCompletionGlow` present as Bool,
  calls `showCompletionGlowStore.set(showCompletionGlow)` then snapshots
  `onShowCompletionGlowReceived` into a local `handler` and invokes it
  (`SkippedReminderSyncService.swift:314-317`). Absent key is a no-op.
- The `onShowCompletionGlowReceived: ((Bool) -> Void)?` hook is declared
  `nonisolated(unsafe)` with write-once-before-`activate()` doc rationale
  (`SkippedReminderSyncService.swift:65-69`).
- Per-platform send direction:
  - iOS `AppViewModel` constructs the service with `sendsShowCompletionGlow`
    left at its default **true**, so iOS pushes the flag
    (`SingleThread/AppViewModel.swift:53-72`, note only `sendsShowDate: true`
    is set explicitly on the same call).
  - WatchOS `WatchAppViewModel.setupSyncService` passes
    `sendsShowCompletionGlow: false` (all send flags off), so the watch never
    pushes; it only receives
    (`SingleThreadWatch/WatchAppViewModel.swift:117-127`).
- iOS also observes App Group UserDefaults changes and calls `syncService?.pushAll()`
  when the glow value changes via `setupSyncObservation` /
  `handlePreferencesChanged` (`SingleThread/AppViewModel.swift:236-258`).
- No `on*Received` hook is wired on iOS; the watch wires its receive hooks
  (Q4).

## Q4: How the watch consumes the flag and gates the flash

**Findings**
- `ShowCompletionGlowState` is `@Observable final class` in
  `SingleThreadWatch/ShowCompletionGlowState.swift`.
- `init()` seeds `isEnabled = preference.isEnabled`, where the holder's
  preference is `ShowCompletionGlowPreference(defaults: .standard)`
  (`ShowCompletionGlowState.swift:9-14,34-35`). Uses `.standard`, not AppGroup.
- `apply(_ value:)` persists via `preference.set(value)` then republisheds
  `isEnabled = value` (`ShowCompletionGlowState.swift:16-19`). `isEnabled` is
  `private(set)`.
- `WatchAppViewModel` creates the holder at init and wires it:
  `wireStateReceiveHooks` sets `service.onShowCompletionGlowReceived = { [weak
  showCompletionGlowState] value in Task { @MainActor in showCompletionGlowState?.apply(value) } }`
  at `SingleThreadWatch/WatchAppViewModel.swift:169-170`. The state is injected into
  `reminderViewModel` (`WatchAppViewModel.swift:59-64`).
- `WatchReminderViewModel.completeCurrentReminder()` gates on the store result
  **and** the holder before `trigger()`:
  `if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled
  { completionGlow.trigger() }` (`SingleThreadWatch/WatchReminderViewModel.swift:48-50`).
- Watch's gating object is the sync-fed `ShowCompletionGlowState`; iOS gates via
  the injected `ShowCompletionGlowPreference`. The iOS side reads the preference
  directly at trigger time; the watch side reads it through the state holder
  populated by the sync callback.

## Q5: How each platform renders the flash and reduce-motion/accessibility

**Findings**
- iOS overlay, `SingleThread/ContentView.swift` `completionGlowOverlay`
  (lines 480-493): `Color.green.opacity(0.1).ignoresSafeArea()
  .allowsHitTesting(false)` → passes touches through; `.accessibilityHidden(!isGlowUITesting)`
  — the overlay is **hidden from accessibility normally** and exposed **only** when
  `isGlowUITesting` is true (`--ui-testing-glow.html`); also
  `.accessibilityElement(children: .ignore)`,
  `.accessibilityIdentifier("completionGlowOverlay")`,
  `.accessibilityLabel("Completion glow")`, `.transition(.opacity)`.
- `isGlowUITesting` returns `ProcessInfo.processInfo.arguments.contains("--ui-testing-glow")`
  (`ContentView.swift:211-214`).
- iOS presents the overlay with an `.overlay { if isActive { completionGlowOverlay } }`
  at `ContentView.swift:80-84`, and applies
  `.animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value:
  viewModel.completionGlow.isActive)` at `ContentView.swift:85-87`.
  `reduceMotion` is `@Environment(\.accessibilityReduceMotion)`
  (`ContentView.swift:200-201`).
- Watch overlay: `SingleThreadWatch/WatchReminderView.swift` `completionGlowOverlay`
  (lines 141-148): `Color.green.opacity(0.3).ignoresSafeArea().allowsHitTesting(false)
  .accessibilityHidden(true) .transition(.opacity)`. It is **always** hidden
  from accessibility (`accessibilityHidden(true)`) — no test seam exposes it,
  and it carries no `accessibilityIdentifier`.
- Watch `reminderContent` gets `.overlay { if isActive { completionGlowOverlay } }`
  (`WatchReminderView.swift:85-88`) and `.animation(reduceMotion ? nil :
  .easeInOut(duration: 0.4), value: ...isActive)` (`WatchReminderView.swift:90-92`);
  `reduceMotion` from `@Environment(\.accessibilityReduceMotion)`
  (`WatchReminderView.swift:62-63`).
- **Reduce-motion for BOTH**: `.animation(reduceMotion ? nil : .easeInOut...)`
  — when reduce motion is on, `nil` is passed, so the opacity flash **doesn't
  animate to/from** (it snaps), but **it does NOT wipe the glow**. Neither
  platform suppresses the glow; reduce motion only disables the fade animation.
  There is no condition on either side that skips `trigger()` under reduce
  motion.
- Opacity differs per platform: iOS 0.1, watch 0.3. Both overlays pass touches
  through (`allowsHitTesting(false)`) but only iOS exposes an identifier/seam.

## Q6: Test seams and sync-pipeline coverage

**Findings**
- `CompletionGlowTests.swift` covers the state machine:
  - `glowStartsInactive`, `triggerSetsActive`, `retriggerKeepsGlowActive`,
    `glowAutoDismissesAfterDuration` — the last sets `glow.duration = 0.05`,
    triggers, then **polls for up to 2s** (`for _ in 0..<100`, sleeping 20ms each)
    for `isActive` to clear; robust against slow executors
    (`CompletionGlowTests.swift:19-46`).
  - `ContentViewModel` wiring suite (`CompletionGlowViewModelTests`):
    `glowTriggersOnSuccessfulCompletion`, `glowStaysInactiveWhenNothingToComplete`,
    `glowStaysInactiveWhenAllSkipped`, `glowStaysInactiveWhenPreferenceDisabled`,
    `glowTriggersWhenPreferenceEnabled` — build a `ReminderStore` with
    `InMemoryEventStore` and highlight that `isActive` is asserted **synchronously**
    right after `await viewModel.completeCurrentReminder()` because `trigger()`
    runs synchronously before the auto-dismiss task can fire
    (`CompletionGlowTests.swift:71-113`).
  - A fake transcriber `GlowFakeTranscriber` keeps `ContentViewModel` off the
    real speech recognizer (`CompletionGlowTests.swift:152-172`).
- `ShowCompletionGlowPreferenceTests.swift`: `missingKeyDefaultsToEnabled`,
  `setFalseRoundTrips`, `setTrueRoundTrips`, `missingKeyIsNotFalse` —
  each uses a unique `suffix` key with `.standard` and `defer removeObject`
  (`ShowCompletionGlowPreferenceTests.swift:5-27`).
- `UITestingSeed` (in SingleThreadCore): parses the `--seed '<json>'` launch
  arg into an in-memory store; `resetPersistedState()` wipes the persisted keys
  (including `showCompletionGlow`) across both `AppGroup.defaults` and
  `.standard` (`UITestingSeed.swift:3-49,81-88`).
- iOS UI test seam: `--ui-testing-glow` (1) sets `completionGlow.duration = 2.0`
  in `AppViewModel.contentViewModel` (the transient 0.25s effect becomes
  2s, deterministically observable) (`SingleThread/AppViewModel.swift:213-220`);
  and (2) exposes the overlay to the accessibility tree via
  `accessibilityHidden(!isGlowUITesting)` (`ContentView.swift:485`).
- iOS UI tests in `SingleThreadUITests/SingleThreadUITestsFlows.swift`:
  `testCompletionGlowDoesNotAppearWhenDisabled` (376) and
  `testCompletionGlowFlashesWhenEnabled` (403) both launch with
  `--seed`+`--ui-testing-glow`; the first flips the setting off and asserts
  `!app.otherElements["completionGlowOverlay"].exists` (397); the second asserts
  `waitForExistence` on the overlay after completing (415), relying on the 2 s
  duration.

- iOS sync glow cases in `SkippedReminderSyncServiceTests.swift`:
  - `pushAllIncludesShowCompletionGlowWhenEnabled` (503-519): store set true,
    `sendsShowCompletionGlow: true`, asserts `context["showCompletionGlow"] == true`.
  - `pushAllOmitsShowCompletionGlowWhenDisabled` (521-534): `sendsShowCompletionGlow:
    false`, asserts `context` has no `"showCompletionGlow"` key (nil).
  - `receiveShowCompletionGlowApplies` (536-548): `glowStore` seeded true, feeds
    `didReceiveApplicationContext:["showCompletionGlow":false]`, asserts `!glowStore.isEnabled`.
  - `receiveShowCompletionGlowFiresHook` (550-565): feeds false and asserts the
    `onShowCompletionGlowReceived` hook fired with `[false]`.
- Watch state tests `SingleThreadWatchTests/ShowCompletionGlowStateTests.swift`
  (`.serialized`, `@MainActor` because they all write the same `.standard`
  `"showCompletionGlow"` key):
  - `initialValueFromPreference`, `applyPersists`, `applyRepublishes`,
    `watchGateSuppressesGlowWhenDisabled` (apply(false) then `complete...` ⇒
    not active), `watchGateTriggersGlowWhenEnabled` (default true ⇒ active)
    (`ShowCompletionGlowStateTests.swift:41-96`).
- Watch pipeline `WatchSyncPipelineTests.swift`:
  - `receiveAppliesShowCompletionGlow` (369-384): feeds context and checks the
    store applied.
  - `showCompletionGlowSurvivesRelaunch` (389-397): feeds context then reads a
    fresh store for the same key.

## Cross-Cutting Observations
- The sync service is a single combined application-context snapshot (latest-wins);
  keys not present are no-ops; `PayloadKey` names are shared.
- Every on-show-received hook is written `nonisolated(unsafe)` and must be set
  before `activate()`; handlers are snapshotted before invocation in
  `apply(context:)`.
- The same gate name (`showCompletionGlow`) is stored in both `.standard`
  (watch, `ShowCompletionGlowState` / `ShowCompletionGlowPreference(defaults: .standard)`)
  and `AppGroup.defaults` (iOS `@AppStorage` + default injection), with
  `AppGroup.defaults` falling back to `.standard` on watch anyway — so the key
  resolves consistently in practice.
- Reduce-motion is honored only as "disable the fade animation" on both
  platforms; neither suppresses/hides the glow under reduce motion.
- Every "show X" setting (date, list, recurrence, alarms, undated, sort,
  completion-glow) follows the same pattern: a preference struct, a sync push
  flag, a PayloadKey, a receive hook, and a watch-side `*State` holder. The
  completion-glow is unique in that it's a **transient visual** gated at the
  view-model call time, rather than a rendered toggle.
- The `--seed` seam and `--ui-testing-glow` seam compose: seed gives a
  deterministic reminder list; `--ui-testing-glow` extends duration + exposes the
  overlay to accessibility.
- `.serialized` suites are used for timing-sensitive and shared-UserDefaults keys.

## Open Areas
- The other reminders-settings toggles (date/recurrence/alarms) fire a
  `showPreferenceChanged()` reload on change but the completion-glow toggle has
  **no `.onChange`** in `ReminderSettingsView`; whether that omission is
  intentional (the glow change is purely visual, not a content/layout change) is
  not explicit in code/docs.
- Whether the watch's per-reminder `complete` glow also fires when a
  completion arrives from outside the current view (e.g. a phone-side complete) is
  not addressed; only the in-view `completeCurrentReminder()` path triggers it.
- `showCompletionGlowSurvivesRelaunch` and the watch relaunch semantics are
  asserted in `WatchSyncPipelineTests`; the watch's own `.standard`-persisted
  value is asserted via the `ShowCompletionGlowState` tests.