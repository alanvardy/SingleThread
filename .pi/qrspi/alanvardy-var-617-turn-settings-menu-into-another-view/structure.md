# Structure Outline

## Approach

Replace the top-trailing settings `Menu` with a gear `Button` that presents a
`Form`-based `SettingsView` as a modal `.sheet` dismissed by "Done" or swipe.
`ContentView` keeps owning the four `@AppStorage` values and passes `@Binding`s
down; `SettingsView` re-applies appearance/text-size to itself and re-locates
the iOS landscape→orientation side-effect. No `NavigationStack`, no key renames.

### Slicing constraint (noted explicitly)

The four controls all live in a single `Menu` container
(`ContentView.swift:273-303`), and a `Menu` is one host whose contents cannot be
presented in a sheet one item at a time without either shipping two competing
settings UIs or temporarily deleting preferences. Phase 1 therefore performs
the **atomic container swap** (all four rows move together). Later phases each
deliver a distinct, independently-verifiable behavior on top. This is the one
place the design resists finer vertical slicing.

---

## Phase 1: Settings sheet — atomic container swap

Delivers the end-state UI in one vertical slice: the gear becomes a plain
`Button` that presents `SettingsView` containing all four preference rows.
Toggles write through `@Binding` → `@AppStorage`, so persistence is
end-to-end working. Two behaviors are intentionally deferred (live feedback
in Phase 2, orientation re-lock in Phase 3).

**Files**: `SingleThread/SettingsView.swift` (new), `SingleThread/ContentView.swift`

**Key changes**:

- `struct SettingsView: View` — new type with:
  ```swift
  @Binding var appearanceMode: AppearanceMode
  @Binding var textSize: TextSize
  #if os(iOS)
      @Binding var allowsLandscape: Bool
  #endif
  @Binding var showMicrophoneButton: Bool
  @Environment(\.dismiss) private var dismiss
  ```
  `body`: a `Form` with a `Picker("Appearance")`, `Picker("Text Size")`,
  iOS-only `Toggle("Landscape")`, `Toggle("Microphone")`, plus a
  `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }`.
- `ContentView`: `@State private var isShowingSettings = false`; gear
  `Menu` → `Button { isShowingSettings = true }` keeping `gearshape`,
  frame, `.contentShape`, `.foregroundStyle(.secondary)`,
  `.accessibilityLabel("Settings")`, and adding
  `.accessibilityAddTraits(.isButton)`.
- `.sheet(isPresented: $isShowingSettings)` — call site passes the bindings
  conditionally (the `allowsLandscape` arg exists only on iOS):
  ```swift
  #if os(iOS)
      SettingsView(appearanceMode: $appearanceMode, textSize: $textSize,
                   allowsLandscape: $allowsLandscape, showMicrophoneButton: $showMicrophoneButton)
  #else
      SettingsView(appearanceMode: $appearanceMode, textSize: $textSize,
                   showMicrophoneButton: $showMicrophoneButton)
  #endif
  ```
- Delete the `settingsMenu` computed property. Keep the root
  `.preferredColorScheme` / `.modifier(TextSizeModifier(...))` on `ContentView`.

**Verify**: `make build` passes; `make test` (unit) still green. Manual: gear
opens a sheet with all four rows; toggling any preference persists across a
relaunch; "Done" and swipe-down both dismiss. *Deferred (known gaps)*: text
size / appearance don't yet live-update *inside* the sheet, and the landscape
toggle writes the binding but doesn't re-lock orientation.

---

## Phase 2: Live feedback inside the sheet

Re-applies appearance and text-size effects on `SettingsView` so the sheet
reflects changes immediately and doesn't depend on sheet environment
inheritance (Design Decision 3).

**Files**: `SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`

**Key changes**:

- `ContentView`: widen `private struct TextSizeModifier` → `struct
  TextSizeModifier` (internal). **Required** — it's currently file-private so
  `SettingsView.swift` cannot reference it.
- `SettingsView.body` gains:
  ```swift
  .preferredColorScheme(appearanceMode.colorScheme)
  .modifier(TextSizeModifier(textSize: textSize))
  ```

**Verify**: `make build`; manual: inside the sheet, change Appearance / Text
Size and watch the sheet itself update immediately.

---

## Phase 3: Orientation lock + cross-platform gating

Restores the landscape toggle's side-effect (moved with the row, per Design
Decision 5) and proves the macOS build compiles the three-row `Form`.

**Files**: `SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`

**Key changes**:

- `SettingsView`: under `#if os(iOS)` add
  ```swift
  Toggle(isOn: $allowsLandscape) { Label("Landscape", systemImage: "rectangle.landscape.rotate") }
      .onChange(of: allowsLandscape) { _, newValue in
          AppDelegate.applyLock(allowsLandscape: newValue)
      }
  ```
- Confirm no change to `AppDelegate.swift` / `"allowsLandscape"` (launch-time
  lock reads raw `UserDefaults` independently and stays untouched).

**Verify**: `make build` (iOS); `make mac-build` compiles a three-row `Form`
with no `allowsLandscape` parameter; `make test` — `AppDelegateTests`,
`AppearanceModeTests`, `TextSizeTests` remain green. Manual: toggling
Landscape inside the sheet immediately locks/rotates orientation.

---

## Phase 4: Test coverage + full pipeline

Adds the test suite and locks everything with the CI-identical gate.

**Files**: `SingleThreadTests/SettingsViewTests.swift` (new),
`SingleThreadTests/MicrophoneToggleTests.swift`

**Key changes**:

- `struct SettingsViewTests` (Swift Testing, `@Test`, `#if os(iOS)` around the
  landscape argument since mac-test runs the same file): construct
  `SettingsView(appearanceMode: .constant(.system), …)` and assert
  `String(describing: view.body)` contains `"Appearance"`, `"Text Size"`,
  `"Microphone"`, `"Done"`, and (iOS) `"Landscape"`.
- `MicrophoneToggleTests`: add a gear assertion
  (`String(describing: ContentView(…).body).contains("gearshape")`) proving the
  entry point survived; keep the mic-gating tests (they exercise `bottomBar`,
  unaffected).

**Verify**: `./scripts/test.sh` passes end-to-end (format, lint, build,
Periphery, unit, UI + accessibility audit). `make ui-test` confirms the audit
still exercises only the main screen (no sheet-navigation test). Manual:
mic toggle still gates the `mic.fill` button on the main list.

---

## Testing Checkpoints

- **After Phase 1**: app builds; sheet opens with 4 rows; persistence works;
  Done + swipe dismiss. *Known*: no in-sheet live feedback, no orientation
  re-lock yet.
- **After Phase 2**: appearance/text-size update live inside the sheet;
  `TextSizeModifier` is now internal (shared between two files).
- **After Phase 3**: iOS locks orientation on toggle; macOS builds the 3-row
  `Form`; `AppDelegate` untouched.
- **After Phase 4**: `./scripts/test.sh` fully green; gear presence and all
  four controls asserted by unit tests; `SettingsView` covered cross-platform.