# Plan: name the freemium cap constant

Single phase — small, fully-specified refactor; all sites enumerated in
research.md.

## Phase 1: Implementation

1. **Constant**: add `public static let freemiumCap = 100` to
   `EntitlementStore.swift` (doc: what it is, strict-`<` note).
2. **Gate**: `ReminderStore.swift:145` → `completionCounter.count <
   EntitlementStore.freemiumCap`; fix doc comment at `:143`.
3. **Watch seam**: `WatchAppViewModel.swift:27` →
   `AppGroup.defaults.set(EntitlementStore.freemiumCap, forKey: "completionCount")`.
4. **Unit tests**: `ReminderStoreGateTests.swift` (25, 31, 45, 58, 83, 132)
   and `ReminderStoreTests.swift:591` → `EntitlementStore.freemiumCap`.
5. **UI tests**: link `SingleThreadCore` into the `SingleThreadUITests` target
   (pbxproj: one `PBXBuildFile` + Frameworks-phase entry +
   `packageProductDependencies`) and interpolate the constant into the four
   seed JSON strings (`\#(EntitlementStore.freemiumCap)`).
6. **Housekeeping**: remove the `DELETEME` branch placeholder.

## Phase 2: Verification (targeted, before commit)

- `make format` and `make lint` (SwiftFormat + SwiftLint `--strict`).
- Debug build of iOS app target (warnings-as-errors).
- Targeted suites: `SingleThreadTests` (unit — gate + boundary) and
  `SingleThreadUITests` freemium-gate flows (`-only-testing:`).

## Phase 3: Full gate (once, after commit)

- `./scripts/test.sh` — the single full CI-identical gate (formats, lints,
  builds iOS + watchOS + widget, Periphery, unit + UI tests).
- Push branch; PR #146 moves towards review (acceptance criteria in
  `implement.md`).

## Acceptance checklist

- [ ] zero bare `100` literals referencing the cap (grep across targets)
- [ ] boundary tests (99 vs 100) still pass with strict-`<` preserved
- [ ] all four UI-test freemium-gate flows still pass
- [ ] no behavior change: `git diff` restricted to literals/doc/constants
- [ ] watch UI-tests unaffected (`--ui-testing-gated` seam still sets the cap)