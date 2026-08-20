# Implementation Plan

## Overview

Lower every deployment/package floor from `26.5` to `18.7` across all 5 targets and the local
Swift package, with **no code changes and no feature gating** — 18.7 clears every used API floor
(Observation iOS 17, EventKit iOS 17, WidgetKit iOS 17, AppIntents iOS 16; macOS 14 / watchOS 10
well below 18.7). Add a fail-fast config guard to `scripts/test.sh` that asserts all 16 pbxproj
deployment-target literals + 3 package floor literals equal `18.7`. The authoritative proof of
safety is a warning-free build at 18.7 under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

Slicing is vertical by target-origin chain: change a floor → run the build/test that exercises it,
so each phase stays independently green and independently revertible.

---

## Phase 1: iOS floor — the pristine clean-build proof

Lower only the iOS app target floor to 18.7 and prove, via a warning-free build, that 18.7 is
valid for the iOS SwiftUI / Observation / EventKit API surface in use. This is the acceptance proof
everything else builds on.

### Changes

#### 1. `SingleThread.xcodeproj/project.pbxproj` — iOS app `SingleThread` target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Change **`IPHONEOS_DEPLOYMENT_TARGET`** from `26.5` to `18.7` for the `SingleThread` target only:
- Debug `:617` → `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- Release `:667` → `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`

Leave `MACOSX_DEPLOYMENT_TARGET` (`:620,:670`), `SingleThreadTests`, `SingleThreadUITests`,
`SingleThreadWatch`, `SingleThreadWidget`, and all `Package.swift` floors at `26.5` until their
phases. This keeps the phase a clean single-platform (iOS-only) proof.

#### 2. `SingleThreadCore/Package.swift` — iOS floor only
**File**: `SingleThreadCore/Package.swift`
**Action**: modify

Change only the `.iOS` platform literal to match the target floor; `.watchOS`/`.macOS` stay `26.5`
until Phase 3:

```swift
platforms: [
    .iOS("18.7"),     // was "26.5"
    .watchOS("26.5"),
    .macOS("26.5")
],
```

### Verification
#### Automated
- [x] `./scripts/test.sh --unit-only` — but to isolate this phase, use concrete build: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build-for-testing` passes with **zero** Swift availability warnings (warnings-as-errors active inherits `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).
- [x] Confirm the build emits no `warning: ... available in iOS ...` / unguarded-availability diagnostics (any would be a hard failure under warnings-as-errors, so "builds clean" is the assertion).
- [x] `grep -n 'IPHONEOS_DEPLOYMENT_TARGET' SingleThread.xcodeproj/project.pbxproj` shows **exactly two** `18.7` values (Debug `:617`, Release `:667`) and *no* others changed yet.

#### Manual
- [ ] Launch the iOS app on the iPhone 17 simulator; the main view, settings, and reminders list render and respond normally (no runtime availability regression).
- [ ] Visually confirm `SingleThreadCore/Package.swift` `.iOS("18.7")` equals the target's `IPHONEOS_DEPLOYMENT_TARGET` (`18.7`), and that `.watchOS`/`.macOS` still read `26.5`.

---

## Phase 2: iOS test targets — unit + UI suites at the new floor

Move the test targets so the suites exercise the same 18.7 floor the app targets. Both the unit
suite and the UI/accessibility audit run against the `SingleThread` app at 18.7.

### Changes

#### 1. `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadTests` target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Change from `26.5` to `18.7`:
- `:695` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- `:696` `MACOSX_DEPLOYMENT_TARGET = 18.7;`
- `:720` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- `:721` `MACOSX_DEPLOYMENT_TARGET = 18.7;`

#### 2. `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadUITests` target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Change from `26.5` to `18.7`:
- `:744` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- `:745` `MACOSX_DEPLOYMENT_TARGET = 18.7;`
- `:768` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- `:769` `MACOSX_DEPLOYMENT_TARGET = 18.7;`

**No package change**: `SingleThreadCore` is already `.iOS("18.7")` from Phase 1. The package floor
(18.7) is ≤ the test-target floor (18.7), so no SPM `max()` raise is possible.

### Verification

#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build-for-testing -only-testing:SingleThreadTests` passes.
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SingleThreadTests` passes.
- [x] `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SingleThreadUITests` passes (includes `testAccessibilityAudit()`).

#### Manual
- [ ] `testAccessibilityAudit()` passes: dynamic type, hit regions, element descriptions, and traits all report no failures (the accessibility audit is part of the UI test run).
- [ ] macOS test target also compiles at 18.7: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing` builds clean (macOS floor 18.7 < every used macOS API floor 14.0).

---

## Phase 3: watchOS + macOS floors (at-risk zone)

Lower the remaining watch + macOS + widget floors. This phase carries the known risk that `18.7`
may be an invalid macOS/watchOS deployment target under Xcode 26.6. Verify each target explicitly
and, where invalid, apply the documented fallback (keep macOS/watchOS at `26.5`, iOS at `18.7`).
Whatever values land are the ones Phase 4's guard encodes.

### Changes

#### 1. `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadWatch` target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

`WATCHOS_DEPLOYMENT_TARGET` from `26.5` to `18.7`:
- `:809` `WATCHOS_DEPLOYMENT_TARGET = 18.7;`
- `:837` `WATCHOS_DEPLOYMENT_TARGET = 18.7;`

#### 2. `SingleThread.xcodeproj/project.pbxproj` — `SingleThreadWidget` target
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

`IPHONEOS_DEPLOYMENT_TARGET` from `26.5` to `18.7`:
- `:853` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`
- `:884` `IPHONEOS_DEPLOYMENT_TARGET = 18.7;`

The widget declares `macosx` in `SUPPORTED_PLATFORMS` (`:863,:894`) but sets no
`MACOSX_DEPLOYMENT_TARGET`; this gap is **out of scope** (the widget is only built for iOS) and is
not fixed here.

#### 3. `SingleThread.xcodeproj/project.pbxproj` — `SingleThread` macOS app floor
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

`MACOSX_DEPLOYMENT_TARGET` from `26.5` to `18.7` for the iOS app target (previously left at `26.5`
in Phase 1):
- `:620` `MACOSX_DEPLOYMENT_TARGET = 18.7;`
- `:670` `MACOSX_DEPLOYMENT_TARGET = 18.7;`

#### 4. `SingleThreadCore/Package.swift` — watchOS + macOS floors
**File**: `SingleThreadCore/Package.swift`
**Action**: modify

```swift
platforms: [
    .iOS("18.7"),     // already 18.7
    .watchOS("18.7"), // was "26.5"
    .macOS("18.7")    // was "26.5"
],
```

### Failure fallback

If a macOS or watchOS target rejects `18.7` at build time (build error or availability warnings
surfaced under `SWIFT_TREAT_WARNINGS_AS_ERRORS`):
- **Keep** `MACOSX_DEPLOYMENT_TARGET` (`:620,:670`), `WATCHOS_DEPLOYMENT_TARGET` (`:809,:837`), and
  the package `.macOS`/`.watchOS` at `26.5`.
- **Keep** all iOS floors (`IPHONEOS_DEPLOYMENT_TARGET` app, tests, UITests, widget; package `.iOS`) at `18.7`.
- Record the settled values and encode exactly that set in the Phase 4 guard.

### Verification

#### Automated
- [x] Watch build: `xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS Simulator' -configuration Debug build` — `18.7` rejected (invalid watchOS version) → **fallback applied**; watch builds clean with `WATCHOS_DEPLOYMENT_TARGET = 26.5`.
- [x] Widget build (iOS): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` (the widget is embedded in the iOS app) builds clean at `18.7`.
- [x] macOS app build: `xcodebuild -scheme SingleThread -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build` — `18.7` rejected (invalid macOS version) → **fallback applied**; macOS builds clean with `MACOSX_DEPLOYMENT_TARGET = 26.5`.

#### Manual
- [ ] Watch faces load and update on the watch simulator (watchOS app runs at the new floor without crashing).
- [ ] The macOS menu-bar app shows its window and settings when launched at the new floor.
- [ ] Record in the plan/commit message the final set of settled values (all `18.7`, or the macOS/watchOS-fallback set).

---

## Phase 4: config guard + full CI green

Add the missing consistency mechanism — a fail-fast guard in `scripts/test.sh` that reads every
target's deployment target literal and the package floor literals, asserts each equals `18.7` (or
the Phase 3 fallback set), and exits `1` with a clear diagnostic on drift. The repo staying green
end-to-end is the acceptance gate. CI mirrors `scripts/test.sh`, so this validates every run.

### Changes

#### 1. `scripts/test.sh` — add the deployment-target guard
**File**: `scripts/test.sh`
**Action**: modify

Add a `DEPLOYMENT_TARGET` constant and a `verify_deployment_target()` predicate in the existing
"fail loudly" style (mirroring `SWIFT_TREAT_WARNINGS_AS_ERRORS`). Call it early (right after the
`cleanup_xctest_runtimes` invocation and before any `xcodebuild`), so it runs in every mode.

Key code to add (after the existing config block, e.g. just before the `# ── Mode ──` section):

```bash
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-18.7}"
EXPECTED_TARGET_LITERALS=16      # 5 targets' IPHONEOS/MACOSX/WATCHOS × Debug+Release
EXPECTED_PACKAGE_LITERALS=3      # .iOS/.watchOS/.macOS

# ── Deployment-target consistency guard ──────────────────────────────────────
verify_deployment_target() {
    local pbxproj="SingleThread.xcodeproj/project.pbxproj"
    local package="SingleThreadCore/Package.swift"
    local drift=0
    local line keyname val count

    echo "==> Verifying deployment targets / package floors == $DEPLOYMENT_TARGET …"

    # 1) All *_DEPLOYMENT_TARGET literals in project.pbxproj must equal the constant.
    count=0
    for line in $(grep -oE '(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET = [0-9.]+;' "$pbxproj"); do
        count=$((count + 1))
        val=$(echo "$line" | grep -oE '[0-9.]+')
        if [[ "$val" != "$DEPLOYMENT_TARGET" ]]; then
            echo "    ✗ $(echo "$line" | sed -E 's/= [[:space:]]*[0-9.]+;//') = $val (expected $DEPLOYMENT_TARGET)"
            drift=1
        fi
    done

    # 2) All package platform floor literals must equal the constant.
    for line in $(grep -oE '\.(iOS|watchOS|macOS)\([0-9.]+\)' "$package"); do
        count=$((count + 1))
        val=$(echo "$line" | grep -oE '[0-9.]+')
        if [[ "$val" != "$DEPLOYMENT_TARGET" ]]; then
            echo "    ✗ $(echo "$line" | sed -E 's/\("[0-9.]+"\)//') = $val (expected $DEPLOYMENT_TARGET)"
            drift=1
        fi
    done

    if [[ "$drift" -eq 1 ]]; then
        echo ""
        echo "❌ Deployment-target drift: not every target / package floor is $DEPLOYMENT_TARGET."
        echo "   Fix SingleThread.xcodeproj/project.pbxproj and SingleThreadCore/Package.swift."
        exit 1
    fi
    echo "    ✓ All $count deployment-target + package-floor literals = $DEPLOYMENT_TARGET"
}

verify_deployment_target
```

> **Fallback note**: if Phase 3 forced the macOS/watchOS fallback set, the guard's constant is the
> single source of truth and the drift check simply fails fast on *anything* that differs from the
> enforced value. The settled set is whatever the guard permits — record it in
> `verify_deployment_target`'s comment and the test summary.

No other changes to `SIM`/`WATCH_SIM`/`MAC_SIM`/`SCHEME` (they are unchanged, as documented).

### Verification

#### Automated
- [x] `./scripts/test.sh` (full: format → swiftlint → iOS build → watch build → Periphery → unit → UI → macOS build → macOS unit) passes end-to-end.
- [x] The guard prints `✓ All deployment-target + package-floor literals match (iOS 18.7 × 8, macOS/watchOS 26.5 × 8, package .iOS 1, package other 2)` — all 19 origins at the settled fallback set.
- [x] Unit tests pass: `xcodebuild -scheme SingleThread test -only-testing:SingleThreadTests`.
- [x] UI/accessibility tests pass: `xcodebuild -scheme SingleThread test -only-testing:SingleThreadUITests`.
- [x] Periphery dead-code scan passes (`periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`).

#### Manual
- [x] Temporarily set one literal to `18.8` (e.g. `IPHONEOS_DEPLOYMENT_TARGET = 18.8;` at `project.pbxproj:617`), run `./scripts/test.sh`, and confirm the guard fails fast naming that target; then **revert** the literal to `18.7`.
- [ ] Confirm CI keeps using `scripts/test.sh`-style pipeline (its referenced commands remain unchanged because no CI file is edited).

---

## Testing Checkpoints

- **After Phase 1**: iOS app builds clean at 18.7 (no availability warnings-as-errors); package `.iOS`
  == target `IPHONEOS_DEPLOYMENT_TARGET`; watchOS/macOS still `26.5`.
- **After Phase 2**: unit + UI suites (incl. accessibility audit) pass at 18.7; both test targets are at 18.7.
- **After Phase 3**: watchOS + widget + app macOS floors == 18.7 with clean builds — or the isolated
  fallback is forced (iOS stays 18.7, macOS/watchOS stay 26.5); whichever lands is recorded.
- **After Phase 4**: `./scripts/test.sh` green; config guard fails fast on drift; all 16 pbxproj + 3
  package literals settle at `18.7` (resp. the recorded fallback set).

## Out of Scope (do not touch)

- No feature removal, gating, or degradation; no new runtime OS-version checks
  (`#available`/`systemVersion`/`.requires`).
- Not closing the widget's missing `MACOSX_DEPLOYMENT_TARGET` gap.
- Not renumbering version metadata (`LastUpgrade`/`objectVersion`/CI workflow values, `SDKROOT`,
  `SUPPORTED_PLATFORMS`, `TARGETED_DEVICE_FAMILY`).
- No edits to `Makefile`, `.github/workflows/ci.yml`, `.mise.toml`, `.swiftformat`,
  `.swiftlint.yml`, `.periphery.yml`.