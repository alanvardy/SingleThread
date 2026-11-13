# Implementation Plan

Ticket VAR-1171 — use toolbars for icons. Branch
`alanvardy-var-1171-use-toolbars-for-icons`.

## Overview

The iOS main screen's floating settings gear, iOS undo button, and bottom action cluster
become a real system toolbar: a `NavigationStack` host with one iOS-only `mainToolbar`
content builder feeding `topBarLeading` (undo), `topBarTrailing` (settings), and one
`ToolbarItemGroup(.bottomBar)` (complete / mic / skip) rendered as
`Label(title, systemImage:)`. Entitlement/speech gating is extracted into a pure,
unit-tested `ToolbarActionSet`. macOS stays byte-identical: every new view lives in a
whole-file `#if os(iOS)` file or an inline `#if os(iOS)` gate, and the macOS gear /
refresh overlays keep their exact modifier chains.

## Resolved ambiguities and deviations from `structure.md`

These are settled here so no open question remains; each is called out again at the
phase that owns it.

1. **Host shape (`structure.md` spike) — expected winner is shape C.** Design decision 2
   asks to *hide* the navigation bar, but design decision 3 puts gear/undo in
   `topBarLeading`/`topBarTrailing`; hiding the navigation bar hides those items. The
   spike therefore targets shape C: `NavigationStack { rootContent }` with
   `.toolbarBackground(.hidden, for: .navigationBar)` (bar stays, background transparent)
   plus `.navigationBarTitleDisplayMode(.inline)`. This keeps the two top slots alive
   *and* reads as "no bar background". Shape A (nav-free `toolbar`) and shape B
   (`.toolbar(.hidden, for: .navigationBar)`) are only evaluated for the bottom group; the
   spike also asserts a throwaway `topBarTrailing` item renders, because Phase 3 depends
   on that slot.
2. **`ToolbarActionSet.make` keeps the structure signature
   `(hasResolvedEntitlement:canMutate:showsActionButtons:)`.** Speech-denial and the
   `showMicrophoneButton` toggle are *outer* guards on the same branch today
   (`ContentView.swift:769`), so they stay as outer guards on the toolbar group and the
   `upgradePrompt` branch. The structure's `speechDeniedCollapsesToMicOnly` test name does
   not describe the real behavior (a denied mic currently hides the whole cluster); that
   case is covered by the existing, unmodified `micButtonHiddenWhenSpeechDenied`, and the
   new suite tests the inner branch instead.
3. **The settings gear overlay is only removed on iOS, not deleted.** `ContentView.swift:181-197`
   is *not* platform-gated: macOS uses the same gear overlay and
   `SingleThreadTests.swift:109 contentViewBodyContainsBorderlessSettingsGearOnMacOS`
   signs it. Phase 3 wraps the block in `#if os(macOS)` (macOS compiled output unchanged)
   and adds the iOS toolbar item.
4. **The settings toolbar item needs private `@State`.** `isShowingSettings` and
   `settingsBag` are `private` (`ContentView.swift:372,385`), so the item calls a new
   internal `presentSettings()` helper in `ContentView.swift` instead of poking state from
   `ContentView+Toolbar.swift`.
5. **Bottom-group items are `some View` builders, not `some ToolbarContent`.** A
   `ToolbarItem` cannot nest inside `ToolbarItemGroup`'s content; the group holds plain
   `Button` views (`completeToolbarItem`, `dictateToolbarItem`, `skipButton`), while the
   top items are wrapped in `ToolbarItem`s inside `mainToolbar`. Verified by type-check.
6. **`bottomBar` slimming happens in Phase 2, not Phase 4.** Deleting `actionCluster`
   in Phase 2 would otherwise leave a duplicate `completeButton`/`skipButton`/
   `dictateButton` (toolbar *and* cluster), which breaks `testLaunchAndRenderSmoke`
   (ambiguous identifier match), and the cluster's `completeButton` is gone from Phase 1.
   Phase 4 is therefore mostly verification: the only conditional code change is bottom
   spacing against the new system bar.
