# Structure Outline

## Approach

Lower every deployment/package floor from `26.5` to `18.7` across all 5 targets and the Swift
package (no code changes, no feature gating — 18.7 clears every used API floor, iOS 17 max). The
end-to-end proof of safety is `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`: a clean build at 18.7 is the
authoritative evidence that no availability warning fired. The work slices vertically by
*target-origin chain*: change a floor, then run the build/test that exercises that origin, so each
phase is independently green.

> Note on slicing: this design has **no database / service / API / UI layers to cross** — it is a
> configuration-floor change. The vertical axis is therefore *which deployment-target origin moves,
> and which build/test proves that origin is valid at the new floor*. Each phase is independently
> revertible and independently verifiable.

---

## Phase 1: iOS floor — the pristine clean-build proof

Ship the single most important floor (the iOS app) and prove via a warning-free build that 18.7 is
valid for the iOS SwiftUI / Observation / EventKit API surface in use. This is the acceptance proof
everything else builds on.

**Files**: `SingleThread.xcodeproj/project.pbxproj` (`:617`, `:667` — `IPHONEOS_DEPLOYMENT_TARGET`,
Debug+Release for target `SingleThread`), `SingleThreadCore/Package.swift` (`:7` — `.iOS`).

**Key changes**:
- `IPHONEOS_DEPLOYMENT_TARGET = 18.7;` (was `26.5`) — 2 occurrences
- `Package.swift.platforms: [.iOS("18.7"), …]` — iOS floor literal; `.watchOS`/`.macOS` stay `26.5`
  until Phase 3 (keeps this phase a clean single-platform proof)

**Verify**: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
passes with zero Swift availability warnings (warnings-as-errors active). Manually: confirm the
package's `.iOS` equals the target's `IPHONEOS_DEPLOYMENT_TARGET` (`18.7`).

---

## Phase 2: iOS test targets — unit + UI suites at the new floor

Move the test targets so the suites exercise the same 18.7 floor the app targets. Both the unit
suite and the UI/accessibility audit run against the `SingleThread` app at 18.7.

**Files**: `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadTests` `:695`,`:696`,`:720`,`:721`
(`IPHONEOS_DEPLOYMENT_TARGET` + `MACOSX_DEPLOYMENT_TARGET`, Debug & Release); `SingleThreadUITests`
`:744`,`:745`,`:768`,`:769`.

**Key changes**:
- `IPHONEOS_DEPLOYMENT_TARGET = 18.7;` and `MACOSX_DEPLOYMENT_TARGET = 18.7;` (was `26.5`) —
  4 literals per test target
- No package change — `SingleThreadCore` is already `.iOS("18.7")`; package floor stays ≤
  test-target floor, so no SPM `max()` raise is possible.

**Verify**: `xcodebuild test … -only-testing:SingleThreadTests` and
`xcodebuild test … -only-testing:SingleThreadUITests` both pass at Configuration Debug. Manually:
`testAccessibilityAudit()` passes (dynamic type, hit regions, element descriptions, traits).

---

## Phase 3: watchOS + macOS floors (at-risk zone)

Lower the remaining watch + macOS + widget floors. This phase carries the known risk that `18.7` may
be an invalid macOS/watchOS deployment target under Xcode 26.6 — verify each target explicitly and,
where invalid, apply the documented failure fallback (keep macOS/watchOS floors at `26.5`, iOS at
`18.7`). Whatever values land are the ones the Phase 4 guard encodes.

**Files**: `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadWatch` (`:809`,`:837` —
`WATCHOS_DEPLOYMENT_TARGET`); `SingleThreadWidget` (`:853`,`:884` — `IPHONEOS_DEPLOYMENT_TARGET`);
`SingleThreadApp` macOS (`:620`,`:670` — `MACOSX_DEPLOYMENT_TARGET`); `SingleThreadCore/Package.swift`
(`:8`,`:9` — `.watchOS`/`.macOS`).

**Key changes**:
- `WATCHOS_DEPLOYMENT_TARGET = 18.7;` (watch), `IPHONEOS_DEPLOYMENT_TARGET = 18.7;` (widget),
  `MACOSX_DEPLOYMENT_TARGET = 18.7;` (app) — was `26.5`
- `Package.swift` `.watchOS("18.7"), .macOS("18.7")`
- The widget declares `macosx` in `SUPPORTED_PLATFORMS` but sets no `MACOSX_DEPLOYMENT_TARGET`; this
  gap is out of scope (the widget is only built for iOS), not to be "fixed" here.

**Verify**: `xcodebuild -scheme SingleThreadWatch … build` and the macOS build
(`xcodebuild … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`) return clean at 18.7.
Manually: watch faces load on a watch simulator; the macOS menu-bar app shows its window. If a
macOS/watchOS target rejects `18.7`, stop, apply the fallback (keep those floors at `26.5`), record
the settled values, then proceed so the guard encodes exactly that set.

---

## Phase 4: config guard + full CI green

Add the missing consistency mechanism — a fail-fast guard in `scripts/test.sh` that reads every
target's deployment target (16 literals across all 5 targets) and the 3 package floor literals,
asserts each equals `18.7`, and exits `1` with a clear diagnostic on drift. The repo staying green
end-to-end is the acceptance gate.

**Files**: `scripts/test.sh` (new guard step; existing `SIM`/`WATCH_SIM`/`MAC_SIM` unchanged).

**Key changes**:
- `DEPLOYMENT_TARGET := "18.7"` — single source-of-truth constant
- `verify_deployment_target(): Bool` — parse `project.pbxproj` `*_DEPLOYMENT_TARGET` values and
  `Package.swift` `.iOS`/`.watchOS`/`.macOS` literals; return false (hard `exit 1`) naming the
  drifted origin if any ≠ constant. Written in the existing "fail loudly" style that mirrors
  `SWIFT_TREAT_WARNINGS_AS_ERRORS`.

**Verify**: `./scripts/test.sh` (format → swiftlint → build → watch & macOS build → Periphery →
unit → UI/accessibility) passes end-to-end, and the guard reports all 19 origins at `18.7`. Manual:
temporarily set one literal to `18.8` and confirm the guard fails fast naming that target — then
revert.

---

## Testing Checkpoints

- **After Phase 1**: iOS app builds clean at 18.7 (no availability warnings-as-errors); package
  `.iOS` == target `IPHONEOS_DEPLOYMENT_TARGET`; watchOS/macOS still `26.5`.
- **After Phase 2**: unit + UI suites (incl. accessibility audit) pass at 18.7; both test targets
  are at 18.7.
- **After Phase 3**: watchOS + widget + app macOS floors == 18.7 with clean builds — or the isolated
  fallback is forced (iOS stays 18.7, macOS/watchOS stay 26.5); whichever lands is recorded.
- **After Phase 4**: `./scripts/test.sh` green; config guard fails fast on drift; all 16 pbxproj + 3
  package literals settle at `18.7` (resp. the recorded fallback set).