# Implementation Plan

## Overview

Give every iOS control a scheme-adaptive 56×56 circular plate with a contrasting
2pt stroke outline, so controls are legible against any background photo in both
light and dark modes. Build a reusable `ControlPlateModifier` first, then roll it
out to each control group — one vertical slice per cluster.

---

## Phase 1: Shared plate modifier + mic button

### Changes

#### 1. New `ControlPlateModifier` ViewModifier
**File**: `SingleThread/ControlPlateModifier.swift`
**Action**: create

```swift
import SwiftUI

struct ControlPlateModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var fill: Color? = nil
    var glyph: Color? = nil
    var stroke: Color? = nil

    func body(content: Content) -> some View {
        let resolvedFill = fill ?? (colorScheme == .dark ? .black : Color(white: 0.92))
        let resolvedGlyph = glyph ?? (colorScheme == .dark ? .white : Color(white: 0.15))
        let resolvedStroke = stroke ?? (colorScheme == .dark ? .white : Color(white: 0.15))

        content
            .foregroundStyle(resolvedGlyph)
            .frame(width: 56, height: 56)
            .background(resolvedFill, in: Circle())
            .overlay {
                Circle()
                    .stroke(resolvedStroke, lineWidth: 2)
            }
            .shadow(radius: 4)
    }
}

extension View {
    func controlPlate(
        fill: Color? = nil,
        glyph: Color? = nil,
        stroke: Color? = nil
    ) -> some View {
        modifier(ControlPlateModifier(fill: fill, glyph: glyph, stroke: stroke))
    }
}
```

No Xcode project changes needed — `objectVersion = 77` auto-discovers the new file.

#### 2. Mic button — apply `controlPlate()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace `.foregroundStyle(.white)`, `.frame(...)`, `.background(...)`, `.shadow(...)` with `.controlPlate()`

**Existing** (lines ~489–499):
```swift
    private var micButton: some View {
        Button {
            Task { await startDictation() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.blue, in: Circle())
                .shadow(radius: 4)
        }
        .accessibilityLabel("Dictate reminder")
        .accessibilityAddTraits(.isButton)
    }
```

**Replace with**:
```swift
    private var micButton: some View {
        Button {
            Task { await startDictation() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .controlPlate()
        }
        .accessibilityLabel("Dictate reminder")
        .accessibilityAddTraits(.isButton)
    }
```

### Verification
#### Automated
- [x] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds (no type errors, warnings = errors)

#### Manual
- [ ] Run app on iPhone 17 simulator. In dark mode: mic shows black plate + white glyph + white stroke outline
- [ ] In light mode: mic shows off-white plate + dark glyph + dark stroke outline
- [ ] Plate is clearly visible against photo backgrounds at all fade percentages (try 0%, 50%, 90%)

---

## Phase 2: Gear button

### Changes

#### 1. Gear button overlay — apply `controlPlate()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace `.foregroundStyle(.secondary)` and `.frame(width: 44, height: 44)` with `.controlPlate()`

**Existing** (lines ~96–110):
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

**Replace with**:
```swift
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .controlPlate()
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
```

### Verification
#### Automated
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds

#### Manual
- [ ] Run app. Gear in top-right has the same scheme-adaptive plate + stroke as the mic (black plate/white glyph in dark mode; off-white plate/dark glyph in light mode)
- [ ] Gear is visible against photo corners (top-right area where photos often have dark regions)
- [ ] Tapping gear still opens Settings sheet

---

## Phase 3: Complete + Skip action buttons

### Changes

#### 1. Complete button — apply `controlPlate()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — remove `.frame(width: 44, height: 44)` and `.tint(.green)`; add `.controlPlate()`

**Existing** (lines ~449–462):
```swift
        private var completeButton: some View {
            Button {
                Task { await store.completeCurrentReminder() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .tint(.green)
            .accessibilityLabel("Complete reminder")
            .accessibilityAddTraits(.isButton)
        }
```

