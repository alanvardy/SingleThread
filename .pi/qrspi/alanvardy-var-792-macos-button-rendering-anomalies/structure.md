# Structure Outline

## Approach

Suppress macOS's platform-default bezel with `.buttonStyle(.borderless)`, centralized
in one shared `singleThreadButton()` modifier, and bring the macOS bottom-bar cluster
to iOS's adaptive-plate treatment — verified headlessly via reflection "string-snapshot"
unit tests plus a `make mac-build` visual pass (no pixel assertions anywhere, per the
repo's "rendered paint can't be asserted" convention).

---

## Stage 1: Shared chrome-suppression modifier (foundation)

Delivers the single decision point — a headless-testable `ViewModifier` that applies
`.buttonStyle(.borderless)` — so every later stage calls one symbol instead of inlining
the style. Nothing calls it yet; this stage only proves the mechanism works and is
assertable via reflection.

**Files**: `SingleThread/SingleThreadButtonModifier.swift` (new),
`SingleThreadTests/SingleThreadButtonModifierTests.swift` (new)

**Key changes**:
- `struct SingleThreadButtonModifier: ViewModifier { func body(content: Content) -> some View }` — new; body = `content.buttonStyle(.borderless)`
- `extension View { func singleThreadButton() -> some View }` — new entry point returning `modifier(SingleThreadButtonModifier())` (mirrors `View.controlPlate`, `ControlPlateModifier.swift:51-55`)
- No `#if os` inside — `.borderless` is harmless on iOS (icon-only labels are already effectively chrome-less there) and is what the shared mic button needs anyway

**Tests** (`SingleThreadButtonModifierTests`, Swift Testing, names must NOT start with `test`):
- happy: `String(describing:)` of a view composed with `.singleThreadButton()` contains `"BorderlessButtonStyle"` (analogous to `SwipePromptTests.swift:51`'s `"BorderedProminentButtonStyle"`)
- sad: assert the composed chain still contains `SingleThreadButtonModifier`, so the extension can't be silently dropped during later refactors

**Verify**: `make mac-test` (macOS unit binary) and `make test` (iOS unit binary) green for
`-only-testing:SingleThreadTests/SingleThreadButtonModifierTests`; `make lint` clean.

---

## Stage 2: Standalone macOS-facing icon buttons

Applies the proven modifier to the three independent icon-only buttons that are not part
of the bottom-bar cluster: settings gear, macOS refresh, and the (shared) mic. Each keeps
its existing `.controlPlate()`; this stage only removes the default chrome by adding
`.singleThreadButton()`.

**Files**: `ContentView.swift` (settings gear `:195`, macOS refresh `:210-226`, mic `:530-539`),
`SingleThreadTests.swift` (`:73-96`, update the pinned reflected signature)

**Key changes**:
- settings gear `ContentView.swift:195` — label `Image(...).controlPlate()` unchanged; add `.singleThreadButton()` on the `Button`
- macOS refresh `ContentView.swift:210-226` — add `.singleThreadButton()` (keeps `.controlPlate()` `:217`, `.disabled(isRefreshing)` `:219`)
- mic `ContentView.swift:530-539` — add `.singleThreadButton()`; shared across platforms, so iOS sees `.borderless` too (no-op visually)
- `contentViewBodyContainsRefreshButtonOnMacOS` `SingleThreadTests.swift:73-96` — the pinned `ModifiedContent<...>` signature now includes the borderless style and **must be re-derived from the build** (documented fragility in design.md Open Risks); update the assertion in the same commit, never separately

**Tests**: updated `SingleThreadTests.swift` macOS-gated signature assert (happy — plate still present AND borderless added) plus a new macOS-gated assert that the gear/refresh/mic buttons each reflect `"BorderlessButtonStyle"`; sad path — a scoped text button (e.g. `PurchaseSettingsView.swift:89` "Try Again") still reflects its `"BorderedButtonStyle"` (`:89`) so the scope boundary is pinned.

**Verify**: `make mac-test` green; `make test` green (shared mic change must not break iOS); `make lint` / `make format` clean.

---

## Stage 3: macOS bottom-bar cluster parity

Transforms the `#if os(macOS)` cluster (`ContentView+ActionMenu.swift:70-170`) — drop the
green/orange/red `.tint`s, add `.controlPlate()` to each label, and route the `Menu`
through `.menuStyle(.borderlessButton)`. Builds on Stage 1's modifier and the already-tested
`controlPlate`.

**Files**: `ContentView+ActionMenu.swift` (`macCompleteButton` `:96-109`, `macActionMenu` `:111-133`, `macSkipButton` `:135-148`, `macDeleteButton` `:150-164`),
`SingleThreadTests/MacOSActionButtonChromeTests.swift` (new, whole-file `#if os(macOS)`)

**Key changes**:
- `macCompleteButton` / `macSkipButton` / `macDeleteButton` — remove `.tint(.green/.orange/.red)` (`:104,:128`-adjacent, `:158`); add `.controlPlate()` to the label and `.singleThreadButton()` on the `Button` (label stays `.labelStyle(.iconOnly)` + `.font(.title)`)
- `macActionMenu` — a `Menu`, not a `Button`, so no `.buttonStyle`; apply `.menuStyle(.borderlessButton)` + `.controlPlate()` on its label to read as the same circle
- No changes to iOS Skip/Complete (`:30-64`, `ContentView.swift:507`) — those already draw their own plates

**Tests**: `MacOSActionButtonChromeTests` (macOS-gated, reflection): each of the three buttons reflects `"BorderlessButtonStyle"` AND `"ControlPlateModifier"` (happy); `macActionMenu` reflects `"BorderlessButtonMenuStyle"` + plate (happy); sad — assert the cluster no longer reflects the removed color tints (`"style: green"`/`"orange"`/`"red"`), guarding against the tint sneaking back. All follow the `SwipePromptTests.swift:11-23` style; a11y labels on the cluster controls are preserved per `accessibility_label_for_image`.

**Verify**: `make mac-test` green; `make test` green; `make lint --strict` clean (watch for the deprecated `.menuStyle` spelling — use modern `.borderlessButton`).

---

## Stage 4: Visual verification & full gate

Final headless + manual confirmation. The `macActionMenu` geometry-parity open risk
(design.md Open Risks: `.menuStyle(.borderlessButton)` + `.controlPlate()` may not be
pixel-identical to a `Button`) is checked by hand here — macOS UI tests are compiled but
never run in CI, so this is the only place the puff/geometry fidelity is seen.

**Files**: none (verification-only); screenshot artifacts kept, never compared.

**Key changes**: none — if the menu plate doesn't sit flush with the other cluster circles, adjust the menu label padding in Stage 3's file and re-run Stage 3 tests.

**Tests**: no new tests; this stage asserts the *visual* parity the headless tests can't.

**Verify**: `make mac-build`, then launch the macOS app and confirm (a) gear/refresh/mic draw glyph-on-circle with no translucent square, (b) the bottom-bar cluster reads as four matching mono circles in both light and dark appearance, (c) hover/press feedback still fire. Then run the full `./scripts/test.sh` once as the final gate.

---

## Testing Checkpoints

- **After Stage 1**: `SingleThreadButtonModifierTests` green on iOS + macOS; modifier reflected.
- **After Stage 2**: updated `SingleThreadTests.swift:73-96` signature green on macOS; scoped text-button boundary assert green.
- **After Stage 3**: `MacOSActionButtonChromeTests` green; tint-removal sad-path assert green; `make lint` clean.
- **After Stage 4**: `./scripts/test.sh` fully green + manual macOS screenshot pass; no translucent squares in dark or light mode.