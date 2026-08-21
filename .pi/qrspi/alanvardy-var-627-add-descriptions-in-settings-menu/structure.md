# Structure Outline

## Approach

Attach the SwiftUI SDK's built-in info affordance — `View.help(_ text: Text)` — to every preference row in `SettingsView` (`SingleThread/SettingsView.swift`). Each row keeps a row-level `.*.help(Text("…"))` with plain-English literal copy describing the behavior it actually implements. No custom popovers, no localization layer, no state/persistence changes. Verification is two-layered: unit tests assert each description via `String(describing: view.body)`, and a UI test taps the affordance to reveal the text.

Because this is purely an iOS/macOS SwiftUI surface change (the repo has no DB/service/API layer — watchOS routes around settings entirely), **vertical slicing cannot cross a backend**. Each phase instead crosses all four relevant axes for that row group: view source, unit-test assertion, SwiftLint accessibility, and preview/render check.

---

## Phase 1: Foundation — mechanism probe on the common toggles

Delivers end-to-end: adds `.help(Text("…"))` to the three platform-agnostic toggle rows (Show Microphone, Show Undated, Show Date) and pins them in the unit test. This first phase is the de-risking spike for the flagged risk that `String(describing: view.body)` may **not** reflect `.help` text.

**Files**: `SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `SomeView.help(_ text: Text) -> some SwiftUICore.View` — SDK-provided; applied per-row as `Toggle(isOn: $showDate) { Label("Show Date", …) }.onChange(…).help(Text("…"))`. No custom type introduced.
- Copy (literals, no keys): "Controls whether the dictation microphone appears in the bottom bar." / "Shows reminders with no due date in the list." / "Shows each reminder's due date on its card."
- Unit test: new `#expect(description.contains("dictation microphone"))` etc. in `settingsViewContainsAllPreferenceNodes`.

**Verify**: `make test` passes (unit test proves `.help` text surfaces in `bodyDescription`); `make lint` passes. **Manual**: run the `SettingsView` `#Preview("Default")`, tap each ″ⓘ″, confirm the description pops up. If the unit `contains` fails for `.help`, record it here and let the UI test in Phase 5 carry the assertion (design-documented fallback).

---

## Phase 2: Picker rows

Adds descriptions to the three enum-driven Picker rows (Appearance, Text Size, Sort By). Same pattern — row-level `.help` — no change to the picker submenus.

**Files**: `SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- Rows become `Picker("Appearance", …).help(Text("…"))`, etc. — API unchanged.
- Copy: "Choose System, Light, or Dark styling for the app." / "Scales the size of your reminder text." / "Chooses the order visible reminders are sorted in."

**Verify**: `make test` unit asserts each new phrase; `make lint` clean. **Manual**: both previews (`Dark + Extra Large`) still render rows with working info affordances.

---

## Phase 3: Submenu NavigationLink row

Adds the description to the Excluded Projects row that pushes `ExcludedProjectsView` (its `footer:` copy already reads like a description and is untouched).

**Files**: `SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `Section { NavigationLink { ExcludedProjectsView(…) } label: { Label("Excluded Projects", …) }.help(Text("Hides the listed projects from the reminder list.")) }`
- Unit assertion for the new phrase.

**Verify**: `make test` + `make lint` pass. **Manual**: open Settings, tap ‹i› beside Excluded Projects; open the submenu to confirm footer copy still present.

---

## Phase 4: iOS-only rows

Adds descriptions to the two rows gated `#if os(iOS)`: Allow Landscape and Enable action buttons. Descriptions only appear on the iOS targets (iPhone/iPad).

**Files**: `SingleThread/SettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- Add `.help(Text("…"))` inside the existing `#if os(iOS)` blocks: `Toggle(…).onChange(…).help(…)`.
- Copy: "Allows rotating the phone into a landscape layout." / "Replaces the microphone with Complete and Skip buttons when a reminder is showing."
- Unit assertions added inside the existing `#if os(iOS)` guard.

**Verify**: `make test` (iOS target) passes with the new `#if os(iOS)` assertions; `make lint` passes. **Manual**: launch iOS simulator, open Settings, confirm both ‹i›s appear; confirm macOS build still lacks them.

---

## Phase 5: End-to-end UI tap feed-through + full CI

Wires the user-facing flow: launch the app, open Settings, tap a row's info affordance, and assert the description text appears. This is the AGENTS.md UI-test regression guard.

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`, `SingleThreadUITests/SingleThreadUITests.swift` (if audit needs a locator)

**Key changes**:
- New `@MainActor` test `testSettingsInfoAffordanceRevealsDescription()`: `app.buttons["Settings"].tap()` → locate the marked info control (query by its `.accessibilityLabel`, per SwiftLint patterns) → `tap()` → `app.staticTexts["…"].waitForExistence`.
- Confirm `testAccessibilityAudit()` still passes (live row exposes enough trait/label), per `research.md` Q5.

**Verify**: `make ui-test` passes; then full `./scripts/test.sh` (format, lint, unit, UI, accessibility) green on the browser sim.

---

## Testing Checkpoints

- **After Phase 1**: `.help` mechanism proven — `SettingsViewTests` asserts literal descriptions; previews show the info affordance revealing text; and the flagged body-reflection risk is either cleared or explicitly reassigned to Phase 5.
- **After Phase 2**: three Picker rows carry descriptions; unit test pins each phrase.
- **After Phase 3**: Excluded Projects row described + pinned; submenu footer unchanged.
- **After Phase 4**: iOS-only rows carry descriptions exactly under `#if os(iOS)`; macOS surface stays unchanged.
- **After Phase 5**: UI tap-through asserts revealed text; `testAccessibilityAudit()` green; full `./scripts/test.sh` passes. Feature complete: every preference row from the Q4 behavior table has an accurate, unit + UI tested description.