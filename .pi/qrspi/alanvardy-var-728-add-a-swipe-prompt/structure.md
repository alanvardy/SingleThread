# Structure Outline

## Approach

Add a single iOS-only `@AppStorage` boolean (`"showSwipePrompt"`, default
`true`) through the existing `SettingsBindings` bag → `@AppStorage` →
`.onChange` write-back pattern (same as `enableActionButtons`), gate a toggle
in `InterfaceSettingsView` behind `#if os(iOS)`, and render a dismissible
prompt inside `ReminderCardView`'s `VStack` after the notes block. No
`Show*Preference` struct, no watch sync, no `SingleThreadCore` changes.

---

## Stage 1: Persistence + Bindings + Test Infrastructure

Wire the `showSwipePrompt` boolean end-to-end through the persistence
layer — `SettingsBindings` property, `@AppStorage` declaration,
`makeSettingsBag()` injection, `.onChange` write-back, `--ui-testing` pre-set,
and `UITestingSeed.persistedKeys` — so the value can be read, written, and
reset. No UI reads it yet.

**Files**: `SingleThread/SettingsBindings.swift`,
`SingleThread/ContentView.swift`, `SingleThread/AppViewModel.swift`,
`SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`

**Key changes**:

- `SettingsBindings.swift`: new property `var showSwipePrompt: Bool = true`
  (alongside `enableActionButtons` at ~:53); new init parameter
  `showSwipePrompt: Bool = true` (in init signature at ~:19–33)

- `ContentView.swift`: new `@AppStorage("showSwipePrompt") private var showSwipePrompt = true`
  inside `#if os(iOS)` block (alongside `enableActionButtons` at ~:164–167)

- `ContentView.swift`: new `.onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }`
  inside `#if os(iOS)` block in the write-back chain (~:124–125)

- `ContentView.swift` `makeSettingsBag()` iOS branch (~:503–520): add
  `showSwipePrompt: showSwipePrompt` to the `SettingsBindings(...)` call

- `AppViewModel.swift` `--ui-testing` block (~:146): add
  `UserDefaults.standard.set(true, forKey: "showSwipePrompt")`
  alongside the existing `enableActionButtons` pre-set

- `UITestingSeed.swift` `persistedKeys` array (~:52–70): append
  `"showSwipePrompt"` (alphabetical position, between `"showMicrophoneButton"`
  and `"showUndatedReminders"`)

**Tests**:

- `SingleThreadTests/SettingsViewTests.swift`: new test
  `settingsBindingsCarriesShowSwipePrompt` — verifies default `true` and
  explicit `false` round-trips through the bag init (mirrors
  `settingsBindingsCarriesShowCompletionGlow` at :12–18)

- `SingleThreadTests/UITestingSeedTests.swift`: new test
  `resetPersistedStateClearsShowSwipePrompt` — sets key to `false`, calls
  `UITestingSeed.resetPersistedState()`, asserts
  `UserDefaults.standard.object(forKey: "showSwipePrompt") == nil` (mirrors
  `resetPersistedStateClearsBackgroundEnabled` at :63–68)

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SettingsViewTests \
  -only-testing:SingleThreadTests/UITestingSeedTests
```

---

## Stage 2: Settings Toggle

Add the "Show swipe prompt" toggle to Interface Settings, gated `#if os(iOS)`,
and wire it through `SettingsView` → `InterfaceSettingsView` via the
`SettingsBindings` bag. A snapshot test proves the label appears.

**Files**: `SingleThread/InterfaceSettingsView.swift`,
`SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:

- `InterfaceSettingsView.swift`: new `@Binding var showSwipePrompt: Bool`
  inside existing `#if os(iOS)` block (~:19–21), next to `enableActionButtons`

