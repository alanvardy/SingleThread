# Done

- **Branch / head SHA**: `alanvardy-var-1129-change-swipe-behaviour` @ `ae17072b`
  (rebased onto `origin/main` `6b3a33cc`; pushed with `--force-with-lease`).
  Commits: `075d5ab9` Phase 1, `04675fba` Phase 2, `15844bb7` DELETEME removal,
  `b69b34c5` phase artifacts, `ae17072b` review fix.

- **Mechanical checks**:
  - `make format` — clean (0 files changed after apply).
  - `make lint` — 0 violations / 0 serious in 228 files.
  - Targeted: `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` —
    17 cases ran, all pass (red-first confirmed: `shallowUpRevealsNothing`
    failed before the guard, passes after).
  - Full CI gate (`./scripts/test.sh`, managed worktree @ `b69b34c5`, pinned
    `SIM=D5156E86…` + `WATCH_TEST_SIM=3F69EA19…` watchOS 26.5 46mm):
    deployment-target/wrapper checks, SwiftFormat, SwiftLint, build (no
    un-allowlisted warnings), watch build, Periphery (none), **iOS UI 6/6**
    (incl. all three swipe tests), watch UI, watch unit — all ✅.
    macOS unit: 758 passed / **1 failed** —
    `AISortCoordinatorTests.reRanksAfterSilentFallbackClearsTheDigest`.
    Verified pre-existing flake, **not a blocker**: the branch touches no
    `AISort`/sort/rank file, the test is unchanged from `origin/main`
    (`24f9d568`), and it re-ran green in isolation (1.12 s). CI is the
    authority for the macOS stage; if it recurs, the fix belongs in
    `AISortCoordinatorTests`, not this branch.
  - Note: the gate covers `b69b34c5`; the review fix `ae17072b` was verified
    with the targeted suite + format/lint above (a full re-gate was not run).

- **Review outcome**: one bounded `reviewer`, fresh context, no blockers.
  - **Fix applied (worth doing now)**: `SwipeGesture.revealedOutcome(forOffset:)`
    could preview a horizontal action that `outcome(for:)` would discard on
    release (e.g. shallow up-drag `dx=60, dy=−100` showed `.complete` but
    released `.none`). Added the mirrored
    `guard abs(vertical) <= abs(horizontal) else { return .none }` and the
    `shallowUpRevealsNothing` regression test.
  - **Optional items documented, not code-changed**:
    - Upward List scroll can lift the card and reveal the More plate
      (`revealedOutcome` fires `.more` for any steep negative `dy`); the release
      still needs 96 pt. Inherent to the shared gesture model (horizontal reveal
      behaves the same); flagged for device confirmation below.
    - macOS now left-swipe-skips and moves the menu behind the up-swipe — locked
      in `plan.md` Q2a but outside the iOS-only ticket; confirm product intent.
  - Declined/irrelevant: reviewer's "full gate/UI unverified" is now covered by
    the gate above; the `implement.md` stale `DELETEME` note is moot (removal is
    committed at `15844bb7`).

- **Remaining manual items** (from `plan.md` / `implement.md`, plus review):
  - iPhone: right-drag completes; left-drag skips to the next reminder (or empty
    state); up-drag opens the Skip / Reschedule / Delete menu.
  - Downward drag and pull-to-refresh still scroll without opening the menu;
    **upward scroll of the list does not spuriously open it** (review add).
  - A shallow diagonal drag fires nothing and shows no reveal badge.
  - VoiceOver rotor on the card offers Complete, Skip and More; the guide copy is
    skipped while Dismiss remains reachable.
  - Guide enabled: `↑ Swipe up for more` above the card; `← Swipe left to skip`
    and `Swipe right to complete →` as one row below it; Dismiss hides all.
  - Settings → Interface → "Show swipe prompt" off hides the whole guide.
  - Large Dynamic Type (AX5): guide wraps without truncating; card not clipped.
  - macOS: confirm the remapped left/up behaviour matches product intent.