7. **No new localization keys.** Visible titles reuse keys already in the catalogs and
   referenced by `Label(LocalizedStringResource(...))`: `SharedStrings.completeAction`
   ("Complete"), "Dictate reminder" (app catalog, `:611`), `SharedStrings.skipAction` /
   `moreAction` ("Skip"/"More"), "Settings" (app catalog, `:2877`), "Undo completion"
   (app catalog, `:3902`). This avoids the 6-language/translation-fixture churn a new key
   would force. A11y labels keep their existing literal values.

---

## Phase 1: Walking skeleton — a real toolbar item on the real root screen

Goal: the app renders one genuine system toolbar item (complete) in a real toolbar host on
the iOS main screen; tapping it still completes a reminder; all a11y ids survive. This
phase also picks the final host shape for Phases 2-3.

### Changes

#### 1. Spike the host shape (throwaway — commit only the winner)

Try, in order, and record for each: do `bottomBar` items render, does a throwaway
`topBarTrailing` item render, does the background photo still reach the top edge, does the
card centering go off (the `GeometryReader` math at `ContentView.swift:424-427`)?

- **Shape A** — attach `.toolbar { mainToolbar }` (bottom group only) directly to the
  existing `ContentView.body` chain, no navigation container. Cheapest diff.
- **Shape B** — `NavigationStack { rootContent }` + `.toolbar(.hidden, for: .navigationBar)`.
  Bottom group only; expected to hide a `topBarTrailing` item.
- **Shape C (expected winner)** — `NavigationStack { rootContent }` +
  `.toolbarBackground(.hidden, for: .navigationBar)` + `.navigationBarTitleDisplayMode(.inline)`.
  Bottom group *and* top slot survive.

**Exit criteria:** if no shape renders a bottom item and keeps a usable top-item slot,
stop and re-run the `design` step — do not invent a custom bar. Shapes A/B that fail the
top-slot check are discarded; only the chosen shape's edits are committed.

#### 2. `SingleThread/ContentView+Toolbar.swift` (create)

Whole-file `#if os(iOS)`, matching `ContentView+iOS.swift`. Phase 1 content:

```swift
#if os(iOS)
import SingleThreadCore
import SwiftUI

// MARK: - Main Toolbar

extension ContentView {
    /// Single attach point for every iOS toolbar item. Later phases add the
    /// top-leading/top-trailing items here rather than attaching more toolbars.
    @ToolbarContentBuilder
    var mainToolbar: some ToolbarContent {
        if viewModel.dictation.canDictate,
           showMicrophoneButton,
           viewModel.store.hasResolvedEntitlement,
           viewModel.store.canMutate,
           viewModel.showsActionButtons {
            ToolbarItemGroup(placement: .bottomBar) {
                completeToolbarItem
            }
        }
    }

    var completeToolbarItem: some View {
        Button {
            Task { await viewModel.completeCurrentReminder() }
        } label: {
            Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
        }
        .accessibilityLabel(SharedStrings.completeReminderAccessibility)
        .accessibilityIdentifier("completeButton")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
```

No `.controlPlate()`, no `.singleThreadButton()`, no `.labelStyle(.iconOnly)` — the system
owns the bezel and the label/symbol representation. The raw-bool guard is temporary; Phase
2 replaces it with `ToolbarActionSet`.

#### 3. `SingleThread/ContentView.swift` (modify) — host + extract `rootContent`

Wrap the iOS root in the chosen host. Rename the existing `body` property (lines
168-369, the full `ZStack` + overlays + animations + `.task`/`.onChange`/sheets chain) to
`private var rootContent: some View`, and add a new `body`:

```swift
var body: some View {
    #if os(iOS)
        NavigationStack {
            rootContent
        }
        .toolbar { mainToolbar }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    #else
        rootContent
    #endif
}
```

