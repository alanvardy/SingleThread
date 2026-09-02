# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `103ad5f` | Phase 1: CardPlate — the shared decision constants (foundation) |
| 2     | `4e435ce` | Phase 2: CardPlateModifier + View.cardPlate(...) — the shape/padding machine |
| 3     | `6c30709` | Phase 3: Migrate remaining consumers + retire the old seams (atomic) |
| 4     | `14383e7` | Phase 4: Full gate + visual regression pass |

## Automated Checks

- [x] `CardPlate` constants type created — `cornerRadius: CGFloat = 10`, `promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)`, `plateFill(for:)` (off-white light / black dark), with docs
- [x] Phase 1 forwarders on `ReminderCardView` kept `Self.plateCornerRadius` / `plateFill(for:)` / `promptBoxFill` compiling; `CardPlateTests` (5 tests) green
- [x] `CardPlateModifier` + `View.cardPlate(fill:padding:restoresGeometry:)` created, consuming `CardPlate.cornerRadius` directly
- [x] `ReminderCardView.body` rewired to `.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 12, restoresGeometry: true)` — identical +12/−12 geometry
- [x] `ReminderCardView.prompt` rewired to `.cardPlate(fill: CardPlate.promptBoxFill)` (default padding 12, no restore)
- [x] `EmptyStateCard.body` rewired to `.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)` — note: plan said `ContentView.swift`; `EmptyStateCard` had been moved to its own file in a prior commit, so the edit landed there
- [x] Phase 1 forwarders + `// MARK: Internal` seam retired; zero references to `ReminderCardView.plateCornerRadius` / `.plateFill` / `.promptBoxFill` remain (grep audit)
- [x] `BackgroundCardTests` (3 assertions) and `SwipePromptTests.promptBoxIsDarkGrey` repointed to `CardPlate`
- [x] `swiftformat` + `swiftlint lint --strict` clean at every phase
- [x] Per-phase build + `-only-testing:SingleThreadTests` unit suites green (Phases 1–3)
- [x] `make periphery` — no dead-code findings at every phase
- [x] **Full gate `./scripts/test.sh` green** (`GATE_EXIT=0`, "All CI checks passed"): format → lint --strict → iOS build → watch build → Periphery → iOS unit tests → iOS UI tests → watch unit tests → watch UI tests → macOS build + unit tests (ran as parent after a subagent loop failure; ~13.5 min)
- [x] No new warnings — only pre-existing SDK deprecations (`SKPaymentTransactionState` in StoreKitTest headers) and Periphery's index-store note
- [x] `SwiftFileTests` / a11y `testAccessibilityAudit` / UI tests green in the full gate

### Deviations from plan (all small, none structural)

1. **Destination pin**: plan used `OS=18.7`; this machine only has the iOS 26.5 runtime, so everything ran against `iPhone 17, OS=26.5` (UDID `D7AC0D41-…`). The full gate needs `SIM=` pinned — a bare `name=iPhone 17` hangs with 4 runtimes.
2. **`CardPlateModifierTests.cardPlateRendersRoundedRectangle`** (plan's Phase 2 test) asserted `String(describing:)` contains `"RoundedRectangle"` — unobservable. SwiftUI does not inline a `ViewModifier`'s body into the host view's static type; `.cardPlate(...)` serializes as `ModifiedContent<…, CardPlateModifier>`. Adapted to assert `CardPlateModifier` presence (same for Phase 3's `promptShownWhenEnabled`).
3. **Remaining `// MARK: Internal` header**: the plan's Phase 3 manual item expected no `// MARK: Internal` section in `ReminderCardView.swift`, but SwiftFormat's `organizeDeclarations` re-inserts it before the (internal) `body` property. Removing it is format-non-idempotent; the header stays by formatter requirement.
4. **`EmptyStateCard` file location** (see above).
5. Two `worker` subagent incidents: Phase 2 correctly flagged the `RoundedRectangle` reflection issue (investigated, confirmed); Phase 4's subagent spun in a poll loop without launching the gate and was interrupted — the gate was run by the parent instead.

## Manual Verification Items (from the plan)

- [ ] `CardPlate` enum file compiles and is auto-discovered by Xcode (synchronized file group — no pbxproj edits needed)
- [ ] `CardPlateTests` file compiles and is auto-discovered by Xcode
- [ ] `CardPlateModifier.swift` is auto-discovered by Xcode (synchronized file group)
- [ ] `CardPlateModifierTests.swift` is auto-discovered by Xcode
- [ ] `ContentView.swift` no longer imports `ReminderCardView` styling — `EmptyStateCard` uses `CardPlate.plateFill(for:)` only
- [ ] Confirm `ReminderCardView.swift` has no `// MARK: Internal` section (see deviation 3 — SwiftFormat re-inserts it; this item is formatter-conflicting)
- [ ] Visual check on `iPhone 17` (light mode): card text plate, swipe prompt, and empty states render pixel-identical to `origin/main`
- [ ] Visual check on `iPhone 17` (dark mode): same comparison
- [ ] Visual check on `iPad (A16)` (light + dark): same comparison
- [ ] `List` row metrics unchanged — the `+12/−12` geometry restore on the card body does not shift row heights or spacing
- [ ] Swipe prompt Dismiss button still tappable; accessibility label still reads "Dismiss swipe prompt"