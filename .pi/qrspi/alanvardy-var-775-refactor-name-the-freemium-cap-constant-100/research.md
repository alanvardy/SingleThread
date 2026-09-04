# Research: freemium cap literal inventory

Consolidated from the VAR-759 audit (research already completed; this ticket is
its T4.1 action item). Auditable evidence: `clusters.md` Cluster 3
(no-named-constant literal inventory), `enums.md` Sketch 2, `findings.md` T4.1.

## Every `100` literal that references the cap

Verified against the current tree with `rg -n "\b100\b"` across all targets:

| Site | Line | Current text |
|------|------|--------------|
| `SingleThreadCore/.../ReminderStore.swift` | 143 | doc comment: `free-tier completion cap (100)` |
| `SingleThreadCore/.../ReminderStore.swift` | 145 | `entitlementStore.isEntitled \|\| completionCounter.count < 100` |
| `SingleThreadWatch/WatchAppViewModel.swift` | 27 | `AppGroup.defaults.set(100, forKey: "completionCount")` (watch `--ui-testing-gated` seam) |
| `SingleThreadTests/ReminderStoreGateTests.swift` | 25, 31 | `makeStore(count: 100, entitled: false/true)` |
| `SingleThreadTests/ReminderStoreGateTests.swift` | 45, 83, 132 | `seededCounter(100)` |
| `SingleThreadTests/ReminderStoreGateTests.swift` | 58 | `#expect(counter.count == 100) // unchanged` |
| `SingleThreadTests/ReminderStoreTests.swift` | 591 | `UserDefaults.standard.set(100, forKey: key)` (undo-gated test) |
| `SingleThreadUITests/SingleThreadUITestsFlows.swift` | 640, 662, 674, 701 | seed JSON `"completionCount":100` |

## `100` literals that are NOT cap references (leave alone)

* `SingleThread/BackgroundFade.swift:25` — percent math (`/ 100`)
* `SingleThreadTests/CompletionGlowTests.swift:35` — loop count (`0 ..< 100`)
* `SingleThreadTests/CompletionCounterStoreTests.swift:92, 94` — arbitrary
  counter set/get fixture (not gating semantics)
* `SingleThreadTests/UITestingSeedTests.swift:42, 46` — arbitrary parser
  round-trip value (tests generic int decoding, not the gate)

The watch UI tests contain no `100` literal at all — they drive the gate
through the `--ui-testing-gated` flag, which resolves to
`WatchAppViewModel.swift:27`.

## Placement

Enum Sketch 2 (`enums.md:55-90`) proposes a full `EntitlementTier` enum
(`unresolved` / `freemium(used, cap)` / `unlimited` + `canMutate`) that would
replace `isEntitled`/`hasResolvedEntitlement`/`completionCounter.count`. That
is a behavior refactor beyond this ticket's scope. Its "Constants extract"
(`extension EntitlementTier { static let freemiumCap = 100 }`) degrades
naturally to the existing single-source-of-truth type for the entitlement
domain: `EntitlementStore` already owns `static let unlockProductID` and the
repo convention names it as the entitlement source of truth. Putting the
constant there satisfies "single source of truth" without inventing an
empty enum.

## UI-test dependency gap

`SingleThreadUITests` currently links no package and imports only XCTest (the
five targets that link `SingleThreadCore` are app, widget, watch, unit tests,
watch unit tests). For the four UI-test seeds to reference the constant, the
UI-test target must link `SingleThreadCore` (same local-package product the
app and unit tests use; pbxproj gains one `PBXBuildFile` in the target's
Frameworks phase plus one `packageProductDependencies` entry — no new
object IDs beyond one build file).