The macOS branch returns `rootContent` unchanged, so
`String(describing: view.body)` reflects the same generic chain and the `#if os(macOS)`
reflection tests keep passing.

#### 4. `SingleThread/ContentView.swift` (modify) — trim the iOS cluster

Delete `private var completeButton` (`:558-569`) and drop `completeButton` from
`actionCluster` so the toolbar owns the single `completeButton` identifier while the
smoke test still finds `skipButton`/`dictateButton` in the cluster:

```swift
private var actionCluster: some View {
    HStack(alignment: .center, spacing: 16) {
        micButton
        skipButton
    }
}
```

The settings gear overlay is untouched in this phase (it stays a floating overlay until
Phase 3), so no duplicate `settingsButton` exists yet.

### Verification

#### Automated
- [x] `make build` passes (iOS).
- [x] `scripts/test-one.sh SingleThreadUITests/testLaunchAndRenderSmoke` green — queries
      `completeButton` / `skipButton` / `dictateButton` (exactly one each) and runs
      `performAccessibilityAudit`.
- [x] `scripts/test-one.sh 'SingleThreadTests/MicrophoneToggleTests/settingsGearButtonIsPresent()'`
      green (macOS gear overlay and Settings sheet untouched).
- [x] `make mac-test` green (macOS body chain unchanged).

#### Manual
- [ ] Record the spike outcome in a short note: chosen shape, whether the photo reaches
      the top edge, whether the card stays vertically centered, whether the bottom bar
      reserves space.
- [ ] Launch the simulator and tap the toolbar complete — the visible reminder still
      completes and the undo button (still an overlay this phase) appears.
- [ ] Confirm the plate→bar visual weight change is acceptable; if the a11y audit reports
      a local-only `.hitRegion` failure on the smaller bar item, record it (do not chase).

---

## Phase 2: All three action items in the bottom group, gated by a tested contract

Goal: complete / mic / skip all live in the bottom `ToolbarItemGroup`, and which of them
appear is decided by a pure `ToolbarActionSet` with unit coverage. The iOS
`actionCluster` HStack and the `bottomBar` action-selection branch are gone.

### Changes

#### 1. `SingleThread/ContentView+Toolbar.swift` (modify) — the contract

```swift
// MARK: - ToolbarAction

enum ToolbarAction: Hashable, CaseIterable {
    case complete
    case dictate
    case skip
}

// MARK: - ToolbarActionSet

/// The iOS toolbar's action gating, extracted from `bottomBar`'s former
/// `#if os(iOS)` branch so every entitlement state is unit-testable. It hides
/// items rather than disabling them (do not add an `isEnabled` path).
struct ToolbarActionSet: Equatable {
    let actions: [ToolbarAction]
    let showsUpgradePrompt: Bool

    static func make(
        hasResolvedEntitlement: Bool,
        canMutate: Bool,
        showsActionButtons: Bool
    ) -> ToolbarActionSet {
        guard hasResolvedEntitlement else {
            return ToolbarActionSet(actions: [], showsUpgradePrompt: false)
        }
        guard canMutate else {
            return ToolbarActionSet(actions: [], showsUpgradePrompt: true)
        }
        return ToolbarActionSet(
            actions: showsActionButtons ? ToolbarAction.allCases : [.dictate],
            showsUpgradePrompt: false)
    }
}
```

Then extend the `ContentView` extension: add `toolbarActionSet`, `dictateToolbarItem`, and
replace `mainToolbar`'s temporary guard with the set. The outer guard stays exactly where
today's cluster guard is (`canDictate`, `showMicrophoneButton`):

```swift
@ToolbarContentBuilder
var mainToolbar: some ToolbarContent {
    if viewModel.dictation.canDictate, showMicrophoneButton {
        ToolbarItemGroup(placement: .bottomBar) {
            let actions = toolbarActionSet.actions
            if actions.contains(.complete) { completeToolbarItem }
            if actions.contains(.dictate) { dictateToolbarItem }
            if actions.contains(.skip) { skipButton }
        }
    }
}

