# Phase 1 report — Duo outer portrait widens the reminder card end-to-end

**Branch**: `alanvardy-var-1170-increase-width-on-outer-duo-screen`
**Status**: implemented, lint/format clean, build + targeted suites green.
**Scope**: Phase 1 only. Phase 2 (empty states + AI-sort banner) not started.

## What was implemented

Phase 1 of the plan, with the plan's snippets adjusted only where the compiler /
linters required (see "Deviations").

### New files (app target `SingleThread/`)

- `SingleThread/ChecklistLayout.swift` — pure layout policy. `Context.standard`
  delegates the width cap to `CardWidth` (so the default path cannot drift from
  `min(340, W * 0.6)`), and the Duo outer variant returns `min(340, W * 0.8)` and
  a 20 pt gutter (standard gutter 40 pt).
- `SingleThread/DuoDisplay.swift` — pure detector. Matches only machine
  `"iPhone19,4"` **and** compact width **and** regular height.
- `SingleThread/DuoOuterPortrait.swift` — app-target adapter. Reads `uname`
  machine identifier (empty off-iOS) and maps SwiftUI size classes to a
  `ChecklistLayout.Context`. Two explicit overloads (no default argument) so the
  MainActor-isolated `machineIdentifier` is never read from the `nonisolated`
  test seam.

### Modified

- `SingleThread/ContentView.swift`:
  - added `@Environment(\.horizontalSizeClass)` / `@Environment(\.verticalSizeClass)`;
  - added `var layoutContext: ChecklistLayout.Context` (no access modifier, so the
    `ContentView+iOS.swift` extension can read it in Phase 2);
  - reminder card `maxWidth` now `ChecklistLayout.maxContentWidth(viewportWidth:context:)`;
  - reminder row `.padding(.horizontal, 40)` → `ChecklistLayout.horizontalInset(layoutContext)`.
  - Empty-state call sites (`EmptyStateCard.maxContentWidth`) deliberately untouched (Phase 2).

### New tests (`SingleThreadTests/`, Swift Testing, non-`test`-prefixed names)

- `ChecklistLayoutTests.swift` (9 cases) — standard gutter/width, anti-drift loop
  against `CardWidth` across the domain, Duo fraction, ceiling clamp, the exact
  425 crossover, a safe-area-adjusted Duo viewport, zero-viewport.
- `DuoDisplayTests.swift` (6 cases / 12 parametrised rows) — happy path, inner
  display, outer landscape, other machines, full size-class matrix, malformed
  (trailing space / newline / lowercase) identifiers.
- `DuoOuterPortraitTests.swift` (5 cases, `@MainActor`) — Duo machine in
  compact/regular is Duo-outer, inner/regular is standard, non-Duo is standard,
  fail-safe empty/nil, `machineIdentifier` readable on iOS / empty otherwise.

## Deviations from the approved plan (all forced by the toolchain)

1. **SwiftLint `type_body_length` blocker — supervisor-approved Option A.**
   `struct ContentView` is already at 499 code lines on `origin/main` (threshold
   500). The Phase-1 additions add ~7 code lines → 506, and `make lint --strict`
   fails. Escalated via `contact_supervisor` (`need_decision`); supervisor
   approved adding a scoped disable. Final form is
   `// swiftlint:disable:next type_body_length` immediately above the struct with a
   one-line rationale (the file already uses `// swiftlint:disable file_length`
   for the same "keep the single-screen modifiers together" reason). A blanket
   disable was rejected by `blanket_disable_command`, hence `:next`.
2. **Environment attributes split onto their own lines.** SwiftLint's `attributes`
   rule rejects `@Environment(\.horizontalSizeClass) private var …` on one line,
   so each is two lines (this also contributed to the line-budget above).
3. **`Context.standard` marked `nonisolated`.** Under the app target's
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, the unannotated `static let
   standard` was MainActor-isolated and failed to compile from the nonisolated
   `ChecklistLayoutTests` suite. Added `nonisolated` (the plan's note anticipated
   the reverse case).
4. **Force-unwrap removed** in `DuoOuterPortrait.machineIdentifier`: the plan /
   CheckStitch reference used `raw.baseAddress!`, which trips this repo's
   `force_unwrapping` lint rule (force-unwrapping is banned outside test code).
   Replaced with `guard let base = raw.baseAddress else { return "" }`.
5. SwiftFormat moved `layoutContext` into the internal section, moved the
   `@Environment` values into `// MARK: Private`, reordered `Context` members
   (static before stored) and rewrote `Context(...)` as `Self(...)`. Purely
   cosmetic; the plan's intent is preserved.

## Validation run

| Command | Result |
| --- | --- |
| `make format` | clean (only the phase's files change; `git status` shows no unrelated edits) |
| `make lint` (`swiftformat --lint …` + `swiftlint lint --strict`) | 0 violations |
| `make build` (SIM pinned from `.simulator_id`) | `** TEST BUILD SUCCEEDED **` |
| `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` | ok: 9 cases |
| `scripts/test-one.sh SingleThreadTests/DuoDisplayTests` | ok: 6 cases |
| `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` | ok: 5 cases |
| `scripts/test-one.sh SingleThreadTests/CardWidthTests` | ok: 4 cases (default path untouched) |
| ripgrep guard on ContentView.swift for the old 40pt gutter / `CardWidth.maxContentWidth` | no matches (guard holds) |
| `git status --porcelain` | only the 1 modified + 6 new + artifact dir; nothing staged |

Note: the first `test-one.sh` invocation hit a simulator launch flake
(`Simulator device failed to launch`); resolved by `xcrun simctl shutdown all`,
killing stray `xcodebuild`/`xctest`, then booting the pinned UDID — per the
`simulator-pairing` remedies. All re-runs green.

## Manual checks (not run — no Duo hardware, no on-device run this session)

- Non-Duo simulator visual parity (card `min(340, 0.6W)`, 40 pt gutters) and
  landscape parity are **not** independently verified here; they are covered by
  the unit tests (standard context delegates byte-for-byte to `CardWidth`) and
  by the fact the environment values default to `nil` → `.standard`.
- On-device Duo outer portrait check needs Duo hardware that is not available in
  this environment.

## Residual risks / open questions

- The Duo path is only exercised through injected machine strings; the real
  geometry (`uname` = `iPhone19,4` + compact/regular size classes) is the plan's
  stated assumption and was not device-verified.
- The `type_body_length` disable is now load-bearing; Phase 2 adds more lines to
  `ContentView.swift`, so it must stay.
- Phase 2 still needs: empty-state call sites, deletion of
  `EmptyStateCard.maxContentWidth` (Periphery-checked), and the AI-sort banner
  gutter in `ContentView+iOS.swift`.

## Recommended next step

Proceed to Phase 2 as planned (empty states + `ContentView+iOS.swift` banner
gutter + the broader standard-path regression test), keeping the Phase-1
`type_body_length` disable in place.
