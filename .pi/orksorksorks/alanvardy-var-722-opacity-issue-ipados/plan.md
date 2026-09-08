# Implementation Plan

## Overview

Make the reminder card's container transparent on every device by clearing **all three**
background layers unconditionally (row chrome, scroll content, and the `List` itself),
extracting the row-background decision into a unit-testable computed seam, and verifying
the rendered result visually on the iPad simulator — no `UIDevice`/idiom branching, and no
change to the card plate, `BackgroundPhotoLayer`, or `Color.systemBackground`.

---

## Phase 1: Decision seam (view-model) — bottom-most

Extract the inline row-background ternary into a single computed property on
`ContentViewModel` so the *decision* is unit-testable (the paint itself is
headless-unassertable). Green tests prove the row chrome is always clear across both photo
states — the regression guard for the exact decision this fix changes.

### Changes

#### 1. Row-chrome seam on the view model
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

Add one computed property. `SwiftUI` is already imported (`import SwiftUI`), so `Color` is
available. Place it directly after `backgroundDisplayed` (currently lines 51–54), so the two
related gates sit together:

```swift
    /// Row chrome is always clear so the photo (or `systemBackground` when none is
    /// shown) shows through on every device. Extracted because the rendered paint
    /// can't be asserted headlessly — tests assert this decision instead.
    var rowChromeBackground: Color { .clear }
```

Note: this is the design's recommended **`Color` form** (consumed directly by
`.listRowBackground(_:)`, no dead ternary left in the view). If `Color` equality proves
problematic in the test, fall back to the design's literal alternative
(`var rowChromeIsClear: Bool { true }` mapped to `rowChromeIsClear ? Color.clear : nil` in
the view), but do not land both — pick one and keep the view/tests in sync.

#### 2. Regression-guard unit tests
**File**: `SingleThreadTests/BackgroundCardTests.swift`
**Action**: modify

Add two `@Test` cases and one private helper to `BackgroundCardTests` (inside the existing
`#if os(iOS)` block). The helper mirrors the existing `gate(toggleOn:withPhoto:)` state
setup but returns the built view model instead of the gate value:

```swift
        @Test
        func rowBackgroundClearWithPhotoStored() async throws {
            let viewModel = try await makeViewModel(toggleOn: true, withPhoto: true)
            #expect(viewModel.rowChromeBackground == Color.clear)
        }

        @Test
        func rowBackgroundClearWithoutPhoto() async throws {
            let viewModel = try await makeViewModel(toggleOn: false, withPhoto: false)
            #expect(viewModel.rowChromeBackground == Color.clear)
        }
```

Add the helper alongside the existing `gate` / `seededBackgroundImage` helpers:

```swift
        /// Builds a view model with the given toggle + photo state. The toggle key is
        /// removed via `defer` (reading after cleanup would see the `@AppStorage`
        /// default, not the value under test) — same rule as `gate(toggleOn:withPhoto:)`.
        private func makeViewModel(
            toggleOn: Bool, withPhoto: Bool) async throws -> ContentViewModel {
            let key = "backgroundEnabled"
            UserDefaults.standard.set(toggleOn, forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }

            let backgroundImage: BackgroundImageStore
            if withPhoto {
                backgroundImage = try seededBackgroundImage()
                await backgroundImage.refreshIfNeeded(maxAge: 3600)
                #expect(backgroundImage.imageData != nil, "seeded store should load")
            } else {
                backgroundImage = BackgroundImageStore(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString))
            }
            return makeViewModel(backgroundImage: backgroundImage)
        }
```

The second test is the **sad path** (toggle off + no photo) — the exact state that
previously fell back to the opaque system row default on iPad.

### Verification
#### Automated
- [x] `./scripts/test.sh --unit-only` passes (builds + runs `SingleThreadTests`, including
  the two new `rowBackgroundClear*` tests).
- [x] `swiftformat --lint` + `swiftlint lint --strict` clean for the two touched files
  (or run `make lint`).

#### Manual
- [ ] None — this layer is headless-only; visual correctness lands in Phases 2–3.

**Cross-cutting note (Periphery):** `periphery scan --strict` will flag
`rowChromeBackground` as dead code at this checkpoint because its only reference is in
tests. This is expected. Land Phases 1–2 together in one PR so Periphery is green at merge;
do not commit a Layer-1-only PR as "done."

---

## Phase 2: View paint (presentation) — consumes Layer 1

Replace the conditional row background with the seam, keep the scroll-content hide, and add
the final `.background(Color.clear)` on the `List` so transparency holds regardless of which
layer iPadOS 18 renders as opaque.

### Changes

#### 1. Row background + List background
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Two edits, both in the single-reminder `List` (currently ~lines 307–358):

**Row** (line 308): replace the ternary with the seam:

```swift
// before
                                .listRowBackground(viewModel.backgroundDisplayed ? Color.clear : nil)
// after
                                .listRowBackground(viewModel.rowChromeBackground)
```

**List tail**: keep `.scrollContentBackground(.hidden)`, add `.background(Color.clear)`
**after** it and **before** `.refreshable` (modifier order matters on iPadOS 18):

```swift
                    .listStyle(.plain)
                    // iPadOS gives `List` an opaque scroll-content background by
                    // default, which would hide the photo. Hide it so the photo
                    // (or the system background when none is shown) shows through.
                    .scrollContentBackground(.hidden)
                    // Clear the List's own background too — after the scroll-content
                    // hide, so it wins on iPadOS 18 regardless of which layer is opaque.
                    .background(Color.clear)
                    .refreshable {
                        await viewModel.reload()
                    }
```

No other changes: the card plate (`ReminderCardView.swift:86-95`), `BackgroundPhotoLayer`,
`Color.systemBackground`, `backgroundDisplayed`, `.listStyle(.plain)`,
`.listRowSeparator(.hidden)`, and `.scrollContentBackground(.hidden)` are all unchanged.

### Verification
#### Automated
- [x] `make build` passes (compiles the view change; treat-warnings-as-errors is on).
- [x] `./scripts/test.sh --ui-only` passes — existing appearance/content UI tests still
  green (presence-level; they do not assert opacity).
- [x] `./scripts/test.sh` (full) passes — format + lint + build + **periphery now green**
  (seam is consumed) + unit + UI + watch + macOS.

#### Manual
- [ ] On the iPhone simulator, confirm no visible change (plain-list rows were already
  transparent when no photo is shown).

---

## Phase 3: Visual verification + documentation — top layer

Prove the end-to-end look on both device families in light × dark × toggle-on/off, and
record the manual gate so the fix is reproducible and reviewable.

### Changes

#### 1. Manual verification documentation
**File**: `docs/SimulatorManualVerification.md`
**Action**: modify

Append a new top-level section at the end of the file (after "Scenarios covered"):

```markdown
## Container opacity (VAR-722)

The reminder card's container is now transparent on every device: row chrome is always
clear (`ContentViewModel.rowChromeBackground`), scroll content stays hidden, and the
`List` itself gets `.background(Color.clear)`. Verifying the rendered look is manual-only —
opacity cannot be asserted headlessly (`BackgroundCardTests` assert the gate decision, not
the paint).

**Gate:**

```bash
SIM='platform=iOS Simulator,name=iPad (A16)' make simverify   # iPad (A16)
make simverify                                                # iPhone 17
```

The `make simverify` XCTest asserts are the determinism gate; for the opacity matrix,
capture side-by-side screenshots after booting each device:

```bash
xcrun simctl io "<UDID>" screenshot build/var722-ipad-light-photo-on.png
# repeat for: light/photo-off, dark/photo-on, dark/photo-off
```

**Expectations (both devices, light × dark × toggle-on/off):**

- The card plate (`showsOverPhoto`) appears **only** when a photo is shown — never as an
  opaque row when no photo is displayed.
- No opaque row on iPad in any state (previously the row fell back to the opaque system
  default when no photo was shown).
- Text contrast is unchanged in dark mode over `systemBackground`.

**Screenshot slots** (record filenames next to each expectation): `build/var722-ipad-light-photo-on.png`,
`build/var722-ipad-light-photo-off.png`, `build/var722-ipad-dark-photo-on.png`,
`build/var722-ipad-dark-photo-off.png`, and the iPhone equivalents.
```

### Verification
#### Automated
- [x] `SIM='platform=iOS Simulator,name=iPad (A16)' make simverify` passes (XCTest
  appearance-launch asserts green; screenshot lands at `build/simverify-cold-launch.png`).
- [x] `make simverify` passes on iPhone 17.

#### Manual
- [ ] Capture and record light/dark × toggle-on/off screenshots on both `iPad (A16)` and
  `iPhone 17`; confirm the plate gate (`showsOverPhoto`) and the always-clear row match the
  documented expectations.
- [ ] Confirm on a physical iPad if available (simulator vs. hardware has diverged for
  list backgrounds historically).

---

## Testing Checkpoints

1. **After Phase 1** — `./scripts/test.sh --unit-only` green (seam tests pass); Periphery
   red expected (seam unconsumed).
2. **After Phase 2** — full `./scripts/test.sh` green (format + lint + build + periphery +
   unit + UI).
3. **After Phase 3** — `make simverify` green on iPad (A16) + iPhone; docs updated with the
   light/dark × toggle screenshot matrix.