- `InterfaceSettingsView.swift` body: new `Toggle(isOn: $showSwipePrompt) { Label("Show swipe prompt", systemImage: "arrow.left.arrow.right") }`
  inside existing `#if os(iOS)` block, after the `enableActionButtons` toggle
  (~:51–53 area)

  > No `.onChange` side-effect hook — unlike `allowsLandscape`
  > (orientation lock), toggling the prompt has no system-level side effect.

- `InterfaceSettingsView.swift` `#Preview`: add `showSwipePrompt: .constant(true)`
  to the `#if os(iOS)` branch

- `SettingsView.swift` `#if os(iOS)` `InterfaceSettingsView` initializer
  (~:35–41): add `showSwipePrompt: $bindings.showSwipePrompt` parameter

**Tests**:

- `SingleThreadTests/SettingsViewTests.swift`:
  `interfaceSettingsViewContainsExpectedRows` — append
  `"Show swipe prompt"` to the `#if os(iOS)` `expectedLabels` array (~:53)
  alongside `"Allow landscape"` and `"Show action buttons"`

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SettingsViewTests
```

---

## Stage 3: Card Prompt View

Add the instructional prompt and Dismiss button to `ReminderCardView`, gated
by a `@Binding` to the `showSwipePrompt` boolean. The prompt sits inside the
card's `VStack` after the notes block, hidden when the binding is `false`.
Accessibility: prompt container is `accessibilityHidden(true)`, Dismiss button
has `.accessibilityLabel("Dismiss swipe prompt")`.

**Files**: `SingleThread/ReminderCardView.swift`,
`SingleThread/ContentView.swift`, `SingleThreadTests/SwipePromptTests.swift`
(new)

**Key changes**:

- `ReminderCardView.swift` init: new parameter
  `showSwipePrompt: Binding<Bool>` (first `@Binding` on this view; stored as
  `@Binding private var showSwipePrompt: Bool`)

- `ReminderCardView.swift` body, after the notes block
  (`if let notesAttr ...` at ~:68–73):
  ```swift
  if showSwipePrompt {
      VStack(alignment: .leading, spacing: 8) {
          Text("← Swipe left to skip  |  Swipe right to complete →")
              .font(.caption)
              .foregroundStyle(.secondary)
          Button {
              showSwipePrompt = false
          } label: {
              Text("Dismiss")
                  .font(.caption)
          }
          .accessibilityLabel("Dismiss swipe prompt")
      }
      .accessibilityHidden(true)
  }
  ```

- `ContentView.swift` `ReminderCardView` call site (~:311–316): add
  `showSwipePrompt: $showSwipePrompt` parameter

  > `showSwipePrompt` is the `@AppStorage` property from Stage 1; the `$`
  > projection gives the card a read/write binding so Dismiss → `false`
  > persists directly.

**Tests** (new file `SingleThreadTests/SwipePromptTests.swift`):

- `promptShownWhenEnabled`: build card with `showSwipePrompt: true`, assert
  `String(describing:)` body contains `"← Swipe left to skip"` and `"Dismiss"`

- `promptHiddenWhenDisabled`: build card with `showSwipePrompt: false`, assert
  body does NOT contain `"← Swipe left to skip"`

- `dismissButtonHasAccessibilityLabel`: assert body contains
  `"Dismiss swipe prompt"` (the `.accessibilityLabel` string appears in the
  snapshot as an `accessibilityLabel` modifier)

- Follow the existing `makeCard` helper pattern (`ShowDateTests.swift:44–54`)
  for building `ReminderCardView` fixtures with a `ReminderDisplay` + constant
  bindings

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/SwipePromptTests
```

Then run the full unit suite to confirm existing snapshot tests still pass
(adding a `@Binding` parameter to `ReminderCardView` changes every call site,
including existing test helpers — `ShowDateTests.makeCard`, `ShowAlarmsTests`,
`ShowRecurrenceTests`):
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests
```

---

## Stage 4: UI Tests + Accessibility Audit

Add UI-test flows covering prompt visibility, Dismiss persistence across
launches, and Settings toggle round-trip. Verify the accessibility audit
continues to pass with the prompt in the view hierarchy.

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`,
`SingleThreadUITests/SingleThreadUITests.swift` (accessibility audit —
possibly no source changes needed, just confirmation)

