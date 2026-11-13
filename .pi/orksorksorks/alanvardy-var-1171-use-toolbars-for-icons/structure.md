# Structure Outline

## Approach

Replace the iOS main screen's overlay + inline-HStack chrome with a real system toolbar: a
`NavigationStack` host with one iOS-only `mainToolbar` content builder feeding
`topBarLeading` (undo), `topBarTrailing` (settings) and one `ToolbarItemGroup(.bottomBar)`
(complete / mic / skip) as `Label(title, systemImage:)`, gated by a pure, unit-testable
`ToolbarActionSet`. macOS stays byte-identical (all new code under whole-file/inline
`#if os(iOS)`); the regression net is a11y ids + `testLaunchAndRenderSmoke` + the existing
macOS reflection tests, not new iOS reflection.

> ⚠️ **Design conflict surfaced during structuring — Phase 1 spike must resolve it.**
> Design decision 2 hides the navigation bar (`.toolbar(.hidden, for: .navigationBar)`) "so
> only the bottom group shows", but decision 3 puts gear/undo in `topBarLeading`/`topBarTrailing`.
> Hiding the navigation bar also hides its items, so those two placements cannot both hold.
> The spike below tries three host shapes and records the winner; if none preserves both the
> hidden-background look and the two top items, this returns to `design` (see *Exit criteria*).

## Phase 1: Walking skeleton — a real toolbar item on the real root screen

The app renders one genuine system toolbar item (complete) in a real toolbar host on the iOS main
screen; tapping it still completes a reminder and the a11y id/label survive. Green tests prove the
host shape works before anything else moves into it.

**Spike first (throwaway branch work, no merge):** try in order —
1. `.toolbar { ToolbarItemGroup(placement: .bottomBar) { … } }` on the current nav-free root;
2. `NavigationStack { root }.toolbar(.hidden, for: .navigationBar)` — bottom group only;
3. `NavigationStack { root }` with `.toolbarBackground(.hidden, for: .navigationBar)` +
   `.navigationBarTitleDisplayMode(.inline)` and an empty title — keeps `topBar*` items alive
   (the shape Phase 3 needs) at the cost of a top inset.
Record: do items render, does the background photo still reach the top edge, does the manual
viewport math (`GeometryReader` `:424-427`) double-count insets.
**Exit criteria:** if no shape renders a bottom item *and* keeps a usable top-item slot, stop and
re-run `design` — do not invent a custom bar.

**Files**: `SingleThread/ContentView.swift` (host + iOS toolbar attachment),
`SingleThread/ContentView+Toolbar.swift` (new, whole-file `#if os(iOS)`, holds the item builders).
**Key changes**:
- `ContentView.body` — iOS branch wraps root content in the spike-selected host
- `var completeToolbarItem: some ToolbarContent` — new; `Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")`, id `completeButton`, `.accessibilityLabel(SharedStrings.completeReminderAccessibility)`, `.accessibilityAddTraits(.isButton)`; **no** `.controlPlate()`, **no** `.singleThreadButton()`
- `var mainToolbar: some ToolbarContent` — new `@ToolbarContentBuilder`, starts with the bottom group holding only complete
**Contract**: `mainToolbar` is the single attach point every later slice adds to; toolbar items
carry the a11y ids `completeButton` / `skipButton` / `dictateButton` / `settingsButton` /
`undoButton` and resolve titles via `SharedStrings` (never literals).

**Tests**: no new unit test (nothing logically new yet — it is host wiring);
`SingleThreadUITests/testLaunchAndRenderSmoke` must stay green unmodified (it queries
`completeButton`/`skipButton`/`dictateButton` + `performAccessibilityAudit`), and
`tapSettingsButton` flows (`:207`, `:276`) must still pass with the gear still an overlay.
**Verify**: `scripts/test-one.sh SingleThreadUITests/testLaunchAndRenderSmoke` green; manual
simulator launch confirms the plate visual weight change is acceptable and the photo still hits
the top edge. (Sad path: the spike's failure shape — items not rendering — is the deciding
observation, not a test.)

---

## Phase 2: All three action items in the bottom group, gated by a tested contract

Complete / mic / skip all live in the bottom `ToolbarItemGroup`, and which ones appear is decided
by a pure `ToolbarActionSet` with unit coverage of every entitlement/speech state. The iOS
`actionCluster` HStack is gone.

**Files**: `SingleThread/ContentView+Toolbar.swift`, `SingleThread/ContentView.swift`
(delete `actionCluster` `:571-577`, keep `micButton` for non-toolbar uses, slim `bottomBar` `:748-757`),
`SingleThread/ContentView+ActionMenu.swift` (`skipButton` iOS label body reused as toolbar item),
`SingleThreadTests/ToolbarActionSetTests.swift` (new).
**Key changes**:
- `enum ToolbarAction: Hashable, CaseIterable { case complete, dictate, skip }` — new
- `struct ToolbarActionSet: Equatable { let actions: [ToolbarAction]; let showsUpgradePrompt: Bool }` — new
- `static func make(hasResolvedEntitlement: Bool, canMutate: Bool, showsActionButtons: Bool) -> ToolbarActionSet` — new; encoder of today's `:748-757` three states (no entitlement → `[]`; free tier → `[]` + `showsUpgradePrompt`; entitled → `[.complete,.dictate,.skip]` or `[.dictate]`)
- `var undoToolbarItem` / `var skipToolbarItem` — new, `Label`-based, ids preserved
**Contract**: `ToolbarActionSet.make(...)` is the only entitlement gate on iOS toolbar content;
it hides rather than disables — do not add an `isEnabled` path.

