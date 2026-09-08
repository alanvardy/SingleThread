# Implementation Plan

## Overview

iOS-only restyle of the shared `RescheduleSheet`: place a literal "Reschedule to"
`Text` beside a label-less date picker in a centered `HStack`, and restyle the
confirm button to `.borderedProminent` with the `Spacer()` edge-push removed so
it centers. No logic, data flow, helpers, or caller presentation changes;
watchOS stays out of scope and macOS is a silent transitive consumer verified
in Layer 3.

---

## Layer 1: Structural layout — centered label+picker row

### Changes

#### 1. Replace the labeled `DatePicker` with a centered `Text` + label-less picker row
**File**: `SingleThread/RescheduleSheet.swift`
**Action**: modify

In `body`, replace the current picker block:

```swift
            DatePicker(
                "Reschedule to",
                selection: $date,
                displayedComponents: Self.displayedComponents(
                    hasDueTime: Self.hasDueTime(reminder)))
                .accessibilityIdentifier("rescheduleDatePicker")
```

with:

```swift
            HStack {
                Text("Reschedule to")
                DatePicker(
                    selection: $date,
                    displayedComponents: Self.displayedComponents(
                        hasDueTime: Self.hasDueTime(reminder)))
                    .labelsHidden()
                    .accessibilityIdentifier("rescheduleDatePicker")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
```

Notes:
- The label-less `DatePicker(selection:displayedComponents:)` overload infers
  `Label == EmptyView`, so "Reschedule to" no longer appears inside the picker
  (no duplicated label). `.labelsHidden()` is kept as a defensive no-op.
- `.frame(maxWidth: .infinity)` centers the pair; no `Spacer()`.
- `.accessibilityElement(children: .combine)` folds the `Text` label and the
  picker into one VoiceOver element ("Reschedule to, <date>") so the split-out
  `Text` doesn't orphan the label. The `accessibilityIdentifier` stays on the
  picker.
- Everything else — doc comment, `@State date` (tomorrow default), `hasDueTime`,
  `displayedComponents`, `dateComponentsMask`, `onReschedule`/`onCancel` — is
  **unchanged** in this phase.

#### 2. Add view-structure tests pinning the new layout
**File**: `SingleThreadTests/RescheduleSheetTests.swift`
**Action**: modify

Add to the existing `@MainActor struct RescheduleSheetTests` (inside the
`// MARK: Tests` section). Names must NOT start with `test` (SwiftFormat would
silently rename them):

```swift
    @Test
    func rescheduleSheetPutsLabelBesidePicker() {
        let sheet = RescheduleSheet(
            reminder: makeReminder(due: DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 30)),
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        // Literal label kept; label-less picker (Label == EmptyView) means no
        // duplicated "Reschedule to" coming from the picker itself.
        #expect(description.contains("Reschedule to"))
        #expect(description.contains("DatePicker<EmptyView"))
        #expect(description.contains("HStack<"))
    }

    @Test
    func dateOnlySheetStillRendersLabeledRow() {
        // Sad path: nil reminder → date-only fallback (no due time) still renders
        // the same centered row, pinning the no-due-time branch.
        let sheet = RescheduleSheet(
            reminder: nil,
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        #expect(description.contains("Reschedule to"))
        #expect(description.contains("DatePicker<EmptyView"))
        #expect(description.contains("AccessibilityAttachmentModifier"))
    }
```

Notes on the assertions:
- `RescheduleSheet` is constructed directly via its memberwise init
  `(reminder:onReschedule:onCancel:nudgeMessage:)`; `@State` is fine on a
  constructed view and `String(describing: sheet.body)` serializes the declared
  view tree the same way sibling suites do (`SwipePromptTests.swift`,
  `SingleThreadButtonModifierTests.swift`).
- `DatePicker<EmptyView` is the label-less token. **Confirm empirically** on the
  first build and adjust if the installed SDK spells the type differently — see
  "Cross-Cutting Notes".
- `AccessibilityAttachmentModifier` (not the identifier string value) is what
  `String(describing:)` actually reflects (see `SwipePromptTests.swift` comment);
  use it as the a11y-identity pin.

### Verification

