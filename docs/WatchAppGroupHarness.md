# Watch App Group Harness

## Purpose

`SingleThreadWatchTests/AppGroupHarness.swift` and the accompanying
`AppGroupRegistrationTests` / `AppGroupDivergenceTests` prove that the watch
app target is group-registered and that `AppGroup.defaults` and
`UserDefaults.standard` are distinct containers on the watch.

## What It Asserts

| Test | What it proves | Failure means |
|---|---|---|
| `suiteResolvesOnWatch()` | `UserDefaults(suiteName: AppGroup.suiteName) != nil` — registration took effect | Registration does not take effect on watchOS sim (negative finding) |
| `completionCountDivergesBetweenContainers()` | Write to group ≠ visible in `.standard` | No divergence — group and standard are the same container (spike finding) |
| `writingStandardDoesNotLeakIntoGroup()` | Write to `.standard` stays out of group | One-way leak — group is not properly isolated |

## How to Run

```sh
make watch-test
```

All tests run inside `SingleThreadWatchTests` (Swift Testing, hosted in the entitled watch app).

## Negative-Result Recording Procedure

If any probe/divergence test fails:

1. Record the exact failure in `.pi/qrspi/<branch>/` (like the existing
   `q4-findings.md` / `research.md` pattern).
2. State whether the finding is **expected** (e.g. "watchOS sim does not
   support App Groups") or **unexpected** (e.g. "group resolves but no
   divergence — containers are not isolated").
3. Do not proceed with Stages that depend on the failed assertion.

## Adding a New Shared Value to the Divergence Tests

For successor tickets (T1.2, T2.1) that need to verify a new value diverges:

1. Add a seed method to `AppGroupHarness` (mirror `seedCompletionCountInGroup`)
2. Add a clear method to `AppGroupHarness` (mirror `clearCompletionCount`)
3. Add a new `@Test` in `AppGroupDivergenceTests` (mirror
   `completionCountDivergesBetweenContainers`): write to group via harness,
   assert group store sees it, assert `.standard` store does not, assert raw
   `.standard` is nil
4. Optionally add a "does not leak into group" test for bidirectional proof
5. Re-run `make watch-test`

All new test code reads `AppGroup.suiteName` — never hardcode
`"group.app.alanvardy.SingleThread"`.