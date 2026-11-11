# Phase 2 report — Empty states and the AI-sort banner follow the same policy

**Scope**: Phase 2 only. Phase 1 was already committed (`38da945d`) and was not re-implemented,
re-run or modified. No other phase was started or "completed". No project-wide gate
(`./scripts/test.sh`) was run. `plan.md` / `implement.md` / `.pi/orksorksorks/**` were **not**
staged or committed.

**Commit**: `e1af721f` — "Phase 2: Empty states and the AI-sort banner follow the same policy"
**Pushed**: `origin/alanvardy-var-1170-increase-width-on-outer-duo-screen` (`38da945d..e1af721f`)

## Changes made (4 files, +18 / −12)

1. `SingleThread/ContentView.swift` — both empty-state call sites converted from
   `EmptyStateCard.maxContentWidth(viewportWidth:)` to
   `ChecklistLayout.maxContentWidth(viewportWidth:context: layoutContext)`:
   - `case .allDone:` (now `:446`) — 24-space indent preserved.
   - `case .empty(hasHidden:)` (now `:463`) — 28-space indent preserved.
   (Plan cited `:434` / `:449`; Phase 1's additions shifted them to `:449` / `:464`
   pre-edit. Call-site identity confirmed by grep, not line number.)
2. `SingleThread/EmptyStateCard.swift` — deleted the unused
   `static func maxContentWidth(viewportWidth:)` and its 5-line doc comment
   (`// MARK: Private` now follows `body` directly).
3. `SingleThread/ContentView+iOS.swift` — `aiSortFailureBanner`'s outer
   `.padding(.horizontal, 40)` → `.padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))`
   (`:176`). The inner `.padding(.horizontal, 20)` / `(.horizontal, 16)` are untouched.
4. `SingleThreadTests/ChecklistLayoutTests.swift` — added the plan's
   `standardContextMatchesLegacyLayoutAtRealViewports` test verbatim (402 / 382 / 874 / 1024 plus
   the standard 40 pt inset).

No new logic, no new files, no `ReminderCardView` / `EmptyStateCard` internals, no vertical
padding, no schema/API change.

## Verification (Phase 2 Automated items only)

| Command | Result |
|---|---|
| `make format` | passed — only the 4 Phase 2 files differ afterwards (`git diff --stat` = 4 files) |
| `make lint` | passed — "Found 0 violations, 0 serious in 239 files" |
| `make build` | passed — `** TEST BUILD SUCCEEDED **`, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` |
| `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` | passed — `ok: 10 case(s) ran` (was 9; the new test is the 10th) |
| `scripts/test-one.sh SingleThreadTests/CardWidthTests` | passed — `ok: 4 case(s) ran` |
| `make periphery` (after `rm -rf DerivedData`) | 1 finding, **pre-existing and unrelated** — see below |
| `rg -n "horizontal, 40\|EmptyStateCard.maxContentWidth" SingleThread/` | returns nothing (exit 1); repo-wide `EmptyStateCard.maxContentWidth` also returns nothing |
| `make format` / `make lint` re-check after edits | 0 violations |

### The single periphery finding is pre-existing (not a Phase 2 regression)

```
SingleThread/ReminderCardView.swift:74:24: warning: Unused property 'swipeOffset'
Error: Found 1 issue.
```

- `ReminderCardView.swift` is untouched by this commit (`git diff HEAD -- SingleThread/ReminderCardView.swift`
  is empty) and the property is byte-identical on `origin/main`.
- `swipeOffset` is read only through its `$`-projection (`offset: $swipeOffset`, `ReminderCardView.swift:136`),
  which is the documented local Xcode 27 false positive
  (`~/.pi/agent/skills/periphery/SKILL.md`: "Under Xcode 27, Periphery **misses `$`-projection-only
  `@State`** … symptom **CI-green, locally red**"). Local toolchain is Xcode 27.0 (27A266a).
- The Phase 2 periphery criterion — *no unused `EmptyStateCard.maxContentWidth` / new symbol* — is
  satisfied: Periphery reports exactly one issue and it is not a symbol this phase touched or created.
  Fixing it would mean editing `ReminderCardView` (explicitly out of scope), so it is left for the
  gate/CI and reported here instead.
- Phase 1's plan did not include a periphery check, so this finding was not previously observed in this
  branch; it is not caused by either phase.

`plan.md` Phase 2 **Automated** checkboxes were ticked; the **Manual** checkboxes were left untouched
(they need a simulator/Duo hardware and belong to the parent).

## Residual risks / open items

- The Duo outer-portrait visual result (20 pt gutters, `min(340, width * 0.8)`, banner aligned to the
  card) is unverified on hardware — no Duo simulator exists and the detector reads `uname`. Unit tests
  are the authority, as the plan states.
- `make periphery` exits non-zero locally because of the pre-existing `swipeOffset` finding; the
  CI-identical gate (`./scripts/test.sh`, CI Xcode 26.6) is the authority for that symbol.
- Unrelated working-tree noise: `.pi/orksorksorks/alanvardy-var-1170-increase-width-on-outer-duo-screen/`
  is untracked (artifacts, deliberately not staged). `DerivedData/` was removed before the periphery run
  and the scan did not leave it behind, so the next build/test run in this worktree starts clean.
