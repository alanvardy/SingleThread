# Structure Outline

## Approach

iOS-only restyle of `RescheduleSheet` (Decision 1): place "Reschedule to" beside a label-less date
picker and center the pair, then restyle the confirm button to `.borderedProminent` and center it —
with **no logic/data-flow change** (helpers, `onReschedule`, `dateComponentsMask`, tomorrow default
all preserved). This is a single-surface `body` restyle — there is **no schema/store/service/transport
decomposition**, so the horizontal-layers idiom maps onto three separable, bottom-up concerns:
**structural layout → control restyle → integration verification.** watchOS is out of scope; macOS is
a silent transitive consumer (shared view) verified in Layer 3.

---

## Layer 1: Structural layout — centered label+picker row

Delivers the new container structure that Layer 2's button will sit on: the labeled `DatePicker` is
replaced with a label-less picker beside a literal `Text`, centered across the sheet. Its green tests
prove the pair renders side-by-side, the picker keeps its a11y identity, and the due-time tailoring
(helpers) survives untouched — the foundation every later layer and the callers rely on.

**Files**: `SingleThread/RescheduleSheet.swift`, `SingleThreadTests/RescheduleSheetTests.swift`

**Key changes**:
- `RescheduleSheet.body: some View` — replace
  `DatePicker("Reschedule to", selection: $date, displayedComponents: displayedComponents)` with:
  ```swift
  HStack {
      Text("Reschedule to")
      DatePicker(selection: $date, displayedComponents: displayedComponents)
          .labelsHidden()
          .accessibilityIdentifier("rescheduleDatePicker")
  }
  .frame(maxWidth: .infinity)   // centers the pair; no Spacer() edge-push
  ```
- Preserved: `@State var date` (tomorrow default), `hasDueTime`, `displayedComponents`,
  `dateComponentsMask` — no `DateComponents` behavior changes.
- Accessibility: picker keeps `accessibilityIdentifier("rescheduleDatePicker")`; the verbal label must
  still associate for VoiceOver — bind the HStack with `.accessibilityElement(children: .combine)` (or
  `.accessibilityLabel("Reschedule to")` on the picker) so the split `Text` doesn't orphan the label.

**Tests** (Swift Testing, `@testable import SingleThread`):
- New `rescheduleSheetPutsLabelBesidePicker` in `RescheduleSheetTests.swift` — `String(describing: RescheduleSheet(…))`
  contains the side-by-side `Text("Reschedule to")` + label-less picker row and no duplicated picker
  label.
- Sad path: construct with `reminder: nil` (date-only fallback) — row still renders and identifier
  present, pinning the no-due-time branch.
- Regression: existing `RescheduleSheetTests.swift` static-helper tests (`dateOnlyReminderPicksDateWithoutTime`,
  `timedReminderPicksDateAndTime`, `nilReminderIsDateOnly`, `reminderWithoutDueDateIsDateOnly`,
  `writeBackMaskFollowsDueTime`) stay green — proves the tailoring helpers were not disturbed.

**Verify**: `make build` (build-for-testing), then
`xcodebuild -scheme SingleThread -destination "$SIM" -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests/RescheduleSheetTests`
— all Layer 1 tests green before advancing.

---

## Layer 2: Confirm-button restyle — `.borderedProminent`, centered

Builds on Layer 1's centered container: the right-edge `Spacer()` button becomes a centered
`.borderedProminent` button, matching the app's primary-button convention. Green tests prove the
prominent style is applied, centering is structural (not `Spacer()`), and the native-chrome invariant
(no `singleThreadButton()`) still holds.

**Files**: `SingleThread/RescheduleSheet.swift`, `SingleThreadTests/RescheduleSheetTests.swift`,
`SingleThreadTests/SingleThreadTests.swift`