var toolbarActionSet: ToolbarActionSet {
    ToolbarActionSet.make(
        hasResolvedEntitlement: viewModel.store.hasResolvedEntitlement,
        canMutate: viewModel.store.canMutate,
        showsActionButtons: viewModel.showsActionButtons)
}

var dictateToolbarItem: some View {
    Button {
        Task { await viewModel.dictation.startDictation() }
    } label: {
        Label(
            LocalizedStringResource("Dictate reminder", table: "Localizable", bundle: .main),
            systemImage: "mic.fill")
    }
    .accessibilityLabel("Dictate reminder")
    .accessibilityIdentifier("dictateButton")
    .accessibilityAddTraits(.isButton)
}
```

#### 2. `SingleThread/ContentView+ActionMenu.swift` (modify) — reuse `skipButton`

`skipButton` (`:71-93`) becomes the toolbar item: drop `.labelStyle(.iconOnly)` and
`.controlPlate()` from its `Label`; keep the action (`showActionMenu ? presentActionMenu() :
viewModel.skipCurrentReminder()`), the dynamic `systemImage`, and all a11y.

```swift
Label(
    SharedStrings.skipAction,
    systemImage: showActionMenu ? SwipeRevealPanel.systemImage(for: .more) : "circle.slash")
```

It is now referenced only by `mainToolbar`; the macOS cluster keeps its own
`macSkipButton`.

#### 3. `SingleThread/ContentView.swift` (modify) — delete cluster, slim `bottomBar`

Delete `actionCluster` (`:571-577`). Keep `micButton` (still used by macOS at `:781`).
Replace the iOS action-selection branch in `bottomBar` (`:769-782`) so the toolbar is the
only renderer of complete/mic/skip and `bottomBar` keeps only the paywall prompt:

```swift
} else if viewModel.dictation.canDictate, showMicrophoneButton {
    #if os(iOS)
        if toolbarActionSet.showsUpgradePrompt {
            upgradePrompt
        }
    #else
        micButton
    #endif
}
```

Behavior parity: free tier (`hasResolvedEntitlement && !canMutate`) still shows
`upgradePrompt`; no entitlement renders nothing; entitled renders nothing here and the
items come from the toolbar.

#### 4. `SingleThreadTests/ToolbarActionSetTests.swift` (create)

Whole-file `#if os(iOS)` (so `make mac-test`, which builds `SingleThreadTests` for macOS,
compiles it to nothing — same idiom as `MacOSActionButtonChromeTests.swift`).

```swift
#if os(iOS)
@testable import SingleThread
import Testing

@MainActor
struct ToolbarActionSetTests {
    @Test
    func hiddenWithoutResolvedEntitlement() { /* actions == []; prompt false */ }
    @Test
    func freeTierShowsUpgradePromptOnly() { /* actions == []; prompt true */ }
    @Test
    func entitledShowsAllThreeActions() { /* == [.complete, .dictate, .skip] */ }
    @Test
    func entitledWithoutActionButtonsShowsMicOnly() { /* == [.dictate] */ }
    @Test
    func freeTierWithoutActionButtonsStillPrompts() { /* == []; prompt true */ }
}
#endif
```

Each asserts `actions` and `showsUpgradePrompt` with `#expect`. Names must not start with
`test` (SwiftFormat strips that prefix).

### Verification

#### Automated
- [x] `make format` then `make lint` green.
- [x] `make test` green, including the new `ToolbarActionSetTests` (5 cases).
- [x] `scripts/test-one.sh SingleThreadUITests/testLaunchAndRenderSmoke` green — all three
      ids now resolve to toolbar items, still exactly one each.
- [x] Existing, unmodified `MicrophoneToggleTests/micButtonHiddenWhenSpeechDenied` and
      `ActionButtonTests` (the `showsActionButtons` gate) green.
- [x] `scripts/test-one.sh 'SingleThreadTests/MicrophoneToggleTests/explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn()'`
      green (`bottomBar`'s unavailable branch untouched).

#### Manual
- [ ] Simulator: entitled → complete/mic/skip in the bottom bar; free tier → only the
      upgrade prompt above the bar; speech denied → no toolbar items, "Speech recognition
      is unavailable." + Open Settings still in `bottomBar`.
- [ ] Note (expected visual change, not a bug to fix here): while dictating, the recording
      indicator shows in `bottomBar` *and* the persistent mic item stays in the bar.

---

## Phase 3: Top chrome moves into the toolbar, overlays deleted

Goal: settings and undo are system top-bar items; the two `.overlay(alignment: .top*)`
blocks with hand-tuned paddings are gone on iOS. macOS is unchanged.

### Changes

#### 1. `SingleThread/ContentView.swift` (modify) — keep macOS gear, drop iOS overlays

Wrap the gear overlay (`:181-197`) in `#if os(macOS)` (macOS compiled output unchanged;
`contentViewBodyContainsBorderlessSettingsGearOnMacOS` still signs it). Delete the iOS
undo overlay block (`:228-249`). Add the internal seam the toolbar item will call
(keeps `settingsBag`/`isShowingSettings` private):

```swift
/// Opens the Settings sheet, creating a fresh bindings bag first. Called by the
/// iOS settings toolbar item; the bag-before-flag ordering is required by
/// `settingsSheetContent`.
func presentSettings() {
    settingsBag = makeSettingsBag()
    isShowingSettings = true
}
```

Do not port the removed overlays' `.padding(.top/.leading/.trailing)` values.

#### 2. `SingleThread/ContentView+Toolbar.swift` (modify) — add both top items

```swift
@ToolbarContentBuilder
var mainToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        settingsToolbarItem
    }
    if viewModel.store.undoStore.hasUndoableReminder,
       showUndoButton,
       viewModel.store.canMutate {
        ToolbarItem(placement: .topBarLeading) {
            undoToolbarItem
        }
    }
    if viewModel.dictation.canDictate, showMicrophoneButton {
        ToolbarItemGroup(placement: .bottomBar) { /* Phase 2 body */ }
    }
}

var settingsToolbarItem: some View {
    Button {
        presentSettings()
    } label: {
        Label(
            LocalizedStringResource("Settings", table: "Localizable", bundle: .main),
            systemImage: "gearshape")
    }
    .accessibilityLabel("Settings")
    .accessibilityIdentifier("settingsButton")
    .accessibilityAddTraits(.isButton)
}

var undoToolbarItem: some View {
    Button {
        Task { await viewModel.undoLastCompletion() }
    } label: {
        Label(
            LocalizedStringResource("Undo completion", table: "Localizable", bundle: .main),
            systemImage: "arrow.uturn.backward")
    }
    .accessibilityLabel("Undo completion")
    .accessibilityIdentifier("undoButton")
    .accessibilityAddTraits(.isButton)
}
```

Contract: no `controlPlate()` / `.singleThreadButton()` inside any toolbar item; those
modifiers keep their macOS call sites and the non-toolbar `recordingIndicator`.

#### 3. `SingleThreadTests/MicrophoneToggleTests.swift`

Verify-only, not edited. `settingsGearButtonIsPresent` stays green: the body description
still contains "Settings" via the retained `SettingsView` sheet, and the toolbar item adds
the same literal.

### Verification

#### Automated
- [x] `make format` then `make lint` green.
- [x] `scripts/test-one.sh SingleThreadUITests/testLanguageSelectionChangesVisibleString`
      green (taps `settingsButton`).
- [x] `scripts/test-one.sh SingleThreadUITests/testUnsupportedStoredLanguageFallsBackToSystem`
      green (taps `settingsButton`).
- [x] `scripts/test-one.sh 'SingleThreadTests/MicrophoneToggleTests/settingsGearButtonIsPresent()'`
      green, unmodified.
- [x] `make mac-test` green — `MacOSActionButtonChromeTests` and the `#if os(macOS)`
      reflection cases untouched.

#### Manual
- [ ] Simulator: gear opens the same Settings sheet; gear shows top-right, undo top-left
      only when an undoable reminder exists.
- [ ] Check the completion-momentum overlay (`.padding(.top, 72)`, comment "clear the
      corner buttons") and the AI-sort banner against the new nav bar; note any overlap as
      a follow-up, do not silently re-tune paddings.

---

## Phase 4: Hardening — transient states, audits, byte-identical macOS

Goal: the dictation/feedback/paywall states sit correctly around a real bar, the a11y
audit passes on both destinations, and everything the change deleted has its coverage
accounted for.

### Changes

#### 1. `SingleThread/ContentView.swift` (contingent only)

No source change is expected. If the manual check shows `upgradePrompt` / transient text
crowding the system bottom bar, reduce `bottomBar`'s `.padding(.bottom, 16)` to
`.padding(.bottom, 8)` (the safe area already reserves the bar). Do not touch macOS.

#### 2. Test-assertion accounting

Grep the test targets for anything signing the deleted chains. Expected result: **no
retirement** — every structural chrome assertion on iOS is already `#if os(macOS)`
(vacuous on iOS), and `SingleThreadButtonModifierTests` / `CardPlateModifierTests` sign
the untouched modifiers. Retire an iOS reflection assertion only if it actually fails
*because* of this change, and give it a one-line PR rationale.

#### 3. Notes

Record in `.pi/orksorksorks/alanvardy-var-1171-use-toolbars-for-icons/` (PR body / notes):
no Duo proxy run exists (design decision 9) — this is the one knowingly-unverified claim;
any local-only `.hitRegion` audit failure on the smaller bar items is local-only.

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadUITests/testLaunchAndRenderSmoke` + its
      `performAccessibilityAudit` green (local extras `.hitRegion`, `.dynamicType`).
- [ ] iPad destination: `SIM='platform=iOS Simulator,name=iPad (A16)' make ui-test` green
      (size-class / resize claim).
- [x] `scripts/test-one.sh SingleThreadUITests/testActionMenuRescheduleFlow` green
      (un-migrated overflow menu still works).
- [x] `make mac-test` green.
- [ ] Full gate ONCE via the `run-gate` skill (`make check`).
- [x] `make periphery` after clearing `DerivedData/` — no new unused code. The only
      remaining finding is the pre-existing `swipeOffset` `$`-projection-only `@State`
      false positive (unchanged from `origin/main`). The branch's new `micButton` finding
      (iOS no longer references it after `actionCluster` was deleted) was cleared by
      compiling `micButton` under `#if os(macOS)`, its only remaining caller. `skipButton`
      is used by the toolbar.

#### Manual
- [ ] iPhone and iPad simulator: complete / skip / mic / gear / undo all reachable and
      correctly labeled; VoiceOver reads each item's label.
- [ ] Rotate (landscape) and re-check bar placement; record the outcome. Duo relocation is
      NOT verified (no Duo hardware/proxy run).

---

## Testing Checkpoints

- After Phase 1: `testLaunchAndRenderSmoke` green + host shape recorded → host is stable.
- After Phase 2: `make test` green (incl. `ToolbarActionSetTests`) + smoke green → gating proven.
- After Phase 3: `make mac-test` + both `settingsButton` UI flows green → macOS byte-identical.
- After Phase 4: one full `make check` via `run-gate`, then `make mac-test`, then `make periphery`.
- Any red checkpoint: stop; do not start the next phase.
