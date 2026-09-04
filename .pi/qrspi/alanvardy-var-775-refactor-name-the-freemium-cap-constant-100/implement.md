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

Full `./scripts/test.sh` gate runs once after commit (QRSPI gate staging).