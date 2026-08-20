# Design Discussion

## Current State

- Text-size preference is a `String, CaseIterable` enum with five cases
  `system, small, medium, large, extraLarge` (`SingleThread/TextSize.swift:8-13`).
- Persisted via `@AppStorage("textSize")` on `ContentView` with default
  `.system`; the raw stored string is exactly the case name (`"system"`, …),
  so `.system` round-trips and needs no sentinel (`ContentView.swift:145`).
- The picker lives in `SettingsView` as
  `Picker("Text Size", selection: $textSize)` iterating `TextSize.allCases`
  → `Label(size.title, systemImage:)` / `.tag(size)` (SettingsView.swift:116-119).
- The value is applied through a single `TextSizeModifier`
  (`ContentView.swift:433-441`) which calls `content.dynamicTypeSize(size)`
  only when `dynamicTypeSize` is non-nil; `.system` applies none. The modifier
  runs at the top of `ContentView.body` (:82) and `SettingsView.body` (:168).
- Current mapped point sizes (per the Chromium-Unit-tested body table, at the
  `.body` style): small→`.small`(15), medium→`.medium`(16), large→`.large`(17),
  extraLarge→`.xLarge`(19) (`TextSize.swift:18-24`).

**The problem:** the `.small`→`.xLarge` mapping spans only **15→19 pt**
(∼4 pt, ×1.12 at the top). Small↔medium differ by 1 pt; the largest offered
size is barely above the baseline. The framework exposes larger non-AX steps
the app does not use: `.xxLarge`(21), `.xxxLarge`(23); the accessibility1–5
steps (28–53 pt) only render when the device enables Larger Accessibility Sizes.

## Desired End State

Widen the smallest→largest spread using only non-accessibility steps, keeping
the identity of each stored case.

Chosen mapping (Q1=A, Q2=A, Q3=α — keep 5 cases, end at `.xxxLarge`,
keep names honest):

| Case | DynamicTypeSize | Body pt |
|------|-----------------|---------|
| system   | nil (none)      | device  |
| small    | `.small`        | 15      |
| medium   | `.medium`       | 16      |
| large    | `.xLarge`       | 19      |
| extraLarge | `.xxxLarge`   | 23      |

This doubles the top end (19→23 pt) and widens the total spread from 15–19
(4 pt) to 15–23 (8 pt). `.system`/`.small`/`.medium` are unchanged; only
`large` and `extraLarge` remap. No new cases are added and none are removed,
so the stored `String` identity and the `Picker` surface are untouched.

**Verification:**
- Unit tests updated: `largeMapsToLargeDynamicTypeSize` asserts `.xLarge`
  (was `.large`); `extraLargeMapsToXLargeDynamicTypeSize` asserts `.xxxLarge`
  (was `.xLarge`) — `TextSizeTests.swift:23-29`.
- `allCasesCoverFiveCases` (TextSizeTests.swift:32-33) and the title tests
  (:37-43) stay valid unchanged.
- `SettingsView` "Dark + Extra Large" preview (`SettingsView.swift:205-208`)
  still compiles and now renders extraLarge at `.xxxLarge`.
- Full CI locally via `./scripts/test.sh` (format, lint, build, Periphery,
  unit + UI tests incl. accessibility audit).

## Patterns to Follow

- **`String, CaseIterable` preference idiom** — TextSize, AppearanceMode
  (AppearanceMode.swift), and SortOption all encode choices as raw-string cases
  with auto-synthesized `.allCases` (research §3). Keep the enum shape; only
  remap internal `dynamicTypeSize`.
- **`.system`/first-case = clear-override sentinel** — applied via
  `TextSizeModifier` returning `content` unmodified when `dynamicTypeSize`
  is nil (ContentView.swift:433-437). Do not add a fake size for `.system`.
- **Single centralized modifier** — one `TextSizeModifier` is reused by both
  `ContentView` (:82) and `SettingsView` (:168) so hierarchy scaling stays
  consistent. Retain this; the settings sheet needs its own modifier because
  a `.modifier` only affects its own content.
- **Fixed `.font(.textStyle)` names compose with Dynamic Type** — all app
  text uses named text styles (`.font(.caption/.callout/.title/.title2)`,
  e.g. ContentView.swift:326,336,356 and ReminderCardView.swift:26,35,40),
  not fixed `.system(size:)`. These are dynamic, so the top-level override
  scales them proportionally. Do not hard-code sizes to compensate.
- **Swift Testing (`@Test`, `import Testing`)** for unit coverage
  (TextSizeTests.swift); force-unwraps banned outside tests.

### Patterns NOT to follow
- The framework's **accessibility1–5 cases** should not be used for a plain
  size picker: they only render when the device's "Larger Accessibility Sizes"
  is on, which would silently no-op for most users (research Q2).
- **Do not add a `.default` case** — the framework has no `.default` enum case;
  `.default` is only a static alias for `.large`.

## Design Decisions

1. **Option count — keep 5 cases (Q1=A):** Add/remove no user-facing options;
   only the rendered mapping changes. Preserves stored strings, picker rows,
   `.allCases`, and prevents migration of persisted values.
2. **Upper bound — `.xxxLarge` (Q2=A):** Largest guaranteed-rendered step
   (≈23 pt body / 1.35×). Higher accessibility steps are gated behind a
   device setting and are out of scope. Doubles today's top size (19→23).
3. **Step mapping (Q3=α):** `small→.small`, `medium→.medium`,
   `large→.xLarge`, `extraLarge→.xxxLarge`. Keeps each name truthful to its
   relative position (large > medium, extraLarge > large) while widening the
   extremes. The small↔medium 1-pt gap is accepted; the task targets the
   smallest-vs-largest spread.
4. **`.system` untouched:** Still applies no override; the app follows the
   device. No change to `TextSizeModifier` control flow.
5. **No AX-tier usage:** accessibility sizes excluded (see "Patterns to
   Follow — NOT").

## What We're NOT Doing

- Not removing, renaming, or reordering any `TextSize` case; stored preference
  strings (`"system"…"extraLarge"`) keep decoding.
- Not using accessibility1–5 `.dynamicTypeSize` values.
- Not compensating fixed `.font(...)` styling elsewhere in the hierarchy — the
  existing named text styles already scale under the modifier.
- Not adding a new unit test for `TextSizeModifier`'s render-time
  `dynamicTypeSize()` call (out of scope for this adjustment; low risk since
  control flow is unchanged).
- Not touching the macOS `SettingsView` path beyond confirming it compiles.

## Risks & Open Items

- **Numeric body-point labels drift across iOS builds** (research Q1); the
  15/16/19/23 figures come from Unit-tested Chromium constants, not Apple
  docs. The design depends on ordering, not exact points, so this is low risk.
- `large→.xLarge` reuses the DynamicTypeSize the old `extraLarge` used;
  stored `.extraLarge` values therefore render clearly larger than before,
  which is the intended behavior change (not a bug).
- `.system`→stored-`"system"` round-trip has no dedicated test; not in scope,
  behavior unchanged.

## Next

Run `/4_structure` to turn this design into a step plan.