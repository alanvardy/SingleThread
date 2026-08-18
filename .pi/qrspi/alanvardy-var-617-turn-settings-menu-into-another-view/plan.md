# Implementation Plan

## Overview

Replace the top-trailing gear `Menu` with a plain gear `Button` that presents a
`Form`-based `SettingsView` as a modal `.sheet` (dismissed by "Done" or
swipe), keeping the same four `@AppStorage`-backed preferences and their
effects end-to-end. No `NavigationStack`, no key renames, no changes to enum
shapes or defaults.

> **Two empirically-verified corrections to `structure.md`/`design.md`**
> (confirmed by compiling standalone SwiftUI snippets): (1) `Image(systemName:)`
> SF-Symbol names such as `"gearshape"` do **not** appear in
> `String(describing: view.body)` — the `Image` describes as a boxed
> `NamedImageProvider` — so the gear-presence assertion must use the button's
> `.accessibilityLabel("Settings")` (which *does* appear) instead of
> `"gearshape"`. (2) A `.sheet`'s lazily-presented `content:` closure is *not*
> part of the hosting view's `body` description, so moving the four rows out of
> the `Menu` removes `"Microphone"` from `ContentView.body` — the existing
> `settingsMenuContainsMicrophoneToggle` test must be repurposed in Phase 1
> (atomically with the container swap), not left for Phase 4.

---

## Phase 1: Settings sheet — atomic container swap

Delivers the end-state UI in one slice: gear becomes a `Button`, presents
`SettingsView` with all four rows, persistence works via `@Binding` →
`@AppStorage`. Live feedback (Phase 2) and orientation re-lock (Phase 3) are
deferred.

### Changes

#### 1. New settings screen
**File**: `SingleThread/SettingsView.swift`
**Action**: create

Placed directly in `SingleThread/` (synchronized file group auto-discovers it;
no pbxproj edit). Explicit `init` mirrors `ContentView`'s convention of
explicit initializers when `@Environment` properties are present (a
memberwise init would otherwise try to synthesize a parameter for
`@Environment(\.dismiss)`).

```swift
import SwiftUI

// MARK: - SettingsView

/// Modal settings screen presented from the gear button. Owns no state —
/// every preference is bound back to `ContentView`'s `@AppStorage` values.
struct SettingsView: View {
    // MARK: Lifecycle

    init(
        appearanceMode: Binding<AppearanceMode>,
        textSize: Binding<TextSize>,
        #if os(iOS)
            allowsLandscape: Binding<Bool>,
        #endif
        showMicrophoneButton: Binding<Bool>
    ) {
        _appearanceMode = appearanceMode
        _textSize = textSize
        #if os(iOS)
            _allowsLandscape = allowsLandscape
        #endif
        _showMicrophoneButton = showMicrophoneButton
    }

    // MARK: Internal

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            Picker("Text Size", selection: $textSize) {
                ForEach(TextSize.allCases, id: \.self) { size in
                    Label(size.title, systemImage: size.systemImage)
                        .tag(size)
                }
            }
            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label("Landscape", systemImage: "rectangle.landscape.rotate")
                }
            #endif
            Toggle("Microphone", isOn: $showMicrophoneButton)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    // MARK: Private

    @Binding private var appearanceMode: AppearanceMode
    @Binding private var textSize: TextSize
    #if os(iOS)
        @Binding private var allowsLandscape: Bool
    #endif
    @Binding private var showMicrophoneButton: Bool
    @Environment(\.dismiss) private var dismiss
}
```

#### 2. Gear button + sheet presentation
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Three edits:

**(a)** Add presentation state next to the other `@State` vars (after
`@State private var creationFeedback: CreationFeedback?`):

```swift
@State private var isShowingSettings = false
```

**(b)** Replace the `.overlay` contents — swap `settingsMenu` for a plain
`Button` (keep `gearshape`, frame, `.contentShape`, `.foregroundStyle(.secondary)`,
`.accessibilityLabel`, and add `.accessibilityAddTraits(.isButton)`):

```swift
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
```

**(c)** Attach the sheet at the root, after the existing
`.modifier(TextSizeModifier(textSize: textSize))` (conditionally passing the
`allowsLandscape` binding on iOS only):

