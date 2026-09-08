# Design Discussion — Work on settings in macOS

## Current State

The macOS build shares one app target (`SingleThread/`) with iOS and presents
Settings as a `.sheet(isPresented:)` driven by the gear button
(`ContentView.swift:160-171`, sheet at `:243-244`). On macOS the sheet's only
size lever is a `.frame(minWidth: 400, minHeight: 500)` inside `#if os(macOS)`
(`ContentView.swift:549-553`) — the comment explains the root settings `List`
reports no intrinsic height and collapses to 0px without a floor
(`ContentView.swift:550-551`). There is no `presentationDetents`,
`presentationBackground`, or `NSWindow` geometry anywhere in the app
(research Q1).

`SettingsView` is a `NavigationStack { List { … } }` (`SettingsView.swift:32-33`)
whose rows are plain `NavigationLink`s into sub-views (research Q2). Every
pushed sub-view is a bare `Form` (`PurchaseSettingsView` uses `List`) plus a
`.navigationTitle(_:)`; **none** adds `.toolbar`, `ScrollView`, `Spacer`,
`frame`, or alignment modifiers (`InterfaceSettingsView.swift:26-74` is
representative). They therefore rely entirely on the framework's vertical
placement inside a ~500px-tall sheet.

The bug: on macOS, pushing a submenu (e.g. Interface) renders the submenu's
navigation title + back button **almost vertically centered** in the sheet
instead of flush with the top.

Settings has **no** shared layout helper to hang a fix on — `CardPlate`,
`CardPlateModifier`, `ControlPlateModifier`, and `EmptyStateCard` are
main-content-only (research Q5); the settings bundle uses stock `List`/`Form`
chrome throughout, with the only card-plate call adjacent to settings being the
gear button's `.controlPlate()` (`ContentView.swift:167`).

Tests: macOS is a **unit-test-only** destination (`scripts/test.sh:288-292`;
`Makefile:26-27`; `ci.yml:270, :297, :308`). `SingleThreadUITests` has no macOS
destination anywhere; there are **no** macOS UI tests (research Q6). Existing
settings unit tests assert on view bodies via `String(describing: view.body)`
(`SettingsViewTests.swift:37-51`).

## Desired End State

On the macOS build, opening any submenu inside the Settings sheet renders the
submenu's navigation title and back button flush with the top of the settings
card, with short-form content top-anchored beneath them (no vertical centering).
This holds for every pushed sub-settings screen — the six primary sub-views,
2nd-level `ExcludedListsView`, and the List-based `PurchaseSettingsView`.

iOS behavior is unchanged: the fix is macOS-gated and the iOS Settings surface
stays pixel-identical (it is already covered by `SingleThreadUITestsFlows` and
the appearance launch tests).

**Verification of correctness:**
- Manual visual check via `make mac-run` — open each submenu and confirm the
  title + back button sit at the top of the card.
- Unit tests (Swift Testing, runs on macOS) assert the top-alignment modifier is
  applied to every sub-settings view (mirroring the `String(describing:
  view.body)` pattern already used in `SettingsViewTests.swift`).
- Full gate `./scripts/test.sh` still passes (the parent runs this once after
  implementation phases commit).

## Patterns to Follow

- **Platform-gated layout via `#if os(macOS)`** — the existing sheet min-frame
  (`ContentView.swift:549-553`) and main-list centering
  (`ContentView.swift:358-379`) are the house style for "fix macOS layout, leave
  iOS alone". Our modifier follows this exactly.
- **Focused binding subsets, not the whole bag** — sub-views take only the
  `@Binding`s they need (`SettingsView.swift:36-51`; `InterfaceSettingsView`
  doc comment). Our change is layout-only and must not alter this data flow.
- **Staged modifier chains with their own type-check budget** — the 19-`onChange`
  write-back chain is split into functions deliberately
  (`ContentView+Settings.swift:5-7`). Keep our modifier small and self-contained.
- **Settings uses stock `Form`/`List` chrome** — no card plates in settings
  (research Q5). A *minimal* settings-scoped layout helper is a new but
  consistent venture; do not pull `CardPlate`/`EmptyStateCard` styling into
  settings.
- **Unit tests describe view structure via `String(describing: view.body)`**
  (`SettingsViewTests.swift:37`) — reuse this rather than inventing a new
  assertion style.

