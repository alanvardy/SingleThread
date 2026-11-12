# Structure Outline

## Approach

Extend `scripts/appstore-screenshots.sh` with an **opt-in** `iphone-duo` device
class that resolves the Duo simulator, captures per display with
`simctl io … screenshot --display <id>`, and adds the four spec pixel pairs to
the `sips` allowlist. Reuse the existing six `iphone-duo-<screen>` wallpaper
slots (one `DEVICE_TYPES` entry ⇒ slots stay shared across all four variants).
Two small app-target launch-arg seams make the Duo outer layout fire on the sim
(`--ui-testing-force-duo-outer`) and force landscape geometry
(`--ui-testing-orientation landscape`); the Duo *production* detection and its
fail-safe are untouched. Poses (`--duo-pose folded|book|open`) are operator
steps in Device Hub; one pose re-run covers all seven languages.

`DuoDisplay`/`DuoOuterPortrait`/`ChecklistLayout` are present on this branch
(rebase verified: `git ls-files SingleThread/Duo*.swift` lists both) — the
`conventions.md` "unmerged" note is superseded by `design.md`.

---

## Phase 1: Walking skeleton — folded outer portrait, end to end

`bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo` boots the
Duo sim, launches the app with the force seam, and writes seven
`4-duo-outer-portrait/` shot sets at exactly 1398 × 2034 with the widened Duo
card. Green here proves resolve → boot → install → force launch → layout →
`--display 1` capture → `sips` gate, the whole chain.

**Files**: `SingleThread/LaunchArgument.swift`, `SingleThread/DuoOuterPortrait.swift`,
`SingleThreadTests/DuoOuterPortraitTests.swift`, `scripts/appstore-screenshots.sh`

**Key changes**:
- `LaunchArgument.forceDuoOuter = "--ui-testing-force-duo-outer"` — new case; existing `isPresent(_:in:)` reused.
- `DuoOuterPortrait.context(horizontal:vertical:machine:forceDuoOuter:) -> ChecklistLayout.Context` — new `forceDuoOuter` param that short-circuits the size-class/machine check; the live `context(horizontal:vertical:)` overload passes `LaunchArgument.isPresent(.forceDuoOuter)`.
- Script: `DEVICE_TYPES += "iphone-duo:iPhone Duo$"`; `DUO_POSE` global + `--duo-pose folded|book|open` CLI case; `shoot <out> [--display <id>] <launch-args…>` gains the display selector; `duo_display_for_pose()` → `1`; `class_folder` maps `iphone-duo`→`4-duo-outer-portrait`; allowlist adds `1398x2034`.

**Contract**: CLI shape `--duo-pose <pose>`; `shoot` accepts `--display`; launch
arg `--ui-testing-force-duo-outer`; output path
`<lang>/4-duo-outer-portrait/<stem>.png`; outer panel is display id `1`.
Later slices extend this, never re-shape it.

**Tests**: `DuoOuterPortraitTests.forceFlagReturnsDuoContext` (new; happy path)
and `.emptyMachineIsStandard` / `.duoMachineInRegularRegularIsStandard` (unchanged,
prove the seam stays opt-in). Shell: `bash -n scripts/appstore-screenshots.sh` +
the runtime `sips` gate.
**Verify**: `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` green;
manual `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose folded iphone-duo` (pose set to *folded* in Device Hub) reports `7×6 screenshots, every size accepted`.

---

## Phase 2: Folded outer landscape, end to end

`--duo-pose folded` also emits the app-forced landscape variant: the same seven
folded runs additionally land `5-duo-outer-landscape/` at 2034 × 1398.

**Files**: `SingleThread/LaunchArgument.swift`, `SingleThread/AppDelegate.swift`,
`SingleThreadTests/LaunchArgumentTests.swift`, `scripts/appstore-screenshots.sh`