**Replace with**:
```swift
        private var completeButton: some View {
            Button {
                Task { await store.completeCurrentReminder() }
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .controlPlate()
                    .contentShape(Circle())
            }
            .accessibilityLabel("Complete reminder")
            .accessibilityAddTraits(.isButton)
        }
```

#### 2. Skip button — apply `controlPlate()`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — remove `.frame(width: 44, height: 44)` and `.tint(.orange)`; add `.controlPlate()`

**Existing** (lines ~464–476):
```swift
        private var skipButton: some View {
            Button {
                store.skipCurrentReminder()
            } label: {
                Label("Skip", systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .tint(.orange)
            .accessibilityLabel("Skip reminder")
            .accessibilityAddTraits(.isButton)
        }
```

**Replace with**:
```swift
        private var skipButton: some View {
            Button {
                store.skipCurrentReminder()
            } label: {
                Label("Skip", systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .controlPlate()
                    .contentShape(Circle())
            }
            .accessibilityLabel("Skip reminder")
            .accessibilityAddTraits(.isButton)
        }
```

### Verification
#### Automated
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds
- [ ] `make format && make lint` passes
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/ActionButtonsUITests` passes — both `testActionButtonsRenderAndSkipAdvancesCard` and `testActionButtonsAccessibilityAudit` pass
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests/SingleThreadUITests/testAccessibilityAudit` passes

#### Manual
- [ ] Enable action buttons in Settings → General
- [ ] In dark mode: Complete and Skip show black plates + white glyphs + white strokes
- [ ] In light mode: off-white plates + dark glyphs + dark strokes
- [ ] Both buttons tappable; Complete advances and marks done; Skip advances

---

## Phase 4: Recording indicator + creation feedback

### Changes

#### 1. Recording indicator — apply `controlPlate(fill: .red, glyph: .white)`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace `.foregroundStyle(.white)`, `.frame(...)`, `.background(.red, ...)`, `.shadow(...)` with `.controlPlate(fill: .red, glyph: .white)`

**Existing** (lines ~504–513):
```swift
    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.red, in: Circle())
            .shadow(radius: 4)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
    }
```

**Replace with**:
```swift
    private var recordingIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .controlPlate(fill: .red, glyph: .white)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityLabel("Recording")
    }
```

#### 2. Creation feedback — apply `controlPlate(fill: feedback.backgroundColor, glyph: .white)`
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace `.foregroundStyle(.white)`, `.frame(...)`, `.background(...)`, `.shadow(...)` with `.controlPlate(fill: ..., glyph: .white)`

**Existing** (lines ~515–523):
```swift
    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(feedback.backgroundColor, in: Circle())
            .shadow(radius: 4)
            .accessibilityLabel(feedback.accessibilityLabel)
    }
```

**Replace with**:
```swift
    private func creationFeedbackView(for feedback: CreationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.title2)
            .controlPlate(fill: feedback.backgroundColor, glyph: .white)
            .accessibilityLabel(feedback.accessibilityLabel)
    }
```

### Verification
#### Automated
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` succeeds
- [ ] `make format && make lint` passes
- [ ] `./scripts/test.sh` fully passes (format, lint, build, periphery, unit tests, UI tests)

#### Manual
- [ ] Dictate a reminder → recording indicator shows red fill + white glyph + scheme-adaptive stroke
- [ ] After save completes → green checkmark plate with outline flashes for 1 second
- [ ] Creation failure → red x-mark plate with outline flashes
- [ ] Full smoke-test in light + dark mode against a background photo:
  - Mic, gear, Complete, Skip all have visible plates + strokes
  - Recording indicator has red fill + white glyph + visible stroke
  - Creation feedback has color fill + white glyph + visible stroke

---

## Implementation Order & Checkpoints

1. **Phase 1** → build check → manual light/dark check
2. **Phase 2** → build check → manual gear check
3. **Phase 3** → build + lint + ActionButtonsUITests + app-wide a11y audit
4. **Phase 4** → build + lint + full `./scripts/test.sh`

Deviations from structure: none. All phases follow the structure outline exactly.