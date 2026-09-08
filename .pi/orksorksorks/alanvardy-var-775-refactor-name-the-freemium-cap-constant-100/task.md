# Task: Refactor — name the freemium cap constant (100)

**Source**: VAR-759 state audit — T4.1. Prioritized Action List item 10.
**Linear**: [VAR-775](https://linear.app/vardy/issue/VAR-775/refactor-name-the-freemium-cap-constant-100)

The freemium cap `100` is a bare literal scattered across 7+ sites with no named
constant, and the boundary is strict `<` (the gate closes at exactly 100):

* `ReminderStore.swift:145` (`canMutate = isEntitled || count < 100`)
* `WatchAppViewModel.swift:27` (seed seam gate)
* `ReminderStoreGateTests.swift:25, 31, 45, 58, 83, 132`
* `ReminderStoreTests.swift:591`
* `SingleThreadUITestsFlows.swift:640, 662, 674, 701`

**Goal**: Extract `static let freemiumCap = 100` to a single source of truth
(on the entitlement domain type, per Enum Sketch 2 in `enums.md`). Update all
referencing tests to use the constant. Preserve strict-`<` semantics — the
gate closes at exactly 100.

**Acceptance**: zero bare `100` literals referencing the cap; boundary tests
(99 vs 100) still hold.