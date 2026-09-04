# Implementation Plan

## Overview

Fix the macOS settings sheet so all rows render (Interface, Reminder, Filtering & Sorting, Background, Unlock/Purchase, Privacy, About, and Done), make platform conditionals explicit (`#elseif os(macOS)` instead of bare `#else`), and correct two stale comments. iOS behavior is unchanged.

---

## Phase 1: Baseline & Diagnostic

Diagnostic-only stage. Establish a green test baseline on both platforms, then build-and-run macOS to observe the actual sheet rendering and decide the exact sizing fix for Phase 4.

### Changes

No code changes. Build and run only.

### Verification

#### Automated
- [x] `make mac-test` green
- [x] `make test` green (iOS unit tests)

#### Manual
- [ ] `make mac-run` — open Settings via gear button:
  - [ ] If sheet shows only the "Done" toolbar button (no rows), root cause = missing sheet sizing → Phase 4 uses `.frame(minWidth: 400, minHeight: 500)`.
  - [ ] If sheet renders all rows already, Phase 4 is unnecessary; stop after Phase 3.
  - [ ] If sheet shows a different failure mode (e.g., empty but visible sheet, crash), record observation and adjust Phase 4 accordingly before continuing.

**Decision recorded**: Baseline green — 386 macOS + 439 iOS unit tests pass. Diagnostic performed by the main agent via GUI automation (Debug build, gear button click, accessibility-hierarchy dump of the presented sheet): the sheet rendered toolbar-only — nav title "Settings" + Done button, with the List (AXScrollArea/AXOutline) at 470×0 (zero height, no rows). Root cause = missing sheet sizing on macOS → **Phase 4 uses `.frame(minWidth: 400, minHeight: 500)`**. Fix validated experimentally: with the frame applied, the sheet grew to 470×565, the List to 470×452, and all 7 expected rows (Interface, Reminder, Filtering & Sorting, Background, Unlock, Privacy, About) + 2 section separators + Done button render; Done dismisses the sheet. Experimental edit reverted; working tree clean.

---

## Phase 2: Platform-Conditional Normalization

Convert three bare `#else` blocks that encode macOS behavior into explicit `#elseif os(macOS)`. Zero behavior change — the `#elseif` body is identical to the old `#else` body. This is purely structural: makes macOS intent grep-able and matches the existing `AppDelegate.swift` pattern.

### Changes

#### 2.1. `settingsSheetWritebacks` — write-back passthrough
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify

Replace the bare `#else` passthrough at lines 29–31. Current:

```swift
        #if os(iOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
                .onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
                .onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
        #else
            let withIOSPreferences = withAppearance
        #endif
```

New:

```swift
        #if os(iOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
                .onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
                .onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
        #elseif os(macOS)
            let withIOSPreferences = withAppearance
        #endif
```

#### 2.2. `makeSettingsBag()` — bag construction
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify

Replace the `#else` at line 71. Current:

```swift
        #else
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #endif
```

New:

```swift
        #elseif os(macOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #endif
```

#### 2.3. `SettingsView` Interface `NavigationLink` — macOS path
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace the `#else` at lines 47–53. Current:

```swift
                        #else
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                viewModel: viewModel)
                        #endif
```

New:

```swift
                        #elseif os(macOS)
                            InterfaceSettingsView(
                                appearanceMode: $bindings.appearanceMode,
                                textSize: $bindings.textSize,
                                showMicrophoneButton: $bindings.showMicrophoneButton,
                                viewModel: viewModel)
                        #endif
```

### Verification

#### Automated
- [x] `make mac-test` green — existing macOS-branch unit tests compile and pass (`SettingsViewTests.settingsViewContainsNavigationLinkLabels`, `interfaceSettingsViewContainsExpectedRows`, `SettingsViewModelTests`, `MicrophoneToggleTests`)
- [x] `make test` green — iOS unit tests unaffected
- [x] `rg '#else\b' SingleThread/SettingsView.swift SingleThread/ContentView+Settings.swift` returns zero matches

#### Manual
- [ ] None required (zero behavior change, proven by identical test pass)

---

## Phase 3: Comment Accuracy

