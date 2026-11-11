# Implementation Plan

Port CheckStitch's Duo-outer-portrait layout adaptation into SingleThread: a pure,
unit-testable layout policy (`ChecklistLayout`: context → width/inset) plus a pure
detector (`DuoDisplay`) and an app-target adapter (`DuoOuterPortrait`, `uname` machine
identifier + compact-width/regular-height size classes). The reminder card's width cap
and its row gutter — and, in phase 2, the empty-state cards and the AI-sort failure
banner — read the policy, so the iPhone Duo's **outer screen in portrait** gets a
20 pt gutter (was 40) and a `min(340, viewportWidth * 0.8)` cap (was `0.6`). Every other
device, screen and orientation resolves to `ChecklistLayout.Context.standard`, which
returns bit-identical values to today's `CardWidth` / 40 pt gutter.

## Recon facts this plan is built on

Verified this session (re-grep before editing if the tree moved):

- `SingleThread/CardWidth.swift:11-13` — `enum CardWidth { nonisolated static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat { min(340, viewportWidth * 0.6) } }`.
- `SingleThread/EmptyStateCard.swift:43-45` — `static func maxContentWidth(viewportWidth:)` is a one-line wrapper over `CardWidth`. **Only** call sites: `ContentView.swift:434`, `ContentView.swift:449`. It becomes unused in phase 2 and must be deleted (Periphery runs in the gate).
- `SingleThread/ContentView.swift:479` — `maxWidth: CardWidth.maxContentWidth(viewportWidth: geometry.size.width)` on `ReminderCardView`.
- `SingleThread/ContentView.swift:498` — `.padding(.horizontal, 40)` on the reminder-card `List` row. Sits **before** the `#if os(iOS)` at `:499`, so it is shared iOS/macOS chrome.
- `SingleThread/ContentView+iOS.swift:176` — `.padding(.horizontal, 40)` on `aiSortFailureBanner` (the ticket calls this "the iOS header"; it is the AI-sort failure banner, and this is the only `40` in that file). Whole file is inside `#if os(iOS)`.
- `ContentView.swift` is shared iOS/macOS (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`). It has **no** `horizontalSizeClass` / `verticalSizeClass` environment values today, and no Duo detection exists anywhere in the repo.
- Reference values from `../CheckStitch`: machine identifier `"iPhone19,4"`, predicate = known machine **AND** compact width **AND** regular height, gutters 32/16 (ours are 40/20 — the ticket says *halve*), fractions 0.6/0.8 with a shared 340 ceiling, and `0.8` crossover at exactly `425`.
- Test style: Swift Testing (`struct …Tests`, `@Test func name()`, `#expect`), non-`test`-prefixed names (`SingleThreadTests/CardWidthTests.swift`). iOS-only app-target tests use `#if os(iOS)` + `@MainActor` + `@testable import SingleThread` (`SingleThreadTests/AppDelegateTests.swift`).
- No schema, API, persisted-format, EventKit, App Group or StoreKit change. Layout only.
- No Duo simulator on this machine (only `scripts/fixtures/devicectl-devices.json:268` carries `productType: "iPhone19,4"`), so the Duo path is proven by unit tests with an **injected machine string**; the on-device check needs Duo hardware.

Resolved decisions (do not re-open):

1. Gutter `40 → 20` (halve), not CheckStitch's `32 → 16`.
2. Duo width fraction `0.8`, ceiling `340` unchanged. Standard path delegates to `CardWidth` — no duplication of the 0.6 math.
3. The AI-sort failure banner gutter **does** follow the policy (phase 2) so it stays aligned with the card.
4. Empty-state cards **do** follow the policy (phase 2), and `EmptyStateCard.maxContentWidth` is deleted with them.
5. Both new policy/detector files live in `SingleThread/` (app target), not `SingleThreadCore` — tests reach them via `@testable import SingleThread` and `CardWidth` already lives there.

## Concurrency note (applies to phases 1–2)

`SingleThread` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Mirror `CardWidth`: every
pure `static func` / `static let` on the new pure types is marked `nonisolated` so
non-`@MainActor` Swift Testing suites can call it. If the compiler rejects `nonisolated`
on a stored `static let` (immutable `Sendable` statics are already nonisolated), drop the
keyword on that declaration and keep it on the functions. The app-target adapter keeps
its no-machine overload MainActor-isolated and its machine-injecting overload
`nonisolated`. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — any warning fails the build.

---

## Phase 1: Duo outer portrait widens the reminder card end-to-end

Thinnest end-to-end path: the pure policy + detector + app adapter exist, and
`ContentView`'s reminder card and its row gutter read them. On Duo outer portrait the
card becomes wider; every other device/orientation is bit-identical to today.

### Changes

#### 1. Pure layout policy
**File**: `SingleThread/ChecklistLayout.swift`
**Action**: create

```swift
import CoreGraphics

/// Pure layout policy for the checklist/reminder card. `Context.standard`
/// reproduces the pre-Duo layout exactly (see `CardWidth`); the Duo outer
/// portrait variant halves the screen gutter and widens the card cap.
enum ChecklistLayout {
    struct Context: Equatable, Sendable {
        let isDuoOuterPortrait: Bool

        static let standard = Context(isDuoOuterPortrait: false)
    }

    /// Screen gutter around the card. Was a hard-coded 40 before the policy.
    nonisolated static let defaultHorizontalInset: CGFloat = 40
    /// Duo outer portrait halves the gutter so the card gets wider.
    nonisolated static let duoOuterHorizontalInset: CGFloat = 20
    /// The Duo outer screen is narrow, so the card may use more of it.
    nonisolated static let duoOuterWidthFraction: CGFloat = 0.8
    nonisolated static let maxWidthCeiling: CGFloat = 340

    nonisolated static func horizontalInset(_ context: Context) -> CGFloat {
        context.isDuoOuterPortrait ? duoOuterHorizontalInset : defaultHorizontalInset
    }

    /// Standard context delegates to `CardWidth`, so the default path cannot
    /// drift from `min(340, viewportWidth * 0.6)`.
    nonisolated static func maxContentWidth(
        viewportWidth: CGFloat,
        context: Context
    ) -> CGFloat {
        guard context.isDuoOuterPortrait else {
            return CardWidth.maxContentWidth(viewportWidth: viewportWidth)
        }
        return min(maxWidthCeiling, viewportWidth * duoOuterWidthFraction)
    }
}
```

#### 2. Pure Duo display detector
**File**: `SingleThread/DuoDisplay.swift`
**Action**: create

```swift
/// Detects the Duo's outer screen. The machine identifier alone cannot tell the
/// outer display from the inner one, and the outer display rotates, so the match
/// requires the portrait-specific compact-width/regular-height size-class pair.
enum DuoDisplay {
    nonisolated static let outerPortraitMachines: Set<String> = ["iPhone19,4"]

    nonisolated static func isOuterPortrait(
        machine: String,
        isCompactWidth: Bool,
        isRegularHeight: Bool
    ) -> Bool {
        outerPortraitMachines.contains(machine) && isCompactWidth && isRegularHeight
    }
}
```

#### 3. App-target adapter
**File**: `SingleThread/DuoOuterPortrait.swift`
**Action**: create

```swift
import Foundation
import SwiftUI

/// Bridges the platform (`uname` machine identifier + SwiftUI size classes) to the
/// pure `DuoDisplay` / `ChecklistLayout` types. Fails safe to `.standard`: macOS,
/// the simulator, unknown machines and the Duo's inner/landscape displays all
/// resolve to `.standard`.
enum DuoOuterPortrait {
    /// `uname` machine identifier, e.g. "iPhone19,4". Empty where unavailable.
    static let machineIdentifier: String = {
        #if os(iOS)
            var info = utsname()
            guard uname(&info) == 0 else { return "" }
            return withUnsafeBytes(of: &info.machine) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
        #else
            return ""
        #endif
    }()

    /// Test seam: inject the machine identifier instead of reading `uname`.
    nonisolated static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        machine: String
    ) -> ChecklistLayout.Context {
        ChecklistLayout.Context(
            isDuoOuterPortrait: DuoDisplay.isOuterPortrait(
                machine: machine,
                isCompactWidth: horizontal == .compact,
                isRegularHeight: vertical == .regular))
    }

    static func context(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> ChecklistLayout.Context {
        context(horizontal: horizontal, vertical: vertical, machine: machineIdentifier)
    }
}
```

Two distinct signatures (not a default argument) so the MainActor-isolated
`machineIdentifier` is never read from the `nonisolated` overload.

#### 4. Wire the reminder card width + row gutter
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add immediately after `struct ContentView: View {` (`:17`), above the
`// MARK: Lifecycle` init block — environment values are unaffected by the custom inits:

```swift
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
```

Add a computed context next to them. **No access modifier** (`private` would hide it from
the `ContentView+iOS.swift` extension in phase 2; `private` in this file is invisible
across files even within the same type):

```swift
    /// Duo-outer-portrait layout policy. Non-Duo / macOS / simulator resolves to
    /// `.standard`, which reproduces the pre-existing CardWidth + 40pt layout.
    var layoutContext: ChecklistLayout.Context {
        DuoOuterPortrait.context(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }
```

At `:479`, replace `maxWidth: CardWidth.maxContentWidth(viewportWidth: geometry.size.width),` with:

```swift
                                maxWidth: ChecklistLayout.maxContentWidth(
                                    viewportWidth: geometry.size.width,
                                    context: layoutContext),
```

At `:498`, replace `.padding(.horizontal, 40)` with:

```swift
                                .padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))
```

Leave `:434` and `:449` (empty states) untouched in this phase — they still call
`EmptyStateCard.maxContentWidth`.

#### 5. Policy tests
**File**: `SingleThreadTests/ChecklistLayoutTests.swift`
**Action**: create

```swift
import CoreGraphics
@testable import SingleThread
import Testing

struct ChecklistLayoutTests {
    @Test
    func standardContextKeepsTheFortyPointGutter() {
        #expect(ChecklistLayout.horizontalInset(.standard) == 40)
    }

    @Test
    func duoOuterContextHalvesTheGutter() {
        #expect(ChecklistLayout.horizontalInset(.init(isDuoOuterPortrait: true)) == 20)
    }

    /// Anti-drift: the standard path must stay CardWidth at every viewport.
    @Test
    func standardWidthMatchesCardWidthAcrossTheDomain() {
        for width in stride(from: 0.0, through: 1500.0, by: 10.0) {
            #expect(
                ChecklistLayout.maxContentWidth(viewportWidth: width, context: .standard)
                    == CardWidth.maxContentWidth(viewportWidth: width))
        }
    }

    @Test
    func standardContextPreservesTheSixtyPercentCap() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 200, context: .standard) == 120)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 1000, context: .standard) == 340)
    }

    @Test
    func duoOuterWidthUsesTheLargerFractionBelowTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 200, context: .init(isDuoOuterPortrait: true)) == 160)
    }

    @Test
    func duoOuterWidthClampsAtTheCeiling() {
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 466, context: .init(isDuoOuterPortrait: true)) == 340)
    }

    /// Sad/boundary path: 425 is the exact 340 / 0.8 crossover.
    @Test
    func duoOuterWidthBoundaryIsFourTwentyFive() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 425, context: duo) == 340)
        #expect(abs(ChecklistLayout.maxContentWidth(viewportWidth: 424.9, context: duo) - 339.92) < 0.0001)
    }

    /// A safe-area-adjusted Duo outer viewport: the card must not exceed it.
    @Test
    func duoOuterWidthFitsTheSafeAreaAdjustedViewport() {
        let duo = ChecklistLayout.Context(isDuoOuterPortrait: true)
        #expect(abs(ChecklistLayout.maxContentWidth(viewportWidth: 382, context: duo) - 305.6) < 0.0001)
    }

    @Test
    func widthIsNonNegativeAtZeroViewport() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 0, context: .standard) == 0)
        #expect(ChecklistLayout.maxContentWidth(
            viewportWidth: 0, context: .init(isDuoOuterPortrait: true)) == 0)
    }
}
```

#### 6. Detector tests
**File**: `SingleThreadTests/DuoDisplayTests.swift`
**Action**: create

```swift
@testable import SingleThread
import Testing

struct DuoDisplayTests {
    @Test
    func knownMachineInOuterPortraitIsRecognised() {
        #expect(DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: true))
    }

    /// Sad: the Duo's inner display is regular width.
    @Test
    func knownMachineWithRegularWidthIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: false, isRegularHeight: true))
    }

    /// Sad: the Duo's outer landscape is compact height.
    @Test
    func knownMachineWithCompactHeightIsNotOuterPortrait() {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: "iPhone19,4", isCompactWidth: true, isRegularHeight: false))
    }

    @Test
    func otherMachinesAreNeverRecognised() {
        for machine in ["iPhone17,1", "iPad13,1", "", "arm64"] {
            #expect(!DuoDisplay.isOuterPortrait(
                machine: machine, isCompactWidth: true, isRegularHeight: true))
        }
    }

    @Test(arguments: ["iPhone19,4", "iPhone17,1", "", "iPad13,1"])
    func sizeClassMatrixFiresOnlyForKnownMachine(machine: String) {
        for horizontal in [true, false] {
            for vertical in [true, false] {
                #expect(DuoDisplay.isOuterPortrait(
                    machine: machine, isCompactWidth: horizontal, isRegularHeight: vertical)
                    == (machine == "iPhone19,4" && horizontal && vertical))
            }
        }
    }

    /// Sad: whitespace / newline / lowercase identifiers must not match.
    @Test(arguments: ["iPhone19,4 ", "iPhone19,4\n", "iphone19,4"])
    func malformedMachinesAreNotOuterPortrait(machine: String) {
        #expect(!DuoDisplay.isOuterPortrait(
            machine: machine, isCompactWidth: true, isRegularHeight: true))
    }
}
```

#### 7. Adapter tests
**File**: `SingleThreadTests/DuoOuterPortraitTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct DuoOuterPortraitTests {
    @Test
    func duoMachineInCompactRegularIsDuoOuter() {
        let context = DuoOuterPortrait.context(
            horizontal: .compact, vertical: .regular, machine: "iPhone19,4")
        #expect(context == .init(isDuoOuterPortrait: true))
    }

    /// Sad: the Duo's inner display must not change the layout.
    @Test
    func duoMachineInRegularRegularIsStandard() {
        let context = DuoOuterPortrait.context(
            horizontal: .regular, vertical: .regular, machine: "iPhone19,4")
        #expect(context == .standard)
    }

    /// Sad: a non-Duo phone in the same size classes must not change the layout.
    @Test
    func nonDuoMachineInCompactRegularIsStandard() {
        let context = DuoOuterPortrait.context(
            horizontal: .compact, vertical: .regular, machine: "iPhone17,1")
        #expect(context == .standard)
    }

    /// Fail-safe: the macOS / unknown-machine path.
    @Test
    func emptyMachineIsStandard() {
        #expect(DuoOuterPortrait.context(horizontal: .compact, vertical: .regular, machine: "")
            == .standard)
        #expect(DuoOuterPortrait.context(horizontal: nil, vertical: nil, machine: "iPhone19,4")
            == .standard)
    }

    @Test
    func machineIdentifierIsReadable() {
        #if os(iOS)
            #expect(!DuoOuterPortrait.machineIdentifier.isEmpty)
            #expect(!DuoOuterPortrait.machineIdentifier.contains("\n"))
        #else
            #expect(DuoOuterPortrait.machineIdentifier.isEmpty)
        #endif
    }
}
```

### Verification

#### Automated
- [x] `make format` (SwiftFormat + SwiftLint autofix) leaves no diff beyond this phase's files
- [x] `make lint` passes (`swiftformat --lint …` + `swiftlint lint --strict`, no warnings)
- [x] `make build` succeeds (SIM pinned from `.simulator_id`; `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`)
- [x] `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/DuoDisplayTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/CardWidthTests` still passes (default path untouched)
- [x] Grep guard: `rg -n "padding\(\.horizontal, 40\)|CardWidth.maxContentWidth" SingleThread/ContentView.swift` shows no remaining `40` on the reminder row and no remaining `CardWidth.` in that file

#### Manual
- [ ] Boot this worktree's simulator (`simctl boot <UDID from .simulator_id>`), install and launch: the reminder card looks exactly as before — card width `min(340, viewportWidth * 0.6)`, 40 pt gutters, no layout shift
- [ ] Rotate to landscape: unchanged
- [ ] Preview (`#Preview`) of `ContentView` still renders the card correctly (the new environment values default to nil → `.standard`)

---

## Phase 2: Empty states and the AI-sort banner follow the same policy

Completes the Duo outer screen: with zero or many reminders the card is the same width,
and the AI-sort failure banner's gutter matches the card's gutter.

### Changes

#### 1. Empty-state call sites
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Replace both occurrences of:

```swift
                        maxWidth: EmptyStateCard.maxContentWidth(viewportWidth: geometry.size.width))
```

(`:434` inside `case .allDone:`, `:449` inside `case .empty(hasHidden):` — keep each
site's indentation) with:

```swift
                        maxWidth: ChecklistLayout.maxContentWidth(
                            viewportWidth: geometry.size.width,
                            context: layoutContext))
```

#### 2. Delete the now-unused wrapper
**File**: `SingleThread/EmptyStateCard.swift`
**Action**: modify

Delete the `static func maxContentWidth(viewportWidth:)` declaration and its doc comment
(`:37-44`). Nothing else references it once the two call sites above are converted, and
Periphery runs in the gate — a leftover unused declaration fails the branch.

#### 3. AI-sort failure banner gutter
**File**: `SingleThread/ContentView+iOS.swift`
**Action**: modify

At `:176`, replace `.padding(.horizontal, 40)` with:

```swift
            .padding(.horizontal, ChecklistLayout.horizontalInset(layoutContext))
```

This is the banner's outer gutter only; the inner `.padding(.horizontal, 20)` /
`(.horizontal, 16)` (label + button padding, `:168` / `:175`) are unchanged. The
extension may read `layoutContext` because it is declared without an access modifier in
phase 1.

#### 4. Standard-path regression test across real viewports
**File**: `SingleThreadTests/ChecklistLayoutTests.swift`
**Action**: modify

Add one test asserting the standard context reproduces the legacy layout at the widths
this app actually sees (iPhone 17 portrait, Duo outer portrait and landscape, iPad):

```swift
    /// The three converted call sites must be bit-identical to the legacy layout on
    /// every non-Duo viewport, including the iPad.
    @Test
    func standardContextMatchesLegacyLayoutAtRealViewports() {
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 402, context: .standard) == 241.2)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 382, context: .standard) == 229.2)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 874, context: .standard) == 340)
        #expect(ChecklistLayout.maxContentWidth(viewportWidth: 1024, context: .standard) == 340)
        #expect(ChecklistLayout.horizontalInset(.standard) == 40)
    }
```

No new *logic* is introduced in this phase — it reuses phase 1's tested policy at the
remaining call sites, so the new test pins the standard path at realistic widths. Say so
in the PR rather than adding a UI test: the Duo geometry cannot be produced on a
simulator (the detector reads `uname`), so a UI test would exercise the standard path
only — value already covered by these unit tests.

### Verification

#### Automated
- [x] `make format` then `make lint` pass
- [x] `make build` succeeds
- [x] `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` passes (includes the new real-viewport test)
- [x] `scripts/test-one.sh SingleThreadTests/CardWidthTests` still passes
- [x] `make periphery` reports no unused `EmptyStateCard.maxContentWidth` / new symbol (clean `DerivedData/` first — the index goes stale after a branch switch)
- [x] `rg -n "horizontal, 40|EmptyStateCard.maxContentWidth" SingleThread/` returns nothing

#### Manual
- [ ] Fill the list with no reminders (`.allDone`) and with hidden-only reminders (`.empty`): the empty-state card is unchanged on a non-Duo simulator
- [ ] Force the AI-sort failure banner (`appViewModel.retryAIRanking()` path or the existing UI-test seam): its 40 pt gutter is unchanged on a non-Duo simulator
- [ ] On a physical iPhone Duo (hardware-dependent — no Duo simulator exists): outer screen in **portrait** shows the card at `min(340, viewportWidth * 0.8)` with 20 pt gutters and the banner aligned to the card; the **inner** screen and **outer landscape** are unchanged at 40 pt / 0.6 cap. If hardware is unavailable, record that in the PR completion artifact and treat the unit tests as the authority
- [ ] Full CI-identical gate (`./scripts/test.sh` via the `run-gate` skill) runs ONCE after both phases are committed

---

## Out of scope

- No refactor of `CardWidth` (it stays the standard-path single source of truth).
- No change to `ReminderCardView`, `EmptyStateCard` internals, list chrome, or vertical padding.
- No new dependencies, no schema or persisted-format change, no launch-arg seam for forcing the Duo context.
- No `SingleThreadWatch` / widget changes — the detector returns `.standard` there and those targets are untouched.
- Remove the `DELETEME` marker file (`git rm DELETEME`) before the branch merges.