**Key changes**:
- `LaunchArgument.orientationValue(in:) -> String?` — parses the token after `--ui-testing-orientation`; new case `orientation = "--ui-testing-orientation"`.
- `AppDelegate.applyForcedOrientationIfNeeded()` — when the arg is `landscape`, calls the existing `applyLock`/`requestGeometryUpdate(.landscape)` path at launch; otherwise a no-op (production unchanged).
- Script: folded branch shoots display `1` a second time with `--ui-testing-orientation landscape`; `class_folder` gains `5-duo-outer-landscape`; allowlist adds `2034x1398`.

**Contract**: `--ui-testing-orientation portrait|landscape` is the only
orientation seam; `5-duo-outer-landscape` folder and `2034x1398` pair. Depends on
Phase 1 only through the `--duo-pose`/`shoot --display` shape.

**Tests**: `LaunchArgumentTests.orientationValueParsesLandscape` / `.orientationValueAbsentIsNil`
(new; happy + sad). Shell `bash -n` + size gate.
**Verify**: `scripts/test-one.sh SingleThreadTests/LaunchArgumentTests` green;
manual folded run shows both `4-…` (1398×2034) and `5-…` (2034×1398) accepted.

---

## Phase 3: Inner display, both poses, end to end

`--duo-pose book` yields `6-duo-inner-portrait/` (2007 × 2853) and
`--duo-pose open` yields `7-duo-inner-landscape/` (2853 × 2007), both from
display id `3`. The inner panel is regular/regular, so the standard layout is
correct — no app seam.

**Files**: `scripts/appstore-screenshots.sh`

**Key changes**:
- `duo_display_for_pose()` → `3` for `book`/`open`.
- `class_folder` gains `6-duo-inner-portrait`, `7-duo-inner-landscape`.
- Allowlist adds `2007x2853`, `2853x2007`.
- (Inner capture ignores `--ui-testing-orientation`; orientation is pose-driven — documented in the doc block.)

**Contract**: pose→display/folder/size table is total; no new app seam. Depends
only on Phase 1's CLI and capture shapes.

**Tests**: shell `bash -n`; runtime `sips` gate is the acceptance (no Swift code
changes). Manual: confirm inner shots render the standard 40-inset layout.
**Verify**: `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose book iphone-duo` and `… --duo-pose open iphone-duo`, each reported accepted.

---

## Phase 4: Hardening & documentation

Clear failure when the Duo runtime/device type is absent (exit non-zero with a
message, never a silent skip); doc block gains the four variants, the three
invocations, the Device Hub pose instructions with observed panel sizes
(466 × 678 outer, 669 × 951 inner), the `--display`/pose table, and the
App Store Connect "Duo slot not live" note. Confirm `iphone-duo` is **not** in
the default class list.

**Files**: `scripts/appstore-screenshots.sh`

**Key changes**: `capture_class` distinguishes "Duo class, no matching runtime"
from a generic skip; doc block (`:1–128`) rewritten for the Duo workflow;
`--fetch-wallpapers` covers the six new slots.

**Contract**: none new — this is polish + operator-facing docs.

**Tests**: `bash -n`; hand-run `shellcheck -S warning` (not gate-wired, per
`conventions.md`); full manual three-invocation sweep across the seven languages.
**Verify**: all four class folders present with every size accepted; wallpapers
resolve for all six `iphone-duo-*` slots.

---

## Testing Checkpoints

- **After Phase 1**: `DuoOuterPortraitTests` green; folded run accepted. Save the
  resolved Duo UDID — later slices reuse it via `resolve_udid`.
- **After Phase 2**: `LaunchArgumentTests` green; folded run now yields both
  outer folders. If `requestGeometryUpdate` proves flaky on the Duo runtime,
  stop and re-open the design's orientation decision before Phase 3.
- **After Phase 3**: all four folders produced across the three pose runs.
- **After Phase 4**: `make test` (units) + `bash -n` + full manual sweep green;
  run the full gate once via the `run-gate` skill (the shell script has no
  gate-wired test, so the Swift seam suites are the only CI-visible coverage).

Note: `scripts/appstore-screenshots.sh` has no automated test beyond the runtime
`sips` gate (`conventions.md`); the Swift seam suites are the only gate-covered
tests. No new test target, no `scripts/test.sh`/CI rewiring.