Correct two documentation drifts so the (now-explicit) platform split is described truthfully. No behavior change — only comment text edits.

### Changes

#### 3.1. Fix modifier-chain count comment
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify — only the doc comment on lines 6–7

Current:

```swift
    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 17-modifier chain does not).
```

New:

```swift
    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 13-modifier chain on macOS, 19 on iOS, does not).
```

#### 3.2. Fix iOS-only fields enumeration
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify — only the doc comment on lines 8–10

Current:

```swift
/// `allowsLandscape`, `enableActionButtons`, and `showUndoButton` are iOS-only
/// in ContentView, but the compiler does not support `#if` directives inside a
/// parameter list, so they are declared unconditionally here with their
/// ContentView defaults. On macOS they are harmless: the values are simply
/// never wired or read.
```

New:

```swift
/// `allowsLandscape`, `enableActionButtons`, `showSwipePrompt`, and
/// `showUndoButton` are iOS-only in ContentView, but the compiler does not
/// support `#if` directives inside a parameter list, so they are declared
/// unconditionally here with their ContentView defaults. On macOS they are
/// harmless: the values are simply never wired or read.
```

### Verification

#### Automated
- [ ] `make format` — no reformat churn (comment-only diffs should be formatting-stable)
- [ ] `make lint` green
- [ ] `make mac-test` green — proves the edits touched only comments, no code

#### Manual
- [ ] `git diff` shows comment-only hunks in exactly two files

---

## Phase 4: macOS Sheet Sizing Fix

The one behavior-changing edit. Add explicit size to the settings sheet content on macOS so all 7 rows + Done toolbar button render. The exact modifier is decided by Phase 1's diagnostic; the default (most-likely) fix is `.frame(minWidth: 400, minHeight: 500)`.

### Changes

#### 4.1. Add `#if os(macOS)` frame modifier to settings sheet content
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**If Phase 1 diagnostic confirms toolbar-only rendering** (expected), add a `.frame` modifier to `settingsSheetContent`. Current at lines 547–551:

```swift
    @ViewBuilder private var settingsSheetContent: some View {
        if let bag = settingsBag {
            settingsSheetWritebacks(bag)
        }
    }
```

New:

```swift
    @ViewBuilder private var settingsSheetContent: some View {
        if let bag = settingsBag {
            settingsSheetWritebacks(bag)
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 500)
                #endif
        }
    }
```

**If Phase 1 diagnostic shows a different root cause**, adjust accordingly:
- If `.frame` alone doesn't fix it: try `.presentationDetents([.medium, .large])` instead, also gated `#if os(macOS)`.
- If a deeper issue (e.g., `NavigationStack` + `List` layout bug): extract the sheet content differently per design doc, but this is unexpected.

The `#if os(macOS)` guard ensures zero change on iOS — the modifier is compile-time gated to macOS only.

### Verification

#### Automated
- [ ] `make mac-test` green — all macOS unit tests still pass
- [ ] `make test` green — iOS unit tests unaffected (the `#if os(macOS)` block does not compile on iOS)

#### Manual
- [ ] `make mac-run` → open Settings via gear button:
  - [ ] All rows visible: Interface, Reminder, Filtering & Sorting, Background, Unlock (or Manage Purchase if entitled), Privacy, About
  - [ ] Done toolbar button visible and functional (tapping dismisses the sheet)
  - [ ] Scrolling works if content exceeds sheet height
- [ ] `make ui-test` (iOS) — settings UI tests still pass: `testSettingsOpensAndShowsControls`, `testSettingsHasPurchaseRow`, `testPurchaseSheetHasRestoreButton`, `testBackgroundAndPinTogglesPersistAcrossRelaunch`, `testReminderTogglesPersistAcrossRelaunch`, `testAboutModalShowsAttribution`, `testSwipePromptToggleRoundTripsViaSettings`, `testUndoButtonHiddenWhenToggleOff`

#### Manual (iOS)
- [ ] Build and run on iOS simulator (`make build` then open app) — settings sheet unchanged:
  - [ ] All rows + Notifications present
  - [ ] Sheet presentation style unchanged (detent-based, not forced frame)

---