**Key changes**:
- `RescheduleSheet.body` — replace `HStack { Spacer(); Button { … } }` (id `rescheduleConfirmButton`)
  with:
  ```swift
  Button { … } label: { Label("Reschedule", systemImage: "calendar.badge.plus") }
      .buttonStyle(.borderedProminent)
      .frame(maxWidth: .infinity)          // horizontally centers, Spacer()-free (codebase idiom)
      .id("rescheduleConfirmButton")
  ```
- Confirm handler body (the `await onReschedule(components)` close-on-`true` logic) is **unchanged**.

**Tests** (Swift Testing):
- New `rescheduleSheetConfirmUsesProminentStyle` in `RescheduleSheetTests.swift` — `String(describing:)`
  contains the `.borderedProminent` structure token (confirm the exact stable token empirically — see
  design Risk on SDK-version brittleness).
- Sad path / invariant: confirm still `!contains("SingleThreadButtonModifier")` across **both** callers
  (construced via nudge sheet and action-menu sheet).
- Update `SingleThreadTests.swift:142–151` `rescheduleSheetTextButtonsKeepNativeChrome` **deliberately**
  (Decision 4): refreshed only to reflect the still-true invariant (`contains("Cancel")`,
  `!contains("SingleThreadButtonModifier")`) — never erased.

**Verify**: same targeted command scoped to both suites —
`-only-testing:SingleThreadTests/RescheduleSheetTests ` **and**
`-only-testing:SingleThreadTests/SingleThreadTests/rescheduleSheetTextButtonsKeepNativeChrome`
— green before advancing.

---

## Layer 3: Integration — macOS passthrough, detents, visual confirmation

No new behavior; proves the shared view's two existing consumers and the unconditional macOS path still
work under the new layout, and that detent heights don't clip. Everything below here is already proven
stable, so this layer is pure verification plus (only if forced) a detent bump.

**Files**: `SingleThread/ContentView.swift` (detent bump **only if** a visible clip forces it — Decision 5);
no other code changes expected.

**Key changes**:
- None by default. Conditional: bump `.height(320)` (action menu, `ContentView.swift:295–297`) or
  `.height(420)` (nudge, `:300–302`) if the centered row/button clips — same commit, noted in plan.

**Tests / checks**:
- macOS native unit suites green: `make mac-test` (or targeted
  `-only-testing:SingleThreadTests/MacOSActionButtonChromeTests` + `…/singleThreadTests` on
  `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`). Known local-only `EntitlementStoreTests` failures are
  pre-existing — annotate, don't debug.
- Residual regression: iOS `RescheduleSyncTests` / `ReminderStoreTests` / `EventKitStoringTests`
  (reschedule persistence & relay) remain green — proves no data-flow change.
- Manual simulator: iPhone nudge sheet **and** action-menu sheet (label+picker centered, prominent
  confirm centered); macOS action-menu sheet renders sanely.

**Verify**: `make build` + macOS targeted tests; then the **full CI-identical gate `./scripts/test.sh`
exactly once via the `run-gate` skill** (managed worktree, multi-hour timeout).

---

## Cross-Cutting Notes

- **Platform-opaque `DatePicker` rendering** (design Risk): the label-less picker's final visual
  position is not assertable from `String(describing:)`; the cheap structural pin lives in Layer 1, and
  the true "side-by-side & centered" look is confirmed on-simulator in Layer 3. Fallback if it collapses
  awkwardly: `.datePickerStyle(.compact)`.
- **A11y label association**: handled early in Layer 1 (never deferred past it) so the split `Text` +
  picker keeps VoiceOver announcing "Reschedule to".
- **No new files/targets**; no pbxproj or `scripts/test.sh` edits (auto-discovered files, suites already
  registered).

## Testing Checkpoints

1. **After Layer 1** — `RescheduleSheetTests` green (helpers + new layout test); iOS build green.
2. **After Layer 2** — `RescheduleSheetTests` + `rescheduleSheetTextButtonsKeepNativeChrome` green; iOS
   build green.
3. **After Layer 3** — macOS targeted suites green; full `./scripts/test.sh` green (run-gate skill).