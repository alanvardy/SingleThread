# Recon: VAR-1129 "change swipe behaviour" (iOS)

## Task (from `.pi/orksorksorks/alanvardy-var-1129-change-swipe-behaviour/medium.md`)
Change the reminder-card swipe behaviour + its on-screen guide (iOS only):
- **Swipe right → Complete** (unchanged).
- **Swipe left → Skip** (today left swipe reveals the "more" action panel; skip moves here).
- **Swipe up → open the action menu** (the actions currently behind the left-swipe "more" reveal move to the up-swipe).
- **Guide**: replace the swipe-prompt card (currently a plate below the main card) with directional arrows left/right/above the card, each labelled with the action word (e.g. "→ Swipe to Complete", "← Swipe to Skip", "↑ Swipe up for more"). Exact copy/layout is implementer's call within that structure.

Scope: iOS app + shared pure-gesture rule in `SingleThreadCore`. No data/storage/API/entitlement changes. Watch app does not use the card swipe.

## Current behaviour (as built by VAR-1123)
- Right drag past threshold → `.complete`; left drag past threshold → `.more` (opens action menu); vertical-dominant drags ignored (List scroll wins).
- `SwipeGestureOutcome { complete, more, none }`.

## Key files

### 1. `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift` (pure rule)
- `public enum SwipeGestureOutcome: Equatable { case complete, more, none }` (L4-8).
- `public nonisolated enum SwipeGesture` (L12):
  - `public static let releaseDistance: CGFloat = 72` (L15).
  - `outcome(for:threshold:)` (L19-32): `guard abs(h) <= abs(w) else { return .none }`; `w >= threshold → .complete`; `w <= -threshold → .more`; else `.none`.
  - `revealedOutcome(forOffset:)` (L34-42): `>0 → .complete`, `<0 → .more`, `0 → .none`.
- **Change needed**: add an up case (e.g. `.skip` for left, `.more`/menu for up). Note the vertical-dominance guard currently returns `.none` for vertical drags — the up-swipe must be distinguished from List scroll (see medium.md note: resolve with existing `SwipeGesture` pattern, not a new gesture stack).

### 2. `SingleThread/SwipeToActModifier.swift`
- `SwipeRevealPanel` (L11-83): reveal badge; `alignment(for:)` (L34-38) `.more → .trailing` else `.leading`; `systemImage(for:)` (L41-48) `.complete → "checkmark.circle.fill"`, `.more → "ellipsis.circle.fill"`, `.none → "circle"`; `presentation` (L66-82) uses `SharedStrings.completeAction` / `SharedStrings.moreAction` and `CardPlate.completeHintColor` / `CardPlate.skipHintColor`.
- `SwipeToActModifier` (L88-151): `DragGesture(minimumDistance: 10)` `.onChanged { dragOffset = value.translation.width }` (only tracks **width**), `.onEnded` calls `SwipeGesture.outcome(for: value.translation, threshold:)` then `onOutcome`. Accessibility actions: `.complete` and `.more` (L133-139). `progress = min(abs(dragOffset)/max(threshold,1), 1)` (L139-142); `revealedOutcome` from `dragOffset` (L145-147).
- `swipeToAct(threshold:onOutcome:)` extension (L153-157).
- **Change needed**: track vertical translation too; add up-swipe reveal + firing; update a11y actions.

### 3. `SingleThread/ContentView.swift`
- `@AppStorage("showSwipePrompt") var showSwipePrompt = true` (iOS only, L104-105).
- `swipePromptBinding` (L382-387): iOS → `$showSwipePrompt`, else constant false.
- Card usage (L455-463): `.swipeToAct { outcome in switch outcome { case .complete: Task { await viewModel.completeCurrentReminder() }; case .more: presentActionMenu(); case .none: break } }`.
- `isShowingActionMenu` / `actionMenuReminder` state (L127-133).
- **Change needed**: `.more` case → `.skip` (call `viewModel.skipCurrentReminder()`), and add up-swipe → `presentActionMenu()`.

### 4. `SingleThread/ContentView+ActionMenu.swift`
- `presentActionMenu()` (L28-33): captures `viewModel.store.visibleReminders.first` into `actionMenuReminder`, sets `isShowingActionMenu = true`. Called by iOS bottom-bar button (gated) and by left-swipe `.more` outcome (ungated, iOS+macOS).
- `actionMenuDialogButtons` (L35-52): Skip / Reschedule / Delete.
- `showActionMenu` gate (iOS, L17-24): `ActionMenuGate.showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:)`.
- **Change needed**: up-swipe should call `presentActionMenu()`; left-swipe should skip directly.

### 5. `SingleThread/ReminderCardView.swift`
- `prompt` (L200-243): the swipe guide plate below the card — "Swipe right to complete" (arrow.right) + "Swipe left to skip" (arrow.left), `.accessibilityHidden(true)`, plus a Dismiss button (`swipePromptDismissButton`, writes `showSwipePrompt = false`).
- Rendered in `body` (L47-49): `if showSwipePrompt { prompt }` inside a `VStack(spacing: 20)` under the card plate.
- **Change needed**: replace `prompt` with directional arrows left/right/above the card, each labelled with the action word.

### 6. `SingleThread/CardPlate.swift`
- `plateFill(for:)` (L20-23), `skipHintColor(for:)` (L30-33, orange), `completeHintColor(for:)` (L38-41, green). Reused by the prompt plate and reveal panel.

### 7. `SingleThread/ContentView+Settings.swift` + `SingleThread/InterfaceSettingsView.swift` + `SingleThread/SettingsView.swift`
- `showSwipePrompt` binding write-back (ContentView+Settings L27) and `makeSettingsBag` (L44-46).
- `InterfaceSettingsView` L131-142: `Toggle(isOn: $showSwipePrompt)` "Show swipe prompt", caption "Show a hint when there are swipeable reminders.", a11y id `showSwipePromptToggle`. **Copy may need updating** for the new guide (arrows).

### 8. `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
- `completeAction` (L15), `skipAction` (L30), `moreAction` (L37, "More" — left-swipe reveal label + a11y action + bottom-bar button label). **Change needed**: `moreAction` no longer the left-swipe label; add up-swipe/menu strings.

### 9. `SingleThread/Resources/Localizable.xcstrings`
- Contains the swipe guide/prompt strings (e.g. "Swipe right to complete", "Swipe left to skip", "More", "Skip", "Complete"). **Change needed**: add new guide strings + localizations.

## Tests to extend
- `SingleThreadTests/SwipeGestureDecisionTests.swift` — pure rule: `leftPastThresholdShowsMore` (L13-15), `verticalDominantDragDoesNothing` (L22-24), `exactlyAtThresholdFires` (L33-36), `negativeDragOffsetRevealsMore` (L48-50). **Change**: left → skip, add up case, revisit vertical-dominance.
- `SingleThreadTests/SwipeToActModifierTests.swift` — `morePanelShowsMoreLabel`, `morePanelUsesEllipsisGlyph`, `morePanelAnchorsPlateToTrailingEdge`, `idleModifierWrapsContentWithoutPanel`. **Change**: more → skip/up.
- `SingleThreadTests/SwipePromptTests.swift` — `promptShownWhenEnabled` asserts "Swipe left to skip" + "Swipe right to complete" order + `CardPlateModifier` + "Dismiss"; `promptHiddenWhenDisabled`; `dismissButtonHasAccessibilityLabel`. **Change**: new guide structure.
- `SingleThreadUITests/SingleThreadUITests.swift` — `testOverThresholdSwipeCompletesReminder` (L81, right drag 110pt → complete), `testOverThresholdSwipeOpensActionMenu` (L122, left drag -110pt → action menu). **Change**: left drag should now skip; add up-swipe → action menu test.
- Possibly `CardPlateModifierTests`, `SettingsViewTests`, `AppLanguageTests` (asserts swipe strings), `AppViewModelSyncWiringTests`.

## Conventions / build notes (from AGENTS.md)
- Shell is **fish** (no heredocs/`$( )`; use `bash -c '…'` or `/tmp/x.sh` for loops).
- `make build` / `make test` / `make ui-test`; pin destination with `SIM=`. Default sim `iPhone 17`; `.simulator_id` in worktree.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch targets (async defaults to MainActor; no redundant `Task { @MainActor in }`). `SingleThreadCore` package does NOT enable it — annotate `@MainActor` explicitly.
- Swift 6 mode; `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide.
- `--seed` write-flow seam + `--ui-testing-noop-settle` used by swipe UI tests; `--reset-swipe-preference` in `AppViewModel.swift` (L263-271) resets `showSwipePrompt` for swipe-prompt UI tests.
- UI tests use `app.descendants(matching: .any)["reminderCard"]` as the drag target.

## Residual risks / open questions
- **Up-swipe vs List scroll**: the current rule deliberately yields vertical-dominant drags to the List. An up-swipe on a card inside a scrolling `List` needs a resolution (e.g. threshold/dominance tweak in `SwipeGesture`, or a distinct gesture) — flagged in medium.md.
- **macOS**: left-swipe `.more` currently opens the action menu on macOS too (ungated). Task is iOS-only; confirm whether macOS left-swipe should now skip or keep opening the menu.
- **`moreAction` string** is also the bottom-bar action-button a11y label — renaming the left-swipe label must not break the bottom-bar button.
- **Guide copy/localization**: new directional-arrow strings need `Localizable.xcstrings` entries + translations; `AppLanguageTests` may assert existing swipe strings.