**New tests** in `SingleThreadUITestsFlows.swift`:

- `testSwipePromptAppearsUnderUITesting`:
  1. Launch with `--ui-testing` (which pre-sets `showSwipePrompt = true`)
  2. Assert `app.staticTexts` contains `"← Swipe left to skip"`
  3. Assert `app.buttons["Dismiss swipe prompt"]` exists

- `testDismissSwipePromptHidesItAndPersistsAcrossRelaunch`:
  1. Launch `--ui-testing` → prompt visible
  2. Tap `app.buttons["Dismiss swipe prompt"]`
  3. Assert prompt text is gone
  4. `app.terminate()`
  5. Relaunch with `--ui-testing` (NOT `--seed` — that calls
     `resetPersistedState()` and would undo the dismiss)
  6. Assert prompt text is still gone

- `testSwipePromptToggleRoundTripsViaSettings`:
  1. Launch `--ui-testing` → open Settings → Interface
  2. `app.switches["Show swipe prompt"].value` is `"1"` (on by default)
  3. Flip toggle to `"0"` (use existing `flipToggle` helper,
     `SingleThreadUITestsFlows.swift:326–344`)
  4. Navigate back, tap Done
  5. Assert prompt text is gone from main screen
  6. Re-open Settings → Interface, assert switch value is `"0"`
  7. Flip back to `"1"`, Done, assert prompt is visible again

**Accessibility**:
- Run `testAccessibilityAudit()` (`SingleThreadUITests.swift:27–64`) —
  the prompt container is `accessibilityHidden(true)` and the Dismiss button
  has an explicit label; the audit should pass unchanged for both `.combine`
  card reading and button traits

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadUITests
```

---

## Testing Checkpoints

After each stage, these must be green before advancing:

| Stage | Checkpoint |
|---|---|
| 1 | `SettingsViewTests.settingsBindingsCarriesShowSwipePrompt` ✅ + `UITestingSeedTests.resetPersistedStateClearsShowSwipePrompt` ✅ |
| 2 | `SettingsViewTests.interfaceSettingsViewContainsExpectedRows` contains `"Show swipe prompt"` ✅ |
| 3 | `SwipePromptTests` (all) ✅ + all existing `SingleThreadTests` still pass ✅ |
| 4 | All UI tests (`SingleThreadUITests`) ✅ |
| Gate | `./scripts/test.sh` passes end-to-end ✅ |

## Cross-Cutting Notes

- **`ReminderCardView` init signature change (Stage 3)** adds a `Binding`
  parameter. Every existing test helper that constructs `ReminderCardView`
  (`ShowDateTests.makeCard`, `ShowAlarmsTests`, `ShowRecurrenceTests`) must
  be updated with a `.constant(true)` binding. This is a mechanical change
  across ~4 test files — done in Stage 3 alongside the new `SwipePromptTests`.

- **No `SingleThreadCore` files changed** except `UITestingSeed.swift`
  (appending one string literal). This stays true to the design decision:
  iOS-only UI preferences don't need `Show*Preference` structs, watch-sync
  wiring, or a `SingleThreadCore`-side API.

- **Stage dependency check**: Stage 3 depends on Stage 1 (for `$showSwipePrompt`
  binding on `ContentView`) but does NOT depend on Stage 2 (the toggle). Stages
  2 and 3 could theoretically be reversed — the card prompt can be built and
  tested before the settings toggle exists. The current ordering puts the
  settings toggle first because it's the simpler incremental layer (one
  toggle in an existing form). ~2 pages is the bar.

- **`showSwipePrompt` stored in `.standard`**, not `AppGroup.defaults`, matching
  `enableActionButtons` and `allowsLandscape`. This means it does NOT sync to
  watch — correct for an iOS-only UI preference.