**Tests**: `ToolbarActionSetTests` — `hiddenWithoutResolvedEntitlement`, `freeTierShowsUpgradePromptOnly`,
`entitledShowsAllThreeActions`, `speechDeniedCollapsesToMicOnly` (happy + three sad paths);
existing `MicrophoneToggleTests/micButtonHiddenWhenSpeechDenied` and
`ActionButtonTests` (`showsActionButtons` gate) must stay green unmodified.
**Verify**: `make test` green; `scripts/test-one.sh SingleThreadUITests/testLaunchAndRenderSmoke`
green (all three ids now resolve to toolbar items).

---

## Phase 3: Top chrome moves into the toolbar, overlays deleted

Settings and undo become system top-bar items and the two `.overlay(alignment: .top*)` blocks with
hand-tuned `.padding(.top, 8)` disappear — the last non-system chrome on this screen.

**Files**: `SingleThread/ContentView.swift` (delete gear overlay `:181-197`, iOS undo overlay
`:228-249`), `SingleThread/ContentView+Toolbar.swift` (add both items), `SingleThreadTests/MicrophoneToggleTests.swift`
(verify-only, not edited).
**Key changes**:
- `var settingsToolbarItem: some ToolbarContent` — `Label("Settings", systemImage: "gearshape")`, id `settingsButton`, `.accessibilityAddTraits(.isButton)`; keeps `settingsBag = makeSettingsBag(); isShowingSettings = true` action
- `var undoToolbarItem: some ToolbarContent` — `Label(<undo title>, systemImage: "arrow.uturn.backward")`, id `undoButton`; gated on the same `viewModel.canUndo` condition as the overlay
- macOS `.overlay(.topLeading)` refresh (`:199-225`) untouched
**Contract**: no `controlPlate()` / `.singleThreadButton()` inside any toolbar item; macOS call
sites keep both. Overlay paddings are not ported.

**Tests**: no new unit test (label/presentation wiring); `SingleThreadUITests/testLanguageSelectionChangesVisibleString`
and `testUnsupportedStoredLanguageFallsBackToSystem` (tapped `settingsButton`) green;
`MicrophoneToggleTests/settingsGearButtonIsPresent` (asserts the `"Settings"` a11y label) green
unmodified — it is the proof the label survived the plate removal; `make mac-test` green with
`MacOSActionButtonChromeTests` and the `#if os(macOS)` reflection cases untouched.
**Verify**: `make mac-test` green; the two `settingsButton` UI flows green; `make lint` green.

---

## Phase 4: Hardening — transient states, audits, byte-identical macOS

The dictation/feedback/paywall states sit correctly around a real bar, the a11y audit passes on
both destinations, and everything the change deleted has its coverage accounted for.

**Files**: `SingleThread/ContentView.swift` (`bottomBar` `:727-757` spacing/`upgradePrompt`
`padding(.bottom)` against a system bar), `SingleThreadTests/` (retire only assertions proven to
sign deleted chains), `.pi/orksorksorks/<branch>/` notes.
**Key changes**:
- `bottomBar` — drop the iOS action branch entirely; keep error/feedback/recording/processing and
  `upgradePrompt`, re-padded so it clears the bottom bar
- Retire iOS reflection assertions that signed the removed chains only if they fail *because* of
  this change (`SingleThreadButtonModifierTests`, `CardPlateModifierTests` stay: they sign the
  modifiers, which are untouched); every retirement gets a one-line PR rationale
- Note explicitly in the PR that no Duo proxy run exists (design decision 9) and that this is the
  one knowingly-unverified claim
**Contract**: `controlPlate` / `singleThreadButton` / `actionButtons` bodies and macOS reflection
tests are byte-identical to `origin/main`.

**Tests**: existing suites only — `SingleThreadUITests/testLaunchAndRenderSmoke` +
`performAccessibilityAudit` (local extras `.hitRegion`, `.dynamicType`: a local-only hit-region
failure on the smaller bar items is recorded, not chased), iPad destination run
(`SIM=platform=iOS Simulator,name=iPad (A16)`) for the size-class/resize claim, and
`testActionMenuRescheduleFlow` (`:190`) proving the un-migrated overflow menu still works.
**Verify**: full gate via the `run-gate` skill (`make check`, once), then `make mac-test`;
`make periphery` after clearing `DerivedData/`.

---

## Testing Checkpoints

- After Phase 1: `testLaunchAndRenderSmoke` green + spike outcome recorded → host shape is stable.
- After Phase 2: `make test` green (incl. `ToolbarActionSetTests`) + smoke green → gating is proven.
- After Phase 3: `make mac-test` + both `settingsButton` flows green → macOS is byte-identical.
- After Phase 4: one full `make check` via `run-gate`, then `make mac-test`, then `periphery`.
- Any red checkpoint: stop, do not start the next phase.