**Patterns to NOT follow:**
- Do **not** add scrolling fixes (no sub-view has a `ScrollView`; content is
  short — wrapping in `ScrollView` would be a larger, risky change).
- Do **not** reach for `navigationBarTitleDisplayMode`/analogues — the codebase
  has zero usage; treat it only as a conditional fallback if reproduction shows
  the *title element itself* is what centers (see Q1-Option C).
- Do **not** paint settings with `CardPlate`/`ControlPlate` — those are the main
  reminder content's visual language, intentionally absent from settings.

## Design Decisions

1. **Fix direction — top-anchor the pushed destinations (Option A)**:
   Add a macOS-gated modifier forcing the destination's content to fill and
   top-align (`maxHeight: .infinity, alignment: .top`) so the nav header and
   form sit flush to the top regardless of the sheet's extra height. Chosen over
   resizing the sheet (Option B: risks the root-List-collapse the `minHeight: 500`
   floor exists to prevent) and over title-display-mode tweaks (Option C: too
   narrow). Robust to the exact centering mechanism, which research flags as
   unverified framework behavior.

2. **Fix location — one shared modifier applied per view (Option A)**:
   A single small settings-scoped modifier (e.g. `SettingsSubscreenLayout`)
   added to the end of each sub-view's `Form`/`List`. Chosen over restructuring
   the root `NavigationStack` to `navigationDestination(for:)` (Option B), which
   would be a larger, iOS-regression-prone change to a currently stock
   `NavigationLink` hierarchy.

3. **Platform gating — `#if os(macOS)` only (Option A)**:
   The modifier compiles to a no-op on iOS, matching the existing min-frame gate.
   Zero risk to the well-tested iOS settings surface; no cross-platform
   no-op wrapper needed.

4. **Scope — all pushed sub-settings views (Option A)**:
   Apply uniformly to the six primary sub-views, 2nd-level `ExcludedListsView`,
   and `List`-based `PurchaseSettingsView`. `PurchaseSettingsView` uses the
   container type most likely to lay out differently; including it (guarded by
   the same modifier) keeps behavior uniform and honors the task's "every
   sub-settings screen" wording.

5. **Verification — manual macOS + unit tests, no UI target (Option A)**:
   Visual verification via `make mac-run`; a Swift Testing test asserts the
   modifier is present on every sub-settings view (using the
   `String(describing: view.body)` pattern). The PR states explicitly that macOS
   layout is manually verified and not covered by an automated UI test (no macOS
   UI target exists, and adding one via new pbxproj target + CI matrix is
   disproportionate — `AGENTS.md` research Q6/Observations).

## What We're NOT Doing

- **Not** adding a macOS UI-test target (or wiring `SingleThreadUITests` to a
  macOS destination).
- **Not** touching the `minHeight: 500` sheet floor or any sheet geometry.
- **Not** restructuring `NavigationStack`/`NavigationLink` navigation.
- **Not** introducing `ScrollView`s or card-plate styling into any settings view.
- **Not** changing the settings data flow (`SettingsBindings`,
  `settingsSheetWritebacks`, binding subsets) — layout only.
- **Not** altering iOS behavior: the change is gated out on iOS.
- **Not** addressing the separate purchase-sheet sizing gap (research Q1 notes
  `PurchaseSheet` has no min-frame) — out of scope unless reproduction shows it
  shares the same bug.

## Open Risks

- **Unverified mechanism**: research flags the macOS nav-bar centering as
  framework behavior with no repo code confirming it. Implementation must first
  reproduce and characterize on `make mac-run` before finalizing the modifier.
  If reproduction shows the *title itself* (not content) is centered, fold in a
  minimal title-style tweak as a conditional fallback, keeping the top-anchor
  modifier.
- **`PurchaseSettingsView` (List) layout**: a `List` destination may center
  differently than `Form`; if the shared `maxHeight/.top` modifier doesn't
  normalize it, treat that one view as a scoped follow-up rather than expanding
  the change.
- **Modifier placement vs. nav header**: `.frame(maxHeight: .infinity,
  alignment: .top)` frames the *body*; if the system-rendered nav header
  (`navigationTitle` + back) still floats, the modifier may need to target the
  container SwiftUI measures for the whole destination — verify empirically
  rather than guessing.
- **macOS unit-test assertion strength**: `String(describing: view.body)` can
  only assert the modifier *is present*, not that rendering is correct — that
  gap is covered by the manual `make mac-run` check, which cannot run in CI.