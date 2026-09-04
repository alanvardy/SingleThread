# Implementation Summary

Branch: `alanvardy-var-775-refactor-name-the-freemium-cap-constant-100` — VAR-775:
name the freemium cap constant (100). T4.1 from the VAR-759 state audit.

## What changed

`EntitlementStore.freemiumCap = 100` is the single source of truth for the
free-tier completion cap. All cap-referencing sites now use it; strict-`<`
semantics preserved (gate still closes at exactly 100).

| File | Change |
|------|--------|
| `SingleThreadCore/.../EntitlementStore.swift` | added `public static let freemiumCap = 100` (doc: strict-`<` semantics) |
| `SingleThreadCore/.../ReminderStore.swift` | `canMutate` gate + doc comment use the constant |
| `SingleThreadWatch/WatchAppViewModel.swift` | `--ui-testing-gated` seam seeds `EntitlementStore.freemiumCap` |
| `SingleThreadTests/ReminderStoreGateTests.swift` | 6 sites → constant; below-cap fixtures become `freemiumCap - 1` |
| `SingleThreadTests/ReminderStoreTests.swift` | undo-gated test seeds `EntitlementStore.freemiumCap` |
| `SingleThreadUITests/SingleThreadUITestsFlows.swift` | 4 gate seeds interpolate `\#(cap)`; `import SingleThreadCore` |
| `SingleThread.xcodeproj/project.pbxproj` | `SingleThreadUITests` target links `SingleThreadCore` (new `PBXBuildFile` `518BF49A…` + Frameworks phase + package product dependency) |
| `DELETEME` | removed branch placeholder |

The full `EntitlementTier` enum (Enum Sketch 2) stays deferred — out of this
ticket's scope ("e.g." placement; acceptances are literal-removal + boundary).

## Learning: seed JSON must stay single-line

Initial UI-test run failed with the seeds reformatted as multiline raw strings
(`#"""…"""#`). `UITestingSeed` decodes the seed from a `--seed '<json>'`
launch argument and is whitespace-insensitive in theory, but the launch-arg
transport mangles embedded newlines — the app fell back to the unseeded state
and the gated render never appeared. Reverting to single-line raw strings
(with a local `let cap` to keep lines ≤ 120) fixed it. **Rule: seed JSON in UI
tests must stay on one physical line.**

## Verification (targeted, pre-commit)

- [x] `make format` / `make lint` — 0 violations
- [x] `xcodebuild build-for-testing` (Debug, warnings-as-errors) — passes
- [x] `SingleThreadTests` unit suite — all pass (gate boundary 99 vs 100 via `- 1`)
- [x] Freemium-gate UI tests ×4 — all pass (with constant-backed seeds)

## Full local gate (`./scripts/test.sh`)

Ran twice; both runs failed exactly one iOS UI test unrelated to this diff
(glow overlay on run 1, notification scheduling on run 2), each on a different
parallel simulator clone — and both tests pass in isolation and in a serial
single-destination run. Root cause is environmental, documented in
`.github/workflows/ci.yml`: CI disables parallel test simulator clones for UI
tests (`-parallel-testing-enabled NO
-maximum-concurrent-test-simulator-destinations 1`) plus
`-retry-tests-on-failure` because clone connection timeouts and contention
stall the steps on shared runners. `scripts/test.sh`'s iOS UI phase does not
carry those flags, so its scheme-default parallel clones flake on this busy
machine.

CI-equivalent serial full UI run (`SingleThreadUITests`, single destination):
**passed** (exit 0) — glow, notification, and all four freemium-gate flows
green.

Final verdict is the PR's CI matrix (pending at time of writing) plus the
serial run above; the local UI-phase flake is unrelated to this change (the
diff touches only the cap constant, its references, and the UI-test target's
package link).