#### Automated
- [x] `make format` then `make lint` passes (new code + tests) with no warnings-as-errors
- [x] `make build` succeeds (iOS build-for-testing)
- [x] Resolve a pinned destination (name-only `iPhone 17` is ambiguous): `xcrun simctl list devices available | grep -iE 'iphone 17'`, then set `SIM` to the UDID or `platform=iOS Simulator,name=iPhone 17,OS=<os-version>`
- [x] `xcodebuild -scheme SingleThread -destination "$SIM" -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests/RescheduleSheetTests` — all helper tests (existing 5) + the 2 new layout tests green

#### Manual
- [ ] Not needed this layer — visual look is confirmed in Layer 3. (Optional early peek: run the app and open the nudge sheet.)

---

## Layer 2: Confirm-button restyle — `.borderedProminent`, centered

### Changes

#### 1. Replace the `Spacer()`-pushed button with a centered `.borderedProminent` button
**File**: `SingleThread/RescheduleSheet.swift`
**Action**: modify

Replace the current confirm-button block:

```swift
            HStack {
                Spacer()
                Button {
                    let components = Calendar.current.dateComponents(
                        Self.dateComponentsMask(hasDueTime: Self.hasDueTime(reminder)),
                        from: date)
                    Task {
                        if await onReschedule(components) {
                            onCancel()
                        }
                    }
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("rescheduleConfirmButton")
            }
```

with:

```swift
            Button {
                let components = Calendar.current.dateComponents(
                    Self.dateComponentsMask(hasDueTime: Self.hasDueTime(reminder)),
                    from: date)
                Task {
                    if await onReschedule(components) {
                        onCancel()
                    }
                }
            } label: {
                Label("Reschedule", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("rescheduleConfirmButton")
```

Notes:
- The handler closure (`await onReschedule(components)` → close on `true`) is
  byte-for-byte unchanged — only the container and button style change.
- `.frame(maxWidth: .infinity)` gives structural centering (codebase idiom);
  the `Spacer()` edge-push is gone.
- `.borderedProminent` is the app's primary/confirm convention
  (`ReminderCardView.swift:164`, `PurchaseSettingsView.swift:113`) and does NOT
  reference `SingleThreadButtonModifier`.

#### 2. Add the prominent-style structural test
**File**: `SingleThreadTests/RescheduleSheetTests.swift`
**Action**: modify

Add to the same struct:

```swift
    @Test
    func rescheduleSheetConfirmUsesProminentStyle() {
        let sheet = RescheduleSheet(
            reminder: nil,
            onReschedule: { _ in true },
            onCancel: {},
            nudgeMessage: nil)

        let description = String(describing: sheet.body)

        // Stable token proven in SwipePromptTests.swift:52.
        #expect(description.contains("BorderedProminentButtonStyle"))
        // Native-chrome invariant: never routes through the shared modifier,
        // and centering is structural (no Spacer edge-push).
        #expect(!description.contains("SingleThreadButtonModifier"))
        #expect(!description.contains("Spacer"))
    }
```

#### 3. Existing chrome test — expected to pass unchanged (update only if forced)
**File**: `SingleThreadTests/SingleThreadTests.swift` (lines ~142–151)
**Action**: verify first; modify only if the stringification genuinely changed