```swift
        .modifier(TextSizeModifier(textSize: textSize))
        .sheet(isPresented: $isShowingSettings) {
            #if os(iOS)
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    allowsLandscape: $allowsLandscape,
                    showMicrophoneButton: $showMicrophoneButton)
            #else
                SettingsView(
                    appearanceMode: $appearanceMode,
                    textSize: $textSize,
                    showMicrophoneButton: $showMicrophoneButton)
            #endif
        }
    }
```

**(d)** Delete the `settingsMenu` computed property in full
(`private var settingsMenu: some View { Menu { … } label: { … } … }`).
Keep `.preferredColorScheme` / `.modifier(TextSizeModifier(...))` on the root.

#### 3. Repurpose the stale settings-menu test
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: modify

The old `settingsMenuContainsMicrophoneToggle` test asserts
`bodyDescription.contains("Microphone")`, which stops being true once the
toggle moves into the sheet (see correction #2 above). Replace it with a
gear-entry-point test:

```swift
    @Test
    func settingsGearButtonIsPresent() {
        let view = ContentView(loadsReminders: false)
        let bodyDescription = String(describing: view.body)

        // The settings entry point (gear button) should survive the
        // Menu → sheet swap. Assert on its accessibility label, not the
        // SF Symbol name: `Image(systemName:)` describes as a boxed
        // `NamedImageProvider`, so "gearshape" never appears in the
        // body description.
        #expect(
            bodyDescription.contains("Settings"),
            "Settings gear button should be present on the main view")
    }
```

Note: `ContentView(loadsReminders: false)` renders `reminderList` (not
`authGatedContent`), so the only `"Settings"` string in the body description is
the gear button's accessibility label — the assertion is unambiguous. The three
remaining mic-gating tests (`micButtonHiddenWhenSpeechDenied`,
`micButtonAbsentWhenToggleOff`, `micButtonWithToggleEnabledDoesNotCrash`)
exercise `bottomBar` and are unaffected.

### Verification

#### Automated
- [x] `make format` normalizes the new/changed files (SwiftFormat + SwiftLint `--fix`)
- [x] `make lint` passes (`swiftformat --lint` + `swiftlint lint --strict`)
- [x] `make build` passes (iOS Debug build-for-testing)
- [x] `make test` passes (unit-only: `./scripts/test.sh --unit-only`)

#### Manual
- [ ] Launch on `iPhone 17` simulator; tap the gear (top-trailing) — a sheet slides up with four rows: Appearance, Text Size, Landscape, Microphone.
- [ ] Toggle each preference, kill and relaunch the app — every choice persists (appearance, text size, landscape, microphone).
- [ ] "Done" (top-trailing toolbar) dismisses the sheet.
- [ ] Swipe-down also dismisses the sheet.
- [ ] *Known gaps (deferred)*: appearance/text-size do not live-update *inside* the sheet yet; the landscape toggle writes the binding but does not re-lock orientation.

---

## Phase 2: Live feedback inside the sheet

Re-applies appearance and text-size effects on `SettingsView` so the sheet
updates immediately (Design Decision 3 — no reliance on sheet environment
inheritance).

### Changes

#### 1. Widen `TextSizeModifier` visibility
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Change the file-bottom declaration from `private struct` to internal so
`SettingsView.swift` can reference it (no other change):

```swift
// before
private struct TextSizeModifier: ViewModifier {
// after
struct TextSizeModifier: ViewModifier {
```

#### 2. Apply effects inside the sheet
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Append to `body`, after `.toolbar { … }`:

```swift
        .preferredColorScheme(appearanceMode.colorScheme)
        .modifier(TextSizeModifier(textSize: textSize))
```

### Verification

#### Automated
- [x] `make lint` passes
- [x] `make build` passes

#### Manual
- [ ] Inside the sheet, change Appearance to Light/Dark — the sheet's own background and controls switch immediately.
- [ ] Change Text Size — the sheet's row labels resize immediately.
- [ ] Return to System for both — the sheet follows the system setting.

---

## Phase 3: Orientation lock + cross-platform gating

Restores the landscape side-effect (moved with its row) and proves macOS
compiles the three-row `Form`.

### Changes

#### 1. Re-attach the orientation side-effect
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace the iOS landscape `Toggle` block with a `.onChange`-bearing version
(identical to the original in the old `Menu`):

```swift
            #if os(iOS)
                Toggle(isOn: $allowsLandscape) {
                    Label("Landscape", systemImage: "rectangle.landscape.rotate")
                }
                .onChange(of: allowsLandscape) { _, newValue in
                    AppDelegate.applyLock(allowsLandscape: newValue)
                }
            #endif
```

No change to `SingleThread/AppDelegate.swift` — it still reads the raw
`"allowsLandscape"` UserDefaults key independently at launch.

### Verification

#### Automated
- [x] `make build` passes (iOS)
- [x] `make mac-build` passes — proves macOS compiles the three-row `Form` with no `allowsLandscape` parameter (run with `CODE_SIGNING_ALLOWED=NO`, matching CI; the raw Makefile target fails locally on missing Mac provisioning profiles)
- [x] `make test` passes — `AppDelegateTests`, `AppearanceModeTests`, `TextSizeTests` remain green
- [x] `make lint` passes

#### Manual
- [ ] Inside the sheet, toggle Landscape off — the app immediately locks to portrait.
- [ ] Toggle it back on — landscape rotation is allowed again.

---

## Phase 4: Test coverage + full pipeline

Adds the settings-view test suite and locks everything with the CI-identical
gate.

### Changes

#### 1. New settings-view tests
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: create

Swift Testing (`@Test`), `@MainActor`, `#if os(iOS)` around the
`allowsLandscape` argument so the same file compiles on the macOS test job:

```swift
@testable import SingleThread
import SwiftUI
import Testing

// MARK: - Settings View Tests

@MainActor
struct SettingsViewTests {
    @Test
    func settingsViewContainsAllPreferenceRows() {
        #if os(iOS)
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                allowsLandscape: .constant(true),
                showMicrophoneButton: .constant(true))
        #else
            let view = SettingsView(
                appearanceMode: .constant(.system),
                textSize: .constant(.system),
                showMicrophoneButton: .constant(true))
        #endif

        let bodyDescription = String(describing: view.body)

        // `Form` content (unlike `.sheet` content) is reflected in the
        // body description, so the row labels below are assertable.
        #expect(bodyDescription.contains("Appearance"))
        #expect(bodyDescription.contains("Text Size"))
        #expect(bodyDescription.contains("Microphone"))
        #expect(bodyDescription.contains("Done"))
        #if os(iOS)
            #expect(bodyDescription.contains("Landscape"))
        #endif
    }
}
```

#### 2. Gear entry-point test — already landed
**File**: `SingleThreadTests/MicrophoneToggleTests.swift`
**Action**: no further change

The gear assertion (`settingsGearButtonIsPresent`, asserting
`bodyDescription.contains("Settings")`) was added in Phase 1 (atomically with
the container swap). No additional edit is needed here in Phase 4.

### Verification

#### Automated
- [x] `./scripts/test.sh` passes end-to-end (format, SwiftFormat/SwiftLint checks, iOS build, watch build, Periphery `--strict`, iOS unit tests, iOS UI tests + accessibility audit, macOS build, macOS unit tests)
- [x] `make ui-test` passes — confirms the audit still exercises only the main screen (no sheet-navigation UI test)

#### Manual
- [ ] Toggle Microphone off in the sheet, dismiss — the `mic.fill` button is gone from the main list; toggle back on — it returns.

---

## Testing Checkpoints

- **After Phase 1**: builds; sheet opens with 4 rows; persistence works; Done + swipe dismiss. *Known*: no in-sheet live feedback, no orientation re-lock.
- **After Phase 2**: appearance/text-size update live inside the sheet; `TextSizeModifier` is internal (shared between two files).
- **After Phase 3**: iOS locks orientation on toggle; macOS builds the 3-row `Form`; `AppDelegate` untouched.
- **After Phase 4**: `./scripts/test.sh` fully green; settings entry point and all four controls asserted by unit tests; `SettingsView` covered cross-platform.