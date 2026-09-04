# Design: name the freemium cap constant

## Decision: where the constant lives

`public static let freemiumCap = 100` on `EntitlementStore`, adjacent to the
existing `static let unlockProductID` ("single source of truth" precedent,
per repo convention).

The audit's Enum Sketch 2 shows the constant inside a full `EntitlementTier`
enum (`.unresolved`/`.freemium(used, cap)`/`.unlimited` + `canMutate`). That
enum replaces `isEntitled` + `completionCounter.count` + the gate — a
behavior refactor explicitly out of scope for this ticket ("Extract
`static let freemiumCap` to a single source of truth", acceptances limited
to literals + boundary semantics). The ticket allows "e.g." placement; the
constant lands on the entitlement domain's existing source-of-truth type.
The per-sketch enum refactor stays deferred.

```swift
public final class EntitlementStore {
    /// The StoreKit product ID for the one-time unlock IAP.
    public static let unlockProductID = "app.alanvardy.SingleThread.unlimited"

    /// The free-tier lifetime-completion cap...
    public static let freemiumCap = 100
}
```

`EntitlementStore` is `@MainActor`; the `static let` inherits that isolation
and is only referenced from `@MainActor` contexts (the gate, the watch
composition root, the test suites, and the `@MainActor` UI-test methods).

## Semantics preserved

Gate stays `count < freemiumCap` (strict `<`): at exactly 100, non-entitled
users are gated. Boundary tests `canMutateTrueWhenCountBelow100AndNotEntitled`
(count 99) and `canMutateFalseWhenCountAt100AndNotEntitled` (count 100) keep
their intent, now expressed via the constant.

## Site-by-site change

| File | Change |
|------|--------|
| `EntitlementStore.swift` | add `public static let freemiumCap = 100` |
| `ReminderStore.swift:143,145` | doc cites `EntitlementStore.freemiumCap`; gate uses it |
| `WatchAppViewModel.swift:27` | `set(EntitlementStore.freemiumCap, ...)` |
| `ReminderStoreGateTests.swift` (6 sites) | `EntitlementStore.freemiumCap` |
| `ReminderStoreTests.swift:591` | `EntitlementStore.freemiumCap` |
| `SingleThreadUITestsFlows.swift` (4 seeds) | JSON interpolates `EntitlementStore.freemiumCap` |
| `SingleThread.xcodeproj/project.pbxproj` | link `SingleThreadCore` into `SingleThreadUITests` |

## UI-test seeds

The four seeds become:

```swift
let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":\#(EntitlementStore.freemiumCap),"isEntitled":false}"#
```

Requires `import SingleThreadCore` and the package link (research.md). Raw
string interpolation `\#(...)` is the raw-string escape — the JSON number
stays unquoted.

## Out of scope / non-changes

* Full `EntitlementTier` enum refactor (Sketch 2) — deferred behavior refactor.
* Non-cap `100` literals (`BackgroundFade` percent math, loop counts, arbitrary
  test fixtures) — untouched.
* Watch UI tests — already literal-free (`--ui-testing-gated` flag).
* `UITestingSeed` wire format — unchanged.