`rescheduleSheetTextButtonsKeepNativeChrome` asserts
`String(describing: view.actionMenuRescheduleSheet)` contains `"Cancel"` and not
`"SingleThreadButtonModifier"`. Both invariants stay true (Cancel is in the
caller's toolbar, untouched; `.borderedProminent` never adds the modifier), so
this test should pass **unchanged**. If it fails for any SDK-rendering reason,
update it **deliberately** to keep the still-true invariant — never erase or
weaken it (Decision 4).

### Verification

#### Automated
- [ ] `make format` then `make lint` passes
- [ ] `make build` succeeds
- [ ] `xcodebuild -scheme SingleThread -destination "$SIM" -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests/RescheduleSheetTests -only-testing:SingleThreadTests/SingleThreadTests/rescheduleSheetTextButtonsKeepNativeChrome` — all green

#### Manual
- [ ] Not needed this layer — visual look confirmed in Layer 3.

---

## Layer 3: Integration — macOS passthrough, detents, visual confirmation

No new behavior. Proves the two existing iOS callers and the unconditional
macOS path still work under the new layout, and that detent heights don't clip.

### Changes

#### 1. Detent bump — **only if a visible clip forces it** (Decision 5)
**File**: `SingleThread/ContentView.swift` (lines ~295–302)
**Action**: no change by default

Action-menu sheet uses `.presentationDetents([.height(320)])` (~:295–297),
nudge sheet `.height(420)` (~:300–302). Leave both as-is unless the simulator
shows the centered row/button clipping for that flow, in which case bump the
clipping detent in the same commit and note it in the PR. No other code change
is expected in this layer.

### Verification

#### Automated
- [ ] `make mac-test` green (macOS-native `SingleThreadTests`, `CODE_SIGNING_ALLOWED=NO`). Known local-only `EntitlementStoreTests` failures (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) are pre-existing — annotate, don't debug.
- [ ] Targeted macOS chrome run green: `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath DerivedData test-without-building -only-testing:SingleThreadTests/MacOSActionButtonChromeTests` (+ `.../singleThreadTests` if convenient). Or rely on `make mac-test`.
- [ ] iOS regression suites green (proves no data-flow change): `-only-testing:SingleThreadTests/RescheduleSyncTests -only-testing:SingleThreadTests/ReminderStoreTests -only-testing:SingleThreadTests/EventKitStoringTests`
- [ ] **Full CI-identical gate `./scripts/test.sh` exactly once, via the `run-gate` skill** (managed worktree, multi-hour timeout) — the only full-gate run; phases verify with targeted suites only.

#### Manual
- [ ] iPhone simulator — nudge sheet: "Reschedule to" label + picker centered side-by-side, prominent "Reschedule" confirm centered beneath; nudge title/destructive actions still present; no clipping at `.height(420)`.
- [ ] iPhone simulator — action-menu sheet: same centered row + prominent centered confirm; no clipping at `.height(320)`.
- [ ] macOS — action-menu ("Reschedule" in the menu) renders the shared sheet sanely (centered row + prominent button).
- [ ] If the picker value collapses awkwardly after centering, apply the fallback `.datePickerStyle(.compact)` on the picker and re-verify (see Cross-Cutting Notes).

---

## Cross-Cutting Notes

- **`DatePicker<EmptyView` token is the one empirical risk** (design Risk +
  SDK-version brittleness). On the first Layer 1 build, print/confirm
  `String(describing:)` when the test runs; if the installed SDK spells the
  label-less picker differently, adjust that one assertion token — never the
  layout intent.
- **A11y label association** is handled in Layer 1 (`.accessibilityElement(children: .combine)`),
  never deferred.
- **No new files/targets**; no pbxproj or `scripts/test.sh` edits (files are
  auto-discovered; suites already registered).
- **No behavior changes**: `onReschedule`, `dateComponentsMask`,
  `displayedComponents`, `hasDueTime`, tomorrow default, skip-count reset, and
  nudge-identifier clearing are all untouched.
- Commands below use `SIM`; resolve it once per session (name-only is
  ambiguous): `xcrun simctl list devices available | grep -iE 'iphone 17'`, then
  use the UDID or pin `,OS=<os-version>`.

## Deviations from structure outline

- Structure's Layer 2 snippet showed `.id("rescheduleConfirmButton")`; the actual
  current code (and every sibling test) uses `.accessibilityIdentifier("rescheduleConfirmButton")`,
  so the plan preserves `.accessibilityIdentifier` — no behavior difference.
- Structure listed the "across both callers" invariant as a separate native-chrome
  assertion; the plan covers it via the direct-`RescheduleSheet` test
  (`!contains("SingleThreadButtonModifier")`) plus the existing
  `actionMenuRescheduleSheet` test in `SingleThreadTests.swift`, since both
  callers embed the identical `RescheduleSheet` body (the button styling lives in
  the sheet, not the callers).

## Testing Checkpoints

1. **After Layer 1** — `RescheduleSheetTests` green (5 helpers + 2 new layout tests); `make build` green.
2. **After Layer 2** — `RescheduleSheetTests` + `rescheduleSheetTextButtonsKeepNativeChrome` green; `make build` green.
3. **After Layer 3** — macOS targeted suites green; full `./scripts/test.sh` green (run-gate skill).