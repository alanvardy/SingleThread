# Structure Outline

## Approach

A UI-only fix for the macOS settings sheet: make the platform split explicit (`#else` → `#elseif os(macOS)`), correct two stale comments, and — gated on a build-and-run diagnostic — add `#if os(macOS)` sizing so all rows render. Behavior-neutral refactoring lands and is proven green before the one behavior-changing (sizing) edit; a macOS UI-test target is deferred.

---

## Stage 1: Baseline & Diagnostic (verification foundation)

Establishes the preconditions every later stage assumes: a green test baseline on both platforms, and an **observed** (not inferred) root cause for the blank macOS sheet. Ships no code — its deliverable is the decision that fixes Stage 4's exact form.

**Files**: none (build/run only)
**Key changes**: none — run `make mac-run`, open Settings, confirm whether the sheet collapses to toolbar-only (expected root cause) or shows a different failure mode.
**Verify**: `make mac-test` green; `make test` green; manual `make mac-run` observation recorded. If the root cause is not sheet sizing, Stage 4's form changes (see Risk note in design) — Stages 2–3 are unaffected.

---

## Stage 2: Platform-Conditional Normalization

Converts the three bare `#else` blocks that encode macOS behavior into explicit `#elseif os(macOS)`, so macOS intent is grep-able and matches the existing `AppDelegate.swift` pattern. Purely structural — zero behavior change — which is why the existing test suite is the proof.

**Files**: `SingleThread/ContentView+Settings.swift`, `SingleThread/SettingsView.swift`
**Key changes**:
- `ContentView+Settings.swift` — `settingsSheetWritebacks(_ bag: SettingsBindings)`: `#else` passthrough → `#elseif os(macOS)` (same 13-observer tail; iOS keeps 19)
- `ContentView+Settings.swift` — `makeSettingsBag() -> SettingsBindings`: `#else` (13-field init) → `#elseif os(macOS)` (same init)
- `SettingsView.swift` — Interface `NavigationLink`: `#else` (3-binding `InterfaceSettingsView(appearanceMode:textSize:showMicrophoneButton:viewModel:)`) → `#elseif os(macOS)`

**Tests**: existing macOS-branch unit tests — `SettingsViewTests.settingsViewContainsNavigationLinkLabels` / `interfaceSettingsViewContainsExpectedRows`, `SettingsViewModelTests`, `MicrophoneToggleTests` (all compile/run the `#else` path); plus the full iOS unit + UI suites (the `#if os(iOS)` path is untouched).
**Verify**: `make mac-test` and `make test` green; `rg '#else\b' SingleThread/SettingsView.swift SingleThread/ContentView+Settings.swift` returns zero matches.

---

## Stage 3: Comment Accuracy

Corrects two documentation drifts so the (now-explicit) platform split is described truthfully. No behavior change; the gate is lint + proof of no accidental code edit.

**Files**: `SingleThread/ContentView+Settings.swift`, `SingleThread/SettingsBindings.swift`
**Key changes**:
- `ContentView+Settings.swift:6-7` — "17-modifier chain" → "13-modifier chain (19 on iOS)"
- `SettingsBindings.swift:8-10` — enumerate `showSwipePrompt` alongside `allowsLandscape`, `enableActionButtons`, `showUndoButton` as iOS-only fields

**Tests**: no new tests (comments don't affect `String(describing: view.body)`); existing suites must remain green to prove the edits touched only comments.
**Verify**: `make format` (no reformat churn), `make lint`, `make mac-test` green; `git diff` shows comment-only hunks.

---

## Stage 4: macOS Sheet Sizing Fix

The one behavior-changing edit: give the sheet content explicit size on macOS so all 7 rows + Done render. Form is decided by Stage 1's diagnostic; the guard follows Stage 2's explicit `#if os(macOS)` pattern.

**Files**: `SingleThread/ContentView.swift`
**Key changes**:
- `.sheet(isPresented: $isShowingSettings) { settingsSheetContent }` (`:244-246`) / `settingsSheetContent` (`:547-551`) — add a new `#if os(macOS)` modifier block, one of:
  - `.frame(minWidth: 400, minHeight: 500)`, or
  - `.presentationDetents([.medium, .large])`

**Tests**: existing macOS unit tests + full iOS suites remain green. **Automated macOS UI coverage does not exist** — this is the design's accepted, deferred gap (`SingleThreadMacUITests` is out of scope), so the top layer is verified manually.
**Verify**: `make mac-test` and `make test` green; manual `make mac-run` → Settings shows Interface, Reminder, Filtering & Sorting, Background, Unlock/Purchase, Privacy, About, and Done; iOS sheet unchanged.

---

## Cross-Cutting Notes

- **The sizing fix is only observable at the top layer** (manual `make mac-run`), because the repo has no macOS UI-test target — flagged here rather than silently skipped; the macOS UI target is a deferred follow-up ticket.
- **The diagnostic (Stage 1) is inherently non-automatable** (runtime rendering), so it is a manual checkpoint, not a unit-testable layer.
- No migration/store/service/transport layers apply: this is a single UI-surface change, so the horizontal split is *verification → conditional structure → documentation → rendering*, each green before the next.

## Testing Checkpoints

1. After Stage 1: `make mac-test` + `make test` green; root cause observed.
2. After Stage 2: `make mac-test` + `make test` green; `rg '#else\b'` on settings files is empty.
3. After Stage 3: `make format` + `make lint` + `make mac-test` green; comment-only diff.
4. After Stage 4: `make mac-test` + `make test` green; manual `make mac-run` shows all macOS rows.
