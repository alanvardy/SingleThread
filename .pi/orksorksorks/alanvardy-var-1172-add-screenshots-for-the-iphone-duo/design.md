# Design Discussion

## Current State

The screenshot pipeline `scripts/appstore-screenshots.sh` (730 lines) is
simulator-only and captures three classes — `iphone-6.3:iPhone 17$`,
`ipad-13:iPad Pro 13-inch (M5)`, and a watch path — for six screens
(`SCREENS` `:234–242`) across seven languages (`:212`). It boots a sim
(`resolve_udid` `:305–321`, name-regex anchored `:245–247`), installs/launches
with `--seed`/`--ui-testing*`/`-showSwipePrompt NO`, stages a wallpaper slot
into the app container via `simctl get_app_container` (`:325–329`, `:429–461`),
sets appearance with `simctl ui` (`:564`), shoots with
`simctl io … screenshot --mask ignored` (`:524–533`), and hard-allowlists the
resulting pixel pairs (`:716`). It has **no test of any kind** (`conventions.md`).

Xcode 27.2 ships an `iPhone Duo` simulator device type (`modelIdentifier`
`iPhone19,4`) whose two integrated displays are **pixel-identical to the App
Store spec pairs**: outer `screenID 1` = 1398 × 2034, inner `screenID 3` =
2007 × 2853. Verified this session on runtime `…iOS-27-2-iPhone19-4`:

- `simctl io <udid> screenshot --display 1` → 1398 × 2034; `--display 3` → 2007 × 2853.
- A UIKit probe shows the outer is **compact/regular, 466 × 678 pt** and reports
  `uname=arm64` but `SIMULATOR_MODEL_IDENTIFIER=iPhone19,4`.
- `UIWindowScene.requestGeometryUpdate(.landscape)` rotates the app and yields
  2034 × 1398 (public API, screenshot-verified).
- The Duo runtime requires identifier `…iOS-27-2-iPhone19-4`; the plain
  `…iOS-27-2` runtime rejects the device type (`Incompatible device`).

App-side, the Duo layout landed on `origin/main` (rebase done this session):
`DuoDisplay.isOuterPortrait` (`DuoDisplay.swift:4–12`) keys on
`uname == "iPhone19,4"` **and** compact-width/regular-height;
`DuoOuterPortrait.machineIdentifier` reads `uname` (`:10–21`) and documents a
fail-safe to `.standard` on the simulator (`:4–7`); `ChecklistLayout` widens the
card (`:21–34`). Because `uname` is `arm64` on the simulator, that layout never
fires there today.

## Desired End State

`bash scripts/appstore-screenshots.sh [flags] iphone-duo` produces, per the
seven languages, the same six screens for four Duo variants at the exact spec
pixels:

| variant | posture | pixels |
|---|---|---|
| `duo-outer-portrait` | folded | 1398 × 2034 |
| `duo-outer-landscape` | folded + app-forced landscape | 2034 × 1398 |
| `duo-inner-portrait` | book (half-open) | 2007 × 2853 |
| `duo-inner-landscape` | open (≈130°) | 2853 × 2007 |

Verification: the run's `sips` dimension gate (`:710–730`) passes with the four
new pairs added, and the outer-portrait shots show the widened Duo card
(horizontal inset 20, cap `min(340, w*0.8)`) rather than the standard 40/cap
layout.

## Patterns to Follow

- **Launch-arg test seams**: follow the `--ui-testing-*` family
  (`AppViewModel.swift:250–321`, `LaunchArgument.swift:18,27`). New seams are
  opt-in argv checks, never persisted-default changes.
- **Seed seam**: keep `--seed '<json>'` + `--ui-testing-app-language` for
  content/language (`UITestingSeed.swift:58–68`); no change needed.
- **Device-name anchoring**: mirror the `iPhone 17$` anchor (`:245–247`) with
  `iPhone Duo$` so the regex does not drift.
- **Output tree**: reuse the `<language>/<class>/<stem>` model and
  `class_folder`/`language_folder` numbering (`:200–228`).
- **Per-display capture**: use `simctl io … screenshot --display <id>`, the
  same mechanism baguette/lody document for Duo panels.
- **Do NOT follow**: `simctl io … screenConfig power` on the inner display —
  the pose lights it, and powering it off crash-loops SpringBoard.
- **Do NOT follow**: changing the production `DuoOuterPortrait` fail-safe
  (`DuoOuterPortrait.swift:4–7`); the seam stays in test/screenshot argv.

## Design Decisions

1. **Capture surface — Duo simulator, no physical device**: the sim's two
   displays already yield the exact spec pairs, so the `devicectl` physical path
   from the research is dropped. Requires the Duo-specific runtime; the script
   resolves the `iPhone Duo` sim and fails with a clear message if the runtime
   is absent.
2. **Rebase onto merged 1170**: PR #247 is merged on `origin/main` (squashed as
   `4f5283f1`); the branch is rebased this session, so `DuoDisplay`/
   `DuoOuterPortrait`/`ChecklistLayout` are present and the widened outer layout
   is capturable.
3. **Detection seam — forcing launch argument**: add
   `--ui-testing-force-duo-outer` so `DuoOuterPortrait.context(...)` returns the
   Duo context under the screenshot/test harness, leaving `uname` detection and
   the documented fail-safe untouched. Unit-tested on the pure seam.
4. **Orientation seam — app-side geometry**: add
   `--ui-testing-orientation portrait|landscape` driving
   `UIWindowScene.requestGeometryUpdate` (public, verified). Used only for the
   outer-landscape variant; the inner display ignores supported orientations and
   is pose-driven.
5. **Pose control — explicit flag + documented Device Hub step**: `--duo-pose
   folded|book|open` selects which panel to shoot; no supported headless hinge
   API exists (`Simulator.app` is absent; Appium/baguette use private APIs).
   The operator sets the pose in `DeviceHub.app` once per posture and re-runs the
   script with the matching `--duo-pose`. One pose change covers all seven
   languages for that posture.
6. **Output tree — four class folders**: `iphone-duo-outer-portrait` →
   `4-duo-outer-portrait`, `…-outer-landscape` → `5-…`, `…-inner-portrait` →
   `6-…`, `…-inner-landscape` → `7-…`, each carrying the six existing stems.
   Keeps the size gate and manifest keyed per variant.
7. **Wallpaper slots — six shared `iphone-duo-<screen>` slots**: all four
   variants reuse the same six photos (class × screen, `:331–339`), fetched once
   via `--fetch-wallpapers`; `stage_slot` must resolve or it exits 3/4.
8. **Dimension allowlist — add the four Duo pairs**: append 1398 × 2034,
   2034 × 1398, 2007 × 2853, 2853 × 2007 to the `:716` allowlist.
9. **Opt-in class, ASC-aware**: `iphone-duo` is not added to the default class
   list (`:657–659`); assets are produced locally because App Store Connect Duo
   upload support is not live (`app-store-screenshots` `SKILL.md:189–190`), and
   the script's doc block says so.
10. **Unchanged**: appearance via `simctl ui` (`:564`), language via
    `--ui-testing-app-language`, wallpaper staging via `simctl get_app_container`
    (`:325–329`), and seeding.
11. **Unit coverage for the seams**: the pure seam decisions
    (`--ui-testing-force-duo-outer` mapping, orientation argv parsing) ship with
    Swift Testing cases in `SingleThreadTests`, per repo policy.

## What We're NOT Doing

- No physical-device / `devicectl` capture path; no `devicectl device capture`.
- No change to `DuoDisplay`/`DuoOuterPortrait` production detection or its
  fail-safe; no reading `SIMULATOR_MODEL_IDENTIFIER` in production.
- No Device Hub automation, no private-CoreSimulator helper, no third-party
  `baguette`/Appium dependency.
- No inner-display `screenConfig power` manipulation (crash-loops SpringBoard).
- No per-variant wallpaper duplication (24 files) and no `iphone-duo` default-run
  inclusion.
- No new test target; no `scripts/test.sh` / CI rewiring for the shell script.
- No child tickets — all work on this branch.

## Open Risks

- **Pose precision**: the exact hinge angles for `book` (inner portrait) vs
  `open` (inner landscape) are runtime-dependent; the operator step must be
  documented with observed panel sizes (466 × 678 outer; 669 × 951 inner).
- **Inner orientation**: Apple documents that the inner display ignores
  supported orientations, so `--ui-testing-orientation` may be a no-op there;
  the design relies on pose, not the flag, for inner orientation.
- **Runtime dependency**: the Duo device type requires runtime
  `iOS-27-2-iPhone19-4` (or later Duo runtime); the plain 27.2 runtime fails.
  The script must detect this rather than silently skipping.
- **Duo layout on inner**: `isOuterPortrait` requires compact/regular; the inner
  is regular/regular, so it correctly renders the standard layout — confirm the
  captured inner shots match that expectation.
- **ASC not live**: uploaded Duo assets will be rejected until App Store Connect
  opens the slot; flag this in the PR and the script doc block.
- **No shell-script tests**: `appstore-screenshots.sh` remains untested beyond
  the runtime `sips` gate (per `conventions.md`); the seam unit tests only cover
  the Swift side.
