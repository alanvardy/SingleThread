# Structure Outline

## Approach

Fix the macOS Settings sheet by adding one small macOS-gated `ViewModifier`
(`SettingsSubscreenLayout`) that forces each pushed sub-view to fill and
top-align (`frame(maxHeight: .infinity, alignment: .top)`), then applying it to
the end of every macOS-reachable Sub-settings `Form`/`List`. iOS compiles the
modifier to a no-op, so the change is zero-risk to the tested iOS surface.
Bottom-up — land and green the modifier in isolation first, then spread it
across the pushed sub-views. (Before Stage 1, reproduce the centering on
`make mac-run` to confirm *content* — not the system nav header itself — is
what centers; the modifier frames the body, so confirm that framing is the
right lever per design.md risk 1/3.)

## Stage 1: `SettingsSubscreenLayout` modifier (foundation)

Deliver a single self-contained layout modifier and prove both of its platform
branches behave in isolation — before any sub-view depends on it.

**Files**:
- `SingleThread/SettingsSubscreenLayout.swift` (new, auto-discovered — no pbxproj edits)
- `SingleThreadTests/SettingsSubscreenLayoutTests.swift` (new)

**Key changes**:
- `struct SettingsSubscreenLayout: ViewModifier` — new type
  - `func body(content: Content) -> some View` — `#if os(macOS)` returns
    `content.frame(maxHeight: .infinity, alignment: .top)`; `#else` returns
    `content` unchanged (no-op)
- `extension View { func settingsSubscreenLayout() -> some View }` — new helper,
  wraps `modifier(SettingsSubscreenLayout())` (next layer consumes this)

**Tests** (`SettingsSubscreenLayoutTests.swift`, Swift Testing, runs on both
platforms via `-only-testing:SingleThreadTests`):
- `settingsSubscreenLayoutTopAlignedOnMacOS` (`#if os(macOS)` in-test) — happy:
  `String(describing:)` of a wrapped view's body contains
  `frame(maxHeight: .infinity, alignment: .top)`
- `settingsSubscreenLayoutIsNoopOnIOS` (`#if os(iOS)` in-test) — sad/negative:
  same wrapped body contains **no** `.frame` modifier and equals the unwrapped
  view (proves the iOS no-op)

**Verify**: `make mac-test` (macOS unit) **and** `make test` (iOS unit) — both
platform branches must compile with `SWIFT_TREAT_WARNINGS_AS_ERRORS` and pass.

---

## Stage 2: Apply to the 7 Form-based sub-views

Spread the proven modifier across every macOS-reachable `Form` sub-view; the
root `NavigationStack`/`List` stays stock.

**Files**:
- `SingleThread/InterfaceSettingsView.swift`, `SingleThread/ReminderSettingsView.swift`,
  `SingleThread/FilterSortSettingsView.swift`, `SingleThread/BackgroundSettingsView.swift`,
  `SingleThread/PrivacySettingsView.swift`, `SingleThread/AboutView.swift`,
  `SingleThread/ExcludedListsView.swift`
- `SingleThreadTests/SettingsViewTests.swift` (extend), `SingleThreadTests/AboutViewTests.swift`
  (extend), and a new `excludedListsViewContainsTopAnchor` test

**Key changes** (per view, one-line change):
- Append `.settingsSubscreenLayout()` to each view's `Form { … }` at end of
  body (after `.navigationTitle(_:)`) — no binding/data-flow change, layout only.

**Tests** (mirror existing `String(describing: view.body)` pattern,
`SettingsViewTests.swift:37`):
- Happy: each of the 7 `…ContainsExpectedRows`-style tests gains an assertion
  that the body string contains `SettingsSubscreenLayout`; add first coverage
  for `ExcludedListsView` (currently untested) and `AboutView` layout.
- Sad/negative: the root `SettingsView` (via `settingsViewContainsNavigationLinkLabels`)
  asserts its body does **not** contain `SettingsSubscreenLayout` — guards
  against accidentally top-anchoring the root `List` (must keep the
  `minHeight: 500` floor behavior).

**Not in this stage**: `PurchaseSettingsView` (List — see Stage 3) and
`NotificationsSettingsView` (its parent row is `#if os(iOS)`
`SettingsView.swift:57-66`, so it is never pushed on macOS — excluded).

**Verify**: `make mac-test` **and** `make test` still green; `make lint` /
`make format` clean.

---

## Stage 3: Apply to `PurchaseSettingsView` (List container)

The one sub-view using `List` instead of `Form` — called out in design.md as the
container most likely to lay out differently, so it lands separately and can be
dropped as a scoped follow-up without blocking Stage 2.

**Files**:
- `SingleThread/PurchaseSettingsView.swift`
- `SingleThreadTests/SettingsViewTests.swift` (extend — first unit coverage of
  this view)

**Key changes**:
- Append `.settingsSubscreenLayout()` to the `List { … }` at
  `PurchaseSettingsView.swift:18` (after `.navigationTitle`).

**Tests**:
- `purchaseSettingsViewContainsTopAnchor` — happy: body string contains
  `SettingsSubscreenLayout`.

**Verify**: `make mac-test` green. Manual: on `make mac-run`, confirm the
Purchase submenu is top-anchored like the others; if the List centers
differently despite the modifier, treat as a scoped follow-up (design.md risk 2)
rather than expanding the change.

---

## Stage 4: Manual visual check + full gate

End-to-end confirmation of the desired end state, plus the single CI-identical
run.

**Files**: none (verification only).

**Key changes**: none.

**Tests** (manual, cannot be CI-automated — no macOS UI target exists):
- `make mac-run` → open each submenu (Interface, Reminder, Filtering & Sorting
  → Excluded Lists, Background, Privacy, About, Purchase) and confirm the
  navigation title + back button sit flush to the top of the card with
  short-form content top-anchored beneath.

**Verify**: full `./scripts/test.sh` run **once by the parent** after phases
commit (formats, lints, builds, Periphery, unit + UI tests). PR states
explicitly that macOS layout is manually verified (design.md decision 5).

---

## Testing Checkpoints

Each line = what must be green before advancing (resume points if context resets):

1. `SettingsSubscreenLayoutTests` green on **both** `make mac-test` and `make test`.
2. All 7 Form sub-view body-string assertions green (`make mac-test` + `make test`), root `SettingsView` still negative-clean.
3. `purchaseSettingsViewContainsTopAnchor` green (`make mac-test`).
4. `make mac-run` visual pass + parent-run `./scripts/test.sh` fully green.

## Cross-cutting note

The modifier is cross-cutting (touches every sub-view), but unlike a
top-layer-only concern it is fully unit-testable *at its own layer*:
body-string asserts prove it's applied, and the only untestable residue —
actual macOS rendering — is scoped to the manual `make mac-run` check, which the
design already accepts (decision 5). No early stub is needed.