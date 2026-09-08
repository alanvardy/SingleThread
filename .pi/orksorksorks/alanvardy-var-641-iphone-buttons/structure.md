# Structure Outline

## Approach

Add an iOS-only `@AppStorage("enableActionButtons")` toggle (default `false`, `.standard` persistence). When on **and** a visible reminder exists, the bottom bar flanks the mic with Complete (left) / Skip (right) using the watch action styling; all four action surfaces already share the same idiom, so this reuses existing store calls and adds **no** new persistence or store API.

> **Note on slicing**: this feature adds no database/service-layer work — it reuses `ReminderStore.completeCurrentReminder()` / `skipCurrentReminder()` and `@AppStorage`. The "layers" here are persistence (toggle), view rendering (bottom bar), settings surface, and test scaffolding. Each phase still lands a user-visible behavior with an automated checkpoint.

## Phase 1: Settings toggle backbone

Persists the "Enable action buttons" toggle on-device and exposes it in Settings. The bottom bar is unchanged (toggle is off by default), so app behavior stays identical.

**Files**: `SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `#if os(iOS) @AppStorage("enableActionButtons") private var enableActionButtons = false #endif` — new, near `showMicrophoneButton` (`ContentView.swift:184-185`), standard defaults
- iOS `.sheet` call (`ContentView.swift:94-107`): add `enableActionButtons: $enableActionButtons`
- `SettingsView` iOS `init` (`SettingsView.swift:62-74`): new param `enableActionButtons: Binding<Bool>`; non-iOS init untouched
- iOS-only row next to "Show Microphone" (`SettingsView.swift:136-138`): `Toggle(isOn: $enableActionButtons) { Label("Enable action buttons", systemImage: "hand.tap") }` (systemImage is a choice)

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes with a new `SettingsViewTests` assertion (`bodyDescription.contains("Enable action buttons")`); manual: open Settings on iPhone sim → row appears; toggle on, relaunch → still on.

---

## Phase 2: Bottom-bar Complete/Skip cluster

Renders the full feature: toggle on + visible reminder → Complete/Skip flank the mic with watch styling; buttons invoke the existing store calls (Complete async, Skip sync). This is the end-to-end slice — settings toggle → rendered buttons → EventKit write / shared skip list.

**Files**: `SingleThread/ContentView.swift`, `SingleThreadTests/ActionButtonTests.swift` (new, mirrors `MicrophoneToggleTests.swift`)

**Key changes**:
- In `bottomBar` mic branch (`ContentView.swift:394-395`): `else if canDictate, showMicrophoneButton { if enableActionButtons, store.visibleReminders.first != nil { actionCluster } else { micButton } }`
- New private views (watch styling from `WatchReminderView.swift:86-101`):
  - `private var completeButton: some View` — `Button { Task { await store.completeCurrentReminder() } }`, `Label("Complete", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)`, `.tint(.green)`, `.frame(width: 44, height: 44)`, `.accessibilityLabel("Complete reminder")`, `.accessibilityAddTraits(.isButton)`
  - `private var skipButton: some View` — `Button { store.skipCurrentReminder() }`, `circle.slash`, `.tint(.orange)`, same frame/traits, `.accessibilityLabel("Skip reminder")` (sync — do **not** use `skipCurrentReminderImmediately()`)
  - `private var actionCluster: some View` — `HStack(spacing: 16, alignment: .center) { completeButton; micButton; skipButton }` (symmetric 44pt frames keep the 56pt mic centered)
- No `ReminderStore` API changes.

**Verify**: new unit tests using `ContentView(store: prepopulatedStore, speechTranscriber: fakeAuthorized)` + `UserDefaults.standard.set(true, "enableActionButtons")` assert body description contains "Complete" and "Skip"; absent when toggle off or no visible reminder; existing `SettingsViewTests` / `ReminderStoreTests` stay green. Manual: toggle on → cluster appears; Complete advances the card and writes to EventKit; Skip advances the card and persists to the shared skipped list.

---

## Phase 3: UI-test seam + accessibility

Makes the new buttons visible to the `--ui-testing` app (currently an **empty** store, `SingleThreadApp.swift:16-20`, so the cluster can't render or be audited) and covers them with an interaction + accessibility test. Crosses app entry point → UI test target.

**Files**: `SingleThread/SingleThreadApp.swift`, `SingleThreadUITests/SingleThreadUITests.swift` (or new `SingleThreadUITests/ActionButtonsUITests.swift`)

**Key changes**:
- iOS `SingleThreadApp`: on `--ui-testing`, build `Self.uiTestingStore()` mirroring the watch seam (`SingleThreadWatchApp.swift:61-77`) — `ReminderStore(loadsReminders: false, reminders: [seededReminder], skippedIDs: [], authorizationStatus: .fullAccess)` — and seed the toggle (`UserDefaults.standard.set(true, "enableActionButtons")` in the seam or a dedicated launch argument). Existing UI tests only wait for "any static text" (`SingleThreadUITests.swift:21`), so seeding is compatible.
- New UI test: launch with the seed + launch argument, assert `app.buttons["Complete reminder"]` / `["Skip reminder"]` exist (waitForExistence), tap Skip → assert the displayed card advances; reuse `performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` — now exercising the two new buttons.

**Verify**: `make ui-test` (or `xcodebuild test ... -only-testing:SingleThreadUITests`) passes — buttons present, skip interaction works, audit clean (no hit-region / description / trait failures). Manual: seeded sim launch shows the cluster; audit passes with the new elements.

---

## Testing Checkpoints

- **After Phase 1**: `SettingsViewTests` proves the new row; toggle persists; app behavior otherwise unchanged (off-by-default → no UI regression risk).
- **After Phase 2**: full feature functional — unit tests prove the on/visible-reminder gating; `ReminderStoreTests` already prove the skip/complete persistence paths.
- **After Phase 3**: end-to-end UI + accessibility verification. Run `./scripts/test.sh` for the full CI-identical gate (format, lint, periphery, unit, UI).