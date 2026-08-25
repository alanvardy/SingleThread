# Structure Outline

## Approach

Give every iOS control a scheme-adaptive circular plate with a contrasting
stroke outline so controls are legible against any background photo in both
light and dark modes. Build a shared `ControlPlateModifier` first, then roll
it out to each control group — one vertical slice per control cluster.

---

## Phase 1: Shared plate modifier + mic button

Deliver the scheme-adaptive circular plate on the most prominent control (mic)
and a reusable `ViewModifier` that all later phases consume.

**Files**: `SingleThread/ControlPlateModifier.swift` (new), `SingleThread/ContentView.swift`

**Key changes**:
- `struct ControlPlateModifier: ViewModifier` — new
  - `@Environment(\.colorScheme) private var colorScheme`
  - `var fill: Color?` — `nil` → scheme-adaptive (`black` / `Color(white: 0.92)`)
  - `var glyph: Color?` — `nil` → scheme-adaptive (`white` / `Color(white: 0.15)`)
  - `var stroke: Color?` — `nil` → scheme-adaptive (independent of glyph)
  - `func body(content:) -> some View` — applies `.foregroundStyle`, 56×56 frame, `.background(fill, in: Circle())`, `.overlay { Circle().stroke(stroke, lineWidth: 2) }`, `.shadow(radius: 4)`
- `extension View { func controlPlate(fill:glyph:stroke:) -> some View }` — convenience
- `ContentView.micButton` — replaces `.foregroundStyle(.white)`, `.background(.blue, in: Circle())`, `.shadow(radius: 4)` with `.controlPlate()`

**Verify**:
```bash
xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
```
Build succeeds. Run the app, toggle light/dark mode — mic shows black plate + white glyph (dark) / off-white plate + dark glyph (light) with a visible stroke outline on both.

---

## Phase 2: Gear button

Give the settings gear a circular plate so it stays visible against dark photo
corners. Currently a bare `.secondary` glyph with no background.

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- `ContentView.body` gear `overlay` (:99–106) — replaces `.foregroundStyle(.secondary)`, 44×44 frame with `.controlPlate()`

**Verify**:
```bash
xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
```
Build succeeds. Run the app — gear in top-right corner has the same scheme-adaptive plate + stroke as the mic, visible against any photo region.

---

## Phase 3: Complete + Skip action buttons

Give the action-cluster buttons circular plates with unified 56×56 sizing.
Currently flat tinted icons at 44×44 with no fill.

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- `ContentView.completeButton` (:450–462) — replaces `.tint(.green)`, 44×44 frame with `.controlPlate()`
- `ContentView.skipButton` (:464–476) — replaces `.tint(.orange)`, 44×44 frame with `.controlPlate()`

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadUITests/ActionButtonsUITests
```
UI tests pass: `testActionButtonsRenderAndSkipAdvancesCard` confirms buttons exist and tap-advance works; `testActionButtonsAccessibilityAudit` confirms a11y is intact. Manual: enable action buttons in Settings, verify plates adapt to light/dark mode.

---

## Phase 4: Recording indicator + creation feedback

Apply plate treatment to transient-state indicators, with recording keeping
its red "live" fill and creation feedback using success/failure fills — both
with scheme-adaptive stroke outlines.

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- `ContentView.recordingIndicator` (:504–513) — replaces `.foregroundStyle(.white)`, `.background(.red, in: Circle())`, `.shadow(radius: 4)` with `.controlPlate(fill: .red, glyph: .white)`
- `ContentView.creationFeedbackView(for:)` (:515–523) — replaces `.foregroundStyle(.white)`, `.background(feedback.backgroundColor, in: Circle())`, `.shadow(radius: 4)` with `.controlPlate(fill: feedback.backgroundColor, glyph: .white)`

**Verify**:
```bash
xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
```
Build succeeds. Manual verification (dictation requires hardware/permissions):
- Dictate a reminder → recording indicator shows red fill + white glyph + scheme-adaptive stroke
- After save completes → green checkmark plate with outline flashes for 1 second
- Simulate failure → red x-mark plate with outline flashes

---

## Testing Checkpoints

After each phase:
- [ ] `xcodebuild build` passes (no type errors, warnings = errors)
- [ ] `make format && make lint` passes
- [ ] Phase-specific verify step passes

After Phase 3:
- [ ] `ActionButtonsUITests` pass (buttons found, tappable, a11y audit clean)
- [ ] `testAccessibilityAudit` (app-wide audit) still passes

After Phase 4 (final):
- [ ] Full `./scripts/test.sh` passes (format, lint, build, periphery, unit tests, UI tests)
- [ ] Manual smoke-test in light + dark mode against a background photo:
  - Mic, gear, Complete, Skip all have visible plates + strokes
  - Recording indicator has red fill + white glyph + visible stroke
  - Creation feedback has color fill + white glyph + visible stroke