# Design Discussion

## Current State

The repo already enforces warnings-as-errors for almost everything, without
knowing it, and the gate has no observation point for compiler diagnostics.

- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is set **project-level** in both Debug
  and Release (`project.pbxproj:676,731`). Every target inherits it by
  omission except one.
- The **only carve-out** is `SingleThreadTests` = `NO` in both configs
  (`project.pbxproj:856,885`), with an in-place rationale: StoreKitTest's
  headers contain an iOS-18-deprecated symbol, and with warnings-as-errors the
  module's PCM fails to emit (`project.pbxproj:858-860,887-889`). This is the
  established pattern for scoping the lever to one target.
- The SPM package `SingleThreadCore` declares no warning flags
  (`SingleThreadCore/Package.swift:1-24`); the `-suppress-warnings` conflict
  mentioned in `AGENTS.md:145-147` is a *conceptual* caution about toggling
  warnings-as-errors via CLI flags, not a setting present in the tree.
- `scripts/test.sh` runs seven xcodebuild invocations in full mode
  (`test.sh:252,282,294,302,324,332,340`), plus `--unit-only`
  (`test.sh:355-360`) and `--ui-only` (`test.sh:369,378`). Every one streams
  live to the terminal; **no build log is captured or parsed anywhere**
  (`test.sh:2` is `set -euo pipefail`; failures propagate purely via `set -e`).
  The only in-repo capture idiom is `scripts/test-one.sh:30-58`
  (`> "$LOG" 2>&1 &`, `tail -25` on failure).
- CI **does not call `scripts/test.sh`**; `.github/workflows/ci.yml`
  re-implements the phases as separate inline steps (CI inventory in
  `conventions.md`; builds at `ci.yml:52,121,173,237,290`). Build output
  streams to step logs only — no log artifact is uploaded.
- SwiftLint runs `--strict` in all three callers (`Makefile:131`,
  `test.sh:248`, `ci.yml:232`).

Two consequences fall out of this. First, a check added only to `test.sh`
would never run in CI, because CI is a separate path. Second, the compiler
already fails the build for inherited targets, so the *only* surfaces a new
check can add value on are: `SingleThreadTests`, the `SingleThreadCore`
package, and warnings emitted where the setting does not apply.

## Desired End State

1. `./scripts/test.sh` (all three modes) fails if any **compiler warning** is
   emitted by any target it builds — iOS app, watch app, widget, SPM
   `SingleThreadCore`, and all test targets.
2. `.github/workflows/ci.yml` applies the same check to its own build steps,
   using the same helper and the same allowlist.
3. The current warning inventory is zero, except for entries explicitly listed
   in a checked-in allowlist with a one-line rationale each.
4. The checker itself is covered by fixture tests, so a rotted pattern fails
   loudly instead of silently passing.

Verification that we got there: `make check` is green on a clean tree; the
fixture self-test passes; deliberately introducing a warning (e.g. an unused
`var`) into each of the app, watch, widget, `SingleThreadCore`, and
`SingleThreadTests` turns the gate red.

## Patterns to Follow

- **Scoped, documented carve-outs.** The `SingleThreadTests` override
  (`project.pbxproj:856/885`) carries its rationale in a comment *at the
  config site*. The allowlist file must do the same: one pattern per line, a
  `#` comment giving why it cannot be fixed.
- **Gate entry / exit shape.** `scripts/test.sh` uses `set -euo pipefail`
  (`test.sh:2`), prints `==>` banners, and ends with
  `echo "✅ All CI checks passed."; exit 0` (`test.sh:348-349`). New checks
  slot in as a `==>` step and fail via a non-zero exit, not a bespoke status.
- **In-repo capture idiom.** `scripts/test-one.sh:30-58` is the model for
  capturing build output; we adopt `tee` instead of background-redirect because
  the gate must keep streaming live progress, and we add a scan afterwards.
- **Literal-count guard style.** `verify_deployment_target()` in
  `scripts/test.sh` shows the house style for a structural assertion: scan a
  file, count, compare to a named `EXPECTED_*` constant, print `✓`/`✗`, exit 1
  on drift. The allowlist parser and self-test should read the same way.
- **`Makefile` delegates, CI duplicates.** Do not add a new `make` target for
  the check; it is part of `make check` by construction. CI gets explicit
  one-line additions because that is how CI already works.

**Patterns NOT to follow:**
- Do **not** toggle warnings-as-errors via CLI flags (`xcodebuild …=YES`).
  `AGENTS.md:145-147` warns this conflicts with the SPM package's build
  settings; scope via the pbxproj instead.
- Do **not** add `-suppress-warnings` / `-Wno-*` / `.unsafeFlags` to
  `Package.swift`. `AGENTS.md` calls the CLI/settings route out by name, and
  the package currently has no flags (`Package.swift:1-24`). Use the allowlist.
- Do **not** silence a warning with a blanket `swiftlint:disable`-style footer.
  SwiftLint suppression is per-location and narrow (`:next`/`:this`); compiler
  warnings have no equivalent, so unfixable ones go in the allowlist where they
  are visible and reviewable.

## Design Decisions

1. **Hybrid detection.** Keep warnings-as-errors as the primary lever (it is
   already project-wide, `pbxproj:676,731`), and add a **log-scan backstop** as
   the new check. Rationale: only the scan can see `SingleThreadTests` (kept at
   `NO`), the SPM `SingleThreadCore` package, and non-Swift warnings; only the
   compiler lever is free of format fragility. Chosen over scan-only (weaker
   than the compiler for inherited targets) and over flipping every target to
   `YES` (blocked by the StoreKitTest PCM issue, and cannot cover the package).

2. **Scope of the pattern: source-level compile warnings only.** Match
   xcodebuild lines of the shape `<path>:<line>:<col>: warning: <message>`
   (Swift, Clang, ObjC, and SwiftPM target diagnostics). Exclude xcodebuild
   meta-warnings ("Run script build phase … will be run during every build",
   destination chatter) and warnings without a source location. Rationale: the
   task says "compile warnings"; anchoring on the diagnostic shape keeps false
   positives near zero and avoids an allowlist full of toolchain noise.

3. **Default strict, explicit allowlist.** `scripts/xcodebuild-warnings.allow`
   holds one extended-regexp per line, `#` comments allowed. Anything not
   matched fails the gate. Rationale: matches the documented-carve-out pattern
   at the pbxproj site; the StoreKitTest deprecated-symbol diagnostic in the
   `SingleThreadTests` build log is the expected first entry.

4. **Cover all three modes.** Every xcodebuild in full, `--unit-only`
   (`test.sh:355`) and `--ui-only` (`test.sh:369`) routes through the wrapper.
   Rationale: `make test`/`make ui-test` must not be able to pass a tree that
   `make check` rejects.

5. **Leave `SingleThreadTests` at `NO`.** Cover that target via the scan.
   Rationale: respects the documented PCM rationale; the scan gives equivalent
   coverage without reopening a toolchain rabbit hole. If the spike shows the
   PCM issue is trivially avoidable, flipping to `YES` is a follow-up, not a
   prerequisite.

6. **Wire both paths.** `scripts/test.sh` sources the helper; `ci.yml`'s build
   steps `tee` to a log and invoke the same helper, which is a one-line
   addition per build step (`ci.yml:52,121,173,237,290`). Rationale: CI is
   authoritative (AGENTS.md) and a check CI never runs will rot. Making CI call
   `test.sh` wholesale is a larger change and out of scope.

7. **The checker ships with fixture tests.** `scripts/tests/warning-check/`
   holds input logs (clean, one real warning, only-allowlisted, mixed) and a
   runner asserting exit codes. The runner is invoked early in `test.sh` (fail
   fast, before the slow build) and in CI's lint job. Rationale: a
   pattern-matching check fails *open* when its regex drifts.

### Shape of the change

- `scripts/check-warnings.sh` — new. Sourced by `test.sh`; also executable.
  Provides `run_xcodebuild <log> <cmd…>` (tees to log, preserves exit status
  via `PIPESTATUS`, then scans on success) and `check_warnings <log>`
  (greps, filters the allowlist, prints offenders, exits 1 on a miss).
  `test.sh` replaces each bare `xcodebuild …` with
  `run_xcodebuild "$DERIVED_DATA/logs/<step>.log" xcodebuild …`.
- `scripts/xcodebuild-warnings.allow` — new. Documented patterns.
- `scripts/tests/warning-check/run.sh` + fixtures — new.
- `scripts/test.sh` — source the helper; route the 9 invocations; add one
  self-test step.
- `.github/workflows/ci.yml` — `tee` + helper call in each build step.
- Source fixes / allowlist entries for whatever the spike finds.

## What We're NOT Doing

- **Not** flipping `SingleThreadTests` to `YES` (`project.pbxproj:856/885`) in
  this ticket; the scan covers it.
- **Not** adding any flag to `SingleThreadCore/Package.swift`.
- **Not** scanning xcodebuild meta-warnings, linker notices, or
  project-configuration warnings — only source-located compile warnings.
- **Not** making CI call `scripts/test.sh` wholesale, nor unifying the two
  build paths.
- **Not** touching SwiftLint/SwiftFormat scope (`test.sh:248`,
  `Makefile:131`), Periphery, or the deployment-target guard.
- **Not** adding a new `make` target, new test target, or a
  `-resultBundlePath`/`xcresulttool`-based extraction (local Xcode 27 vs CI
  26.6 divergence makes that a portability risk).
- **Not** fixing the known pre-existing macOS-only `EntitlementStoreTests`
  failures (per AGENTS.md) — they are test failures, not warnings.

## Open Risks

- **Warning inventory is unknown.** Research never enumerated the current
  warnings; that is a build spike, not a codebase fact. The plan's first step
  must instrument the gate, run the builds, and capture the actual list before
  any fix work is scoped. This could reveal more allowlist entries than
  expected (SDK/deprecation noise).
- **Platform split.** `test.sh` builds `SingleThreadTests` on macOS
  (`test.sh:340`) while CI builds it on iOS sims (`ci.yml:52,67`). A warning
  may exist on one platform only; the check must run on both paths to be a
  guarantee, which is why decision 6 matters.
- **`tee` changes exit-code plumbing.** `test.sh` relies on `set -euo
  pipefail`; the wrapper must read `PIPESTATUS[0]` (or `set +e` around the
  pipeline) so a build failure is not masked by `tee`'s status.
- **False positives from log content.** A `: warning:` string inside test
  output or a fixture could match; the anchored `<path>:<line>:<col>:` shape is
  the mitigation and the self-test should include a near-miss fixture.
- **Log growth.** Per-step logs under `$DERIVED_DATA` (`test.sh:25`) must be
  confirmed gitignored, or CI/local will accumulate untracked files.
- **Format fragility.** xcodebuild diagnostic text is not a stable API; the
  self-test guards drift, but a future format change will require a pattern
  update, not a logic change. This is the accepted cost of the backstop.
