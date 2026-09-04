# Implementation Plan

## Overview

Fix the macOS Settings sheet so that every pushed sub-settings screen (the six
primary sub-views, 2nd-level `ExcludedListsView`, and the `List`-based
`PurchaseSettingsView`) renders its navigation title + back button flush to the
top of the settings card instead of vertically centered, while leaving the iOS
Settings surface byte-for-byte identical. One macOS-gated `ViewModifier`
(`SettingsSubscreenLayout`) fills-and-top-aligns each sub-view's `Form`/`List`;
on iOS the helper compiles to a true no-op returning the receiver unchanged.

## Phase ordering

1. Modifier + its own unit tests (green in isolation on **both** platforms).
2. Apply to the 7 `Form` sub-views + extend view tests.
3. Apply to the `List`-based `PurchaseSettingsView` + first unit coverage.
4. Manual `make mac-run` visual check + single parent-run `./scripts/test.sh`.

> **Completeness note (resolved, not open):** two details in
> `structure.md` were technically infeasible and are corrected below, with
> rationale:
> - The `#if os(macOS)` gate lives in the `View` extension *not* inside
>   `SettingsSubscreenLayout.body`. Reason: `structure.md` Stage-1 iOS test
>   requires the wrapped view to **equal** the unwrapped view (a true no-op),
>   but if iOS compiled `modifier(SettingsSubscreenLayout())` the reflected
>   body would be `ModifiedContent<…, SettingsSubscreenLayout>` ≠ unwrapped.
>   Gating in the extension returns `self` unchanged on iOS. (Verified against
>   the macOS 26.5 SDK: reflection shows `ModifiedContent<Text, ML>` for a
>   modifier wrap, never the modifier's internal body.)
> - The macOS "top-aligned" assertion checks `contains("SettingsSubscreenLayout")`
>   rather than a literal `frame(maxHeight: .infinity, alignment: .top)` string.
>   Reason: SwiftUI does **not** inline a `ViewModifier`'s body into the host
>   view's reflected description (documented in `CardPlateModifierTests.swift`);
>   `.frame` reflects as `SwiftUI._FlexFrameLayout(… maxHeight: Optional(inf)
>   …)` with no literal `frame`, `.infinity`, or `top` text.

---

## Phase 1: `SettingsSubscreenLayout` modifier (foundation)

### Changes

#### 1. New layout modifier
**File**: `SingleThread/SettingsSubscreenLayout.swift`
**Action**: create (auto-discovered — no pbxproj edits; `objectVersion = 77`
synchronized file groups)

```swift
import SwiftUI

/// Frames a pushed Settings sub-view's content to fill the available height
/// and top-align, fixing the macOS sheet's vertical-centering bug. Applied
/// only on macOS: on iOS `settingsSubscreenLayout()` returns the receiver
/// unchanged, so the iOS Settings surface is untouched.
struct SettingsSubscreenLayout: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Fills and top-aligns the receiving view on macOS; a no-op on iOS.
    func settingsSubscreenLayout() -> some View {
        #if os(macOS)
            modifier(SettingsSubscreenLayout())
        #else
            self
        #endif
    }
}
```

- The `#if` resolves at the preprocessor level, so each platform compiles a
  single return expression — no `@ViewBuilder` needed.
- On macOS the extension returns `ModifiedContent<Self, SettingsSubscreenLayout>`
  whose reflected description contains `SettingsSubscreenLayout` (this is what
  the unit tests assert). On iOS it returns `Self` unchanged.

#### 2. Unit tests for the modifier
**File**: `SingleThreadTests/SettingsSubscreenLayoutTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

// MARK: - Settings Subscreen Layout Tests

@MainActor
struct SettingsSubscreenLayoutTests {
    /// SwiftUI does not inline a `ViewModifier`'s body into the host view's
    /// reflected description (see `CardPlateModifierTests`), so reflection can
    /// only pin that the modifier is present — which, on macOS, *is* the
    /// fill-and-top-align behavior.
    #if os(macOS)
        @Test
        func settingsSubscreenLayoutTopAlignedOnMacOS() {
            let view = Text("hi").settingsSubscreenLayout()
            #expect(
                String(describing: view).contains("SettingsSubscreenLayout"),
                "macOS branch should wrap content in the top-anchoring modifier")
        }
    #endif

    /// Negative/sad path: on iOS the helper must be a true no-op — the wrapped
    /// view equals the unwrapped view and carries no `SettingsSubscreenLayout`.
    #if os(iOS)
        @Test
        func settingsSubscreenLayoutIsNoopOnIOS() {
            let content = Text("hi")
            let wrapped = content.settingsSubscreenLayout()
            let wrappedDescription = String(describing: wrapped)
            #expect(wrappedDescription == String(describing: content))
            #expect(!wrappedDescription.contains("SettingsSubscreenLayout"))
        }
    #endif
}
```

### Verification

#### Automated
- [x] `make mac-test` passes (compiles + runs the macOS branch with
      `SWIFT_TREAT_WARNINGS_AS_ERRORS`)
- [x] `make test` passes (compiles + runs the iOS no-op branch)

#### Manual
- [ ] None — Phase 1 is foundation only; visual check comes in Phase 4.

---

## Phase 2: Apply to the 7 `Form` sub-views

### Changes

The edit is identical for every view: insert `.settingsSubscreenLayout()` on a
new line immediately after the view's `.navigationTitle(_:)` (which is the last
statement of `body` for all seven). Representative before/after for
`InterfaceSettingsView`; the other six are the same one-line appends.

#### 1. `InterfaceSettingsView`
**File**: `SingleThread/InterfaceSettingsView.swift`
**Action**: modify

```swift
        }
        .navigationTitle("Interface")
        .settingsSubscreenLayout()
```

#### 2. `ReminderSettingsView`
**File**: `SingleThread/ReminderSettingsView.swift` (`.navigationTitle("Reminder")` at `:59`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 3. `FilterSortSettingsView`
**File**: `SingleThread/FilterSortSettingsView.swift` (`.navigationTitle("Filtering & Sorting")` at `:39`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 4. `BackgroundSettingsView`
**File**: `SingleThread/BackgroundSettingsView.swift` (`.navigationTitle("Background")` at `:68`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 5. `PrivacySettingsView`
**File**: `SingleThread/PrivacySettingsView.swift` (`.navigationTitle("Privacy Policy")` at `:20`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 6. `AboutView`
**File**: `SingleThread/AboutView.swift` (`.navigationTitle("About")` at `:39`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 7. `ExcludedListsView`
**File**: `SingleThread/ExcludedListsView.swift` (`.navigationTitle("Excluded Lists")` at `:30`)
**Action**: modify — append `.settingsSubscreenLayout()` after the title.

#### 8. Extend `SettingsViewTests`
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add a macOS-gated presence assertion to each existing sub-view test, add the
negative root-guard to `settingsViewContainsNavigationLinkLabels`, and add a new
`excludedListsViewContainsTopAnchor` test (first coverage of `ExcludedListsView`).

- In `interfaceSettingsViewContainsExpectedRows`, `reminderSettingsViewContainsExpectedRows`,
  `filterSortSettingsViewContainsExpectedRows`, `backgroundSettingsViewContainsExpectedRows`,
  and `privacySettingsViewContainsExpectedContent`, append after the existing
  label loop:

```swift
        #if os(macOS)
            #expect(
                bodyDescription.contains("SettingsSubscreenLayout"),
                "Sub-view should top-anchor via SettingsSubscreenLayout on macOS")
        #endif
```

- In `settingsViewContainsNavigationLinkLabels`, append after the "Done"
  assertion — guards the root `List` (which must keep its `minHeight: 500`
  floor) stays unmodified:

```swift
        #if os(macOS)
            #expect(
                !bodyDescription.contains("SettingsSubscreenLayout"),
                "Root settings List must not be top-anchored")
        #endif
```

- New test (place after `privacySettingsViewContainsExpectedContent`):

```swift
    @Test
    func excludedListsViewContainsTopAnchor() {
        let view = ExcludedListsView(
            excludedLists: .constant(["Work"]),
            availableLists: ["Work", "Personal"])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Excluded Lists"))
        #expect(bodyDescription.contains("Excluded lists are hidden from the reminder list."))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }
```

#### 9. Extend `AboutViewTests`
**File**: `SingleThreadTests/AboutViewTests.swift`
**Action**: modify — in `aboutViewRendersAttributionAndIdentity`, after the
existing loop, add:

```swift
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
```

(`bodyDescription` already exists in that test.)

### Verification

#### Automated
- [x] `make mac-test` passes — macOS branch: all 7 presence assertions + root
      negative guard green
- [x] `make test` passes — iOS branch: existing row-label assertions still
      green (macOS-gated blocks compiled out)
- [x] `make format` clean (SwiftFormat `organizeDeclarations` does not reorder
      the modifier chains)
- [x] `make lint` clean (SwiftLint `--strict`)

#### Manual
- [ ] `make mac-run` → open Interface, Reminder, Filtering & Sorting → Excluded
      Lists, Background, Privacy, About: each title + back button sits at the
      top of the card (defer full sweep to Phase 4).

---

## Phase 3: Apply to `PurchaseSettingsView` (`List` container)

### Changes

#### 1. `PurchaseSettingsView`
**File**: `SingleThread/PurchaseSettingsView.swift`
**Action**: modify — insert `.settingsSubscreenLayout()` between
`.navigationTitle("Unlock")` (`:55`) and `.task { await loadProduct() }`:

```swift
        .navigationTitle("Unlock")
        .settingsSubscreenLayout()
        .task {
            await loadProduct()
        }
```

(`.task`/`.onChange` are lifecycle modifiers, not layout, so placement relative
to them is irrelevant; keeping the modifier right after the title matches the
other seven views.)

#### 2. First unit coverage of this view
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify — add after `excludedListsViewContainsTopAnchor`:

```swift
    @Test
    func purchaseSettingsViewContainsTopAnchor() {
        let view = PurchaseSettingsView(entitlementStore: EntitlementStore())
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Unlock"))
        #if os(macOS)
            #expect(bodyDescription.contains("SettingsSubscreenLayout"))
        #endif
    }
```

`EntitlementStore()` is constructed with no args in
`settingsViewContainsNavigationLinkLabels` already; describing `body` does not
trigger the `.task` StoreKit load (that runs on appear, not construction).

### Verification

#### Automated
- [ ] `make mac-test` passes — `purchaseSettingsViewContainsTopAnchor` green
- [ ] `make test` passes (macOS-gated block compiled out; list still describes
      "Unlock")

#### Manual
- [ ] `make mac-run` → open Purchase: confirm the submenu is top-anchored like
      the others. If the `List` still centers differently despite the modifier,
      treat as a scoped follow-up (design.md risk 2) — do **not** expand the
      change.

---

## Phase 4: Manual visual check + full gate

No file changes.

### Verification

#### Manual (cannot be CI-automated — no macOS UI target exists)
- [ ] `make mac-run` → open every submenu — Interface, Reminder, Filtering &
      Sorting → Excluded Lists, Background, Privacy, About, Purchase — and
      confirm the navigation title + back button sit flush to the top of the
      card with short-form content top-anchored beneath.
- [ ] Confirm iOS is visually unchanged (optional smoke: `make ui-test` or a
      quick `make build` + run, since the change is iOS no-op).

#### Automated (parent runs ONCE after all phases commit)
- [ ] `./scripts/test.sh` fully green (formats, lints, builds, Periphery, iOS
      unit + UI tests, watch suites, macOS unit tests — identical to CI).

---

## Notes for the PR

- State explicitly that macOS layout is **manually verified** via `make mac-run`
  and is not covered by an automated UI test (no macOS UI target exists;
  adding one is disproportionate — design.md decision 5).
- iOS behavior is gated out (true no-op) and covered by the existing
  `SingleThreadUITestsFlows` + appearance launch tests.
- The modifier is cross-cutting but fully unit-testable at its own layer:
  body-string assertions prove it is applied on macOS, and the only untestable
  residue (real macOS rendering) is the Phase 4 manual check.