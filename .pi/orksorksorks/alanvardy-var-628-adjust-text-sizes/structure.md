# Structure Outline

## Approach

Widen the smallest→largest text-size spread by remapping two `DynamicTypeSize`
steps in the `TextSize` enum only — `large→.xLarge`, `extraLarge→.xxxLarge` —
keeping all five stored case strings and the picker surface untouched. Delivery
is a two-line config remap plus the unit tests that pin the mapping, verified
end-to-end by build, UI tests, and a preview render. No schema, no API, no new
UI.

---

## Phase 1: Widen the top end (`extraLarge → .xxxLarge`)

Remaps the largest offered size from `.xLarge` (19 pt) to `.xxxLarge` (23 pt).
This is the primary fix for "largest barely above baseline" and is fully valid
in isolation — `large` still maps to `.xLarge` and behaves unchanged.

**Files**: `SingleThread/TextSize.swift`, `SingleThreadTests/TextSizeTests.swift`

**Key changes**
- `TextSize.dynamicTypeSize` switch: `case .extraLarge: .xLarge` → `case .extraLarge: .xxxLarge` (TextSize.swift:23)
- `extraLargeMapsToXLargeDynamicTypeSize()` → `extraLargeMapsToXXXLargeDynamicTypeSize()`; boss `#expect(... == .xxxLarge)` (TextSizeTests.swift:25-29) — name corrected to match the honest mapping
- No type/`allCases`/`title`/`systemImage` change; no `ContentView`/`SettingsView` change

**Verify**
- `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes (all 5 mapping asserts + `allCasesCoverFiveCases` + titles)
- Manual: `SettingsView` "#Preview("Dark + Extra Large")" (`SettingsView.swift:205`) renders extra-large at 23 pt — check the top-end jump vs today

---

## Phase 2: Fill the second step (`large → .xLarge`)

Remaps default `large` from `.large` (17 pt) to `.xLarge` (19 pt), giving a
real gap above `medium`. **Order-dependent**: must land **after Phase 1**,
because it reuses the old `extraLarge` value `.xLarge` — if it landed first,
`large == extraLarge` (both `.xLarge`), temporarily narrowing the spread instead
of widening it. Phase 1 moving `extraLarge` off `.xLarge` is what makes `large→.xLarge` safe.

**Files**
| `SingleThread/TextSize.swift`, `SingleThreadTests/TextSizeTests.swift`

**Key changes**
- `TextSize.dynamicTypeSize` switch: `case .large: .large` → `case .large: .xLarge` (TextSize.swift:18-24)
- `largeMapsToLargeDynamicTypeSize()` → `largeMapsToXLargeDynamicTypeSize()`; `#expect(... == .xLarge)` (TextSizeTests.swift:18-22)

**Verify**
- Same unit-test command as Phase 1 — now `largeMapsToXLargeDynamicTypeSize` and `extraLargeMapsToXXXLargeDynamicTypeSize` both pass
- Manual: `SettingsView` preview "Default" (`textSize: .constant(.system)`) is unaffected; confirm the Dark + Extra Large preview still shows the full 15→23 spread

---

## Phase 3: Full CI + visual confirmation

Closes the loop with the repo's whole test pipeline and a visual check of the
spread. No code changes intended beyond regression cleanup.

**Files**: none (verification only)

**Key changes**: none — all mapping work is complete in Phases 1–2.

**Verify**
- `./scripts/test.sh` (format, lint, build, Periphery dead-code, unit + UI tests incl. accessibility audit) — all green, identical to CI
- `make format` then `make lint` to satisfy SwiftFormat/SwiftLint (auto-imported naming/lint rules)
- Manual: open the Settings ⚙ sheet, select System → Small → Medium → Large → Extra Large and confirm a visibly increasing 15 → 16 → 19 → 23 pt step, matching the design §table (not the old 15 → 16 → 17 → 19)

---

## Testing Checkpoints (resume scratchpad)

- **After latter-phase 1**: extraLarge→`.xxxLarge`; `allCases`/titles stay unchanged; unit test `SingleThreadTests` passes; Dark + Extra Large preview shows larger largest.
- **After Phase 2**: large→`.xLarge`; unit tests pass (both renamed assert non-system steps); spread is 15→23.
- **After Phase 3**: `./scripts/test.sh` full pass; Settings picker shows 5 rows unchanged with a clearly wider smallest↔largest gap; `.system` still applies no override ("System" picker row + ContentView modifier weight).
- **If resuming mid-flight**: the only coupling is Phase 2's dependence on Phase 1 (`.xLarge` collision). Do not run Phase 2 solo.

## Out of scope / not sliceable

This design cannot be sliced further without becoming horizontal: there is **no
database migration, no new type, no new API/handler, and no new UI surface**.
The complete change lives in one enum switch (2 lines) and is validated by enum-level tests whose names track the remapped values. The two case remaps are only separable *(Phase 1 / Phase 2)* — every other layer (modifier, storage, picker, previews, accessibility) is unchanged by design and needs no per-phase slice. If you want the two remaps to ship as one atomic commit instead of two, fold Phases 1–2 into a single "Remap sizes" slice — the coupling noted in Phase 2 is the reason both orderings are valid either way.