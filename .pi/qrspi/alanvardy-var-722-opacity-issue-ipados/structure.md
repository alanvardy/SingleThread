# Structure Outline

## Approach

Make the reminder card's container transparent on every device by clearing **all three**
background layers unconditionally (row chrome, scroll content, and the `List` itself),
extracting the row-background decision into a unit-testable computed seam, and verifying
the rendered result visually on the iPad simulator — no `UIDevice`/idiom branching, and
no change to the card plate, `BackgroundPhotoLayer`, or `Color.systemBackground`.

---

## Layer 1: Decision seam (view-model) — bottom-most

The row-background decision today lives inline in the view as a ternary
(`viewModel.backgroundDisplayed ? Color.clear : nil`). This layer extracts it into a
single computed property so the **decision** is unit-testable (the paint itself is
headless-unassertable). Green tests prove the row chrome is *always* clear across both
photo states — the regression guard for the exact decision this fix changes.

**Files**: `SingleThread/ContentViewModel.swift`, `SingleThreadTests/BackgroundCardTests.swift`

**Key changes**:
- `ContentViewModel` (new computed, `@MainActor`; `Color` already available via `import SwiftUI`):
  ```swift
  /// Row chrome is always clear so the photo (or `systemBackground` when none is
  /// shown) shows through on every device. Extracted because the rendered paint
  /// can't be asserted headlessly — tests assert this decision instead.
  var rowChromeBackground: Color { .clear }
  ```
  - **Alternative** (design's literal form): `var rowChromeIsClear: Bool { true }`, with the
    view mapping `rowChromeIsClear ? Color.clear : nil`.
  - ⭐ Recommend the `Color` form: consumed directly by `.listRowBackground(_:)`, leaving no
    dead ternary in the view and staying a genuine (non-tautological) single source of truth.

**Tests**: `BackgroundCardTests` (iOS-only, Swift Testing) — reuse the existing
`seededBackgroundImage()` / `makeViewModel(backgroundImage:)` helpers:
- `rowBackgroundClearWithPhotoStored` — toggle on + photo → `rowChromeBackground == .clear`.
- `rowBackgroundClearWithoutPhoto` — toggle off / no photo (the **sad path** that previously
  fell back to the opaque system default on iPad) → still `.clear`.

**Verify**: `./scripts/test.sh --unit-only` (or `make test`) green for this stage.
*Note: Periphery stays red here — the seam is referenced only by tests until Layer 2
consumes it (see Cross-cutting note).*

---

## Layer 2: View paint (presentation) — consumes Layer 1

Replace the conditional row background with the seam, keep the scroll-content hide, and add
the final `.background(Color.clear)` on the `List` so the transparency holds regardless of
which layer iPadOS 18 renders as opaque. No visual change on iPhone (plain-list rows are
already transparent when no photo is shown).

**Files**: `SingleThread/ContentView.swift`

**Key changes** (all in the `reminderList` `List`, ~`:307-358`):
- Row (~`:308`): `.listRowBackground(viewModel.backgroundDisplayed ? Color.clear : nil)`
  → `.listRowBackground(viewModel.rowChromeBackground)`.
- Keep `.scrollContentBackground(.hidden)` (~`:358`).
- Add `.background(Color.clear)` on the `List` **after** `.scrollContentBackground(.hidden)`
  and **before** `.refreshable` (modifier order matters on iPadOS 18).

**Tests**: none new — the paint is unassertable via `_ConditionalContent`
(`BackgroundCardTests.swift:38-41`). Correctness is gated by a green build plus the existing
UI suite still passing (presence-level) and the Layer 1 seam test.

**Verify**: `make build`, then `./scripts/test.sh --ui-only` (existing appearance/content UI
tests green), then full `./scripts/test.sh` — Periphery is now green because the seam is
consumed, and lint/format are green.

---

## Layer 3: Visual verification + documentation — top layer

Prove the end-to-end look on **both** device families in **light × dark × toggle-on/off**,
and record the manual gate so the fix is reproducible and reviewable (the headless-unassertable
part the design flags as manual-only).

**Files**: `docs/SimulatorManualVerification.md`

**Key changes**:
- Add a "Container opacity (VAR-722)" section documenting the `make simverify` gate on
  `iPad (A16)` + `iPhone 17`, the light/dark × toggle-on/off matrix, and screenshot slots.
- Record expectations: card plate appears **only** when a photo is shown; no opaque row on
  iPad; text contrast unchanged in dark mode over `systemBackground`.

**Tests**: manual gate (no automated test — opacity is unassertable headlessly).

**Verify**:
```bash
SIM='platform=iOS Simulator,name=iPad (A16)' make simverify
make simverify                                  # iPhone 17
```
Capture side-by-side light/dark × toggle-on/off screenshots on both devices; confirm the
plate gate (`showsOverPhoto`) and the always-clear row. Document in
`docs/SimulatorManualVerification.md`.

---

## Cross-cutting note (Periphery vs. horizontal landing)

The one place this change isn't cleanly horizontal: the seam (Layer 1) is referenced only by
tests until Layer 2 wires the view to it, so `periphery scan --strict` flags it as dead code
at the Layer 1 checkpoint. The seam and its first consumer form a **minimal atomic pair**.
Recommended: develop strictly in order (seam + its test green **first**), but land Layers 1–2
together in one PR so Periphery is green at merge. If a strict per-layer land is required,
tolerate a transient Periphery red at Layer 1 and close it in Layer 2.

## Testing Checkpoints

1. **After Layer 1** — `./scripts/test.sh --unit-only` green (seam tests pass); Periphery red
   expected (seam unconsumed).
2. **After Layer 2** — full `./scripts/test.sh` green (format + lint + build + periphery +
   unit + UI).
3. **After Layer 3** — `make simverify` green on iPad (A16) + iPhone; docs updated with the
   light/dark × toggle screenshot matrix.
