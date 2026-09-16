# Implementation Plan

## Overview

The floors (iOS 17.0 / watchOS 11.0 / macOS 26.5) are already landed on this
branch by `53124c3e`, but they are **unproven**: no red-probe evidence, no run
on an older runtime, no artifact record. This plan converts the landed values
into *evidence*: per-platform red probes at the boundary below the floor, real
build/run verification on an actual iOS 17.x and watchOS 11.x runtime, and one
gate hardening change so per-platform literal drift is detected. The only
production file that changes is `scripts/test.sh` (Phase 3); every floor edit in
Phases 1–2 is temporary and restored with `git checkout --`.

**Artifact directory** (all logs referenced below live here and are committed):
`.pi/orksorksorks/alanvardy-var-1014-lower-deployment-targets-from-ios-187watchos-265-to-the/`

**Standing rules for all phases**
- Toggle floors with `perl -pi -e`, **never** by hand-editing pbxproj.
- After every probe: `git checkout -- SingleThread.xcodeproj/project.pbxproj SingleThreadCore/Package.swift`
  and confirm `git status --short` shows no floor files modified before the next step.
- Probe output is captured with `2>&1 | tee <artifact_directory>/<log>` — the raw
  compiler output is the evidence; a truncated/`tail`-only log does not count.
- Never leave the tree carrying a probe value. Never advance on a red checkpoint.
- One `xcodebuild` at a time (AGENTS.md). On `Busy`/`RequestDenied`, see the
  `simulator-pairing` skill.

---

## Phase 1: Walking skeleton — prove the iOS 17.0 floor with the red-probe ladder, on a real iOS 17.x simulator

**Outcome**: the central claim is evidence, not annotation. With iOS floors
temporarily at 16.0 the build fails with availability errors naming the pinning
API; with the landed 17.0 the app builds, installs and runs on an actual iOS
17.x runtime. If 16.0 unexpectedly compiles, that is a finding to report (the
true floor is lower), not to hide.

### Changes

#### 1. Runtime prerequisite (no file edit)

**Action**: download + create the iOS 17.x device, record its UDID.

Locally only **iOS 26.5 / 27.0** runtimes exist
(`xcrun simctl list runtimes`), so `iPhone 17`-class devices cannot serve this
verification and the runtime must be fetched first.

```bash
# 1. Download the lowest available iOS 17.x runtime (Xcode 27 accepts -buildVersion)
xcodebuild -downloadPlatform iOS -buildVersion 17.5
xcrun simctl list runtimes | grep -i 'iOS 17'     # note the runtime identifier

# 2. Create a pre-iPhone-17 device on it (device types iPhone 15/16 and
#    iPhone SE (3rd generation) are present in Xcode 27's device-type list)
xcrun simctl create "Probe iPhone 15 (17.5)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15 \
  com.apple.CoreSimulator.SimRuntime.iOS-17-5      # <- exact id from step 1
xcrun simctl boot <UDID> && xcrun simctl bootstatus <UDID> -b
```

Record the UDID in `probe-runtimes.md` in the artifact directory, e.g.
`IOS17_SIM='platform=iOS Simulator,id=<UDID>'` (used verbatim in later commands).

**Fallback (must be named, not hidden)**: if `-downloadPlatform` cannot serve a
17.x build and no `.dmg` can be imported (`xcrun simctl runtime add <dmg>`),
fall back to the strongest *available* pre-26 runtime, record it in
`probe-runtimes.md` as a **named verification gap**, and state the gap in the PR
body (Phase 3). Do **not** touch `.simulator_id` (`BFB5C8FB-…BF4E6` is this
worktree's 26.5/27.0 device and must stay).

#### 2. Probe 1a — gate still bites (red, no build)

**File**: none — env override only.

```bash
DEPLOYMENT_TARGET_IOS=16.0 bash scripts/test.sh --unit-only \
  2>&1 | tee <artifact_directory>/probe-ios16.0-drift-gate.log
```

Expected: exits 1 **at `verify_deployment_target()`**, before any build, with
`❌ Deployment-target drift` and `✗ IPHONEOS = 17.0 (expected 16.0)`.

#### 3. Probe 1b — SPM consumer floor < package floor (red, resolves a design risk)

**Files**: `SingleThread.xcodeproj/project.pbxproj` (8 iOS literals) — **temporary**.

Design lists "SPM behaviour when a consumer floor is lower than a dependency's"
as unverifiable in-repo. This probe resolves it for the cost of one build:

```bash
perl -pi -e 's/(IPHONEOS_DEPLOYMENT_TARGET = )17\.0;/${1}16.0;/' \
  SingleThread.xcodeproj/project.pbxproj
rg -c 'IPHONEOS_DEPLOYMENT_TARGET = 16\.0;' SingleThread.xcodeproj/project.pbxproj  # expect 8

SIM='platform=iOS Simulator,id=<IOS17 UDID>' make build \
  2>&1 | tee <artifact_directory>/probe-ios16.0-package-floor.log
```

Expected: a build failure naming the SPM floor mismatch (the package still
declares `.iOS("17.0")`). Record the **exact** diagnostic text — this is the
evidence for the design's open risk. If the build instead succeeds, record that
too (a finding: the toolchain ignores it).

```bash
git checkout -- SingleThread.xcodeproj/project.pbxproj   # restore 17.0
```

#### 4. Probe 1c — the floor itself (red)

**Files**: `SingleThread.xcodeproj/project.pbxproj` (8 iOS literals) **and**
`SingleThreadCore/Package.swift:7` — **temporary**.

```bash
perl -pi -e 's/(IPHONEOS_DEPLOYMENT_TARGET = )17\.0;/${1}16.0;/' \
  SingleThread.xcodeproj/project.pbxproj
perl -pi -e 's/\.iOS\("17\.0"\)/.iOS("16.0")/' SingleThreadCore/Package.swift

DEPLOYMENT_TARGET_IOS=16.0 SIM='platform=iOS Simulator,id=<IOS17 UDID>' \
  xcodebuild -scheme SingleThread -destination "$SIM" -configuration Debug \
    -derivedDataPath DerivedData build-for-testing \
  2>&1 | tee <artifact_directory>/probe-ios16.0-build.log

git checkout -- SingleThread.xcodeproj/project.pbxproj SingleThreadCore/Package.swift
git status --short   # expect only committed-untracked artifact files, no floor files
```

**Instrument note (deviation from `structure.md`)**: `structure.md` prescribes
`scripts/test.sh --unit-only` for this probe, but `--unit-only` runs the
**macOS-native** suite (`test.sh` unit branch uses `MAC_SIM`), which cannot
surface an iOS availability error. A raw iOS-simulator `build-for-testing` under
the env-pinned gate value is the correct instrument; the gate-drift half of the
probe is still covered, unchanged, by Probe 1a.

Expected in the log: `error:` availability diagnostics naming the pinning API —
`@Observable` / `Observable` (Observation) and/or `EKAuthorizationStatus.fullAccess`
/ `requestFullAccessToReminders()`, with the text `only available in iOS 17.0 or
newer` (or `16.0`-style guards). Because `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
+ `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE`, this must **fail** the build.

- If it fails on an unrelated API, **record that API** in the log/`verification.md`
  — it becomes the real pin.
- If it unexpectedly **succeeds**, the true floor is below 17.0: stop and report
  (design-level finding, per `structure.md` "Deliberately not in this structure").

#### 5. Restore + landed-floor green gate

**Action**: confirm the landed tree is intact and the gate accepts it.

```bash
git diff --stat                        # expect no floor files
rg -c 'IPHONEOS_DEPLOYMENT_TARGET = 17\.0;' SingleThread.xcodeproj/project.pbxproj  # expect 8
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-landed-gate.log
```

Assert the log contains
`✓ All deployment-target + package-floor literals match` and
`iOS 17.0 × 8, watchOS 11.0 + macOS 26.5 × 12, package .iOS 1, package other 2`.
The script's overall exit may be non-zero because of the **three known
local-only macOS failures** (`EntitlementStoreTests.isEntitledSurvivesStoreRecreation`,
`initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — annotate them as
pre-existing, do not debug.

#### 6. Green runtime verification on the real iOS 17.x device

```bash
SIM='platform=iOS Simulator,id=<IOS17 UDID>' make build
SIM='platform=iOS Simulator,id=<IOS17 UDID>' scripts/test-one.sh SingleThreadTests/ReminderStoreTests
SIM='platform=iOS Simulator,id=<IOS17 UDID>' scripts/test-one.sh SingleThreadTests/EventKitStoringTests
SIM='platform=iOS Simulator,id=<IOS17 UDID>' make ui-test
```

`scripts/test-one.sh` exits non-zero on zero matched cases — a `SUCCEEDED` with
0 cases proves nothing. Targeted suites only (gate staging); the full gate runs
once in Phase 3.

Smoke install + launch on that runtime (bundle id `app.alanvardy.SingleThread`):

```bash
xcrun simctl install <UDID> DerivedData/Build/Products/Debug-iphonesimulator/SingleThread.app
xcrun simctl launch --console-pty <UDID> app.alanvardy.SingleThread
```

### Verification

#### Automated
- [x] `probe-ios16.0-drift-gate.log` exists and contains `❌ Deployment-target drift`; the run never reached `==> Unit tests`
- [x] `probe-ios16.0-package-floor.log` exists and records the SPM consumer-floor diagnostic (or its documented absence)
- [x] `probe-ios16.0-build.log` contains a compiler `error:` naming `@Observable`/`Observable` and/or `EKAuthorizationStatus.fullAccess` / `requestFullAccessToReminders`, with an iOS-availability phrase
- [x] `git status --short` shows no modified `project.pbxproj` / `Package.swift`; `rg -c 'IPHONEOS_DEPLOYMENT_TARGET = 17\.0;'` → 8; `rg -c '\.iOS\("17\.0"\)' SingleThreadCore/Package.swift` → 1
- [x] `probe-landed-gate.log` contains `✓ All deployment-target + package-floor literals match`
- [x] `make build` with `SIM='…id=<IOS17 UDID>'` succeeds
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` and `…/EventKitStoringTests` each print `ok: N case(s) ran` with N > 0
- [x] `make ui-test` with the iOS 17.x `SIM` passes

#### Manual
- [ ] `probe-runtimes.md` records the exact downloaded iOS runtime build, the created device UDID, and (if applicable) the named verification gap
- [ ] Smoke launch on the iOS 17.x sim reaches the reminder list; the EventKit authorization prompt appears (grant → list renders, deny → the denied state renders) — screenshots optional but the observed outcome must be written into `probe-runtimes.md`
- [ ] Probe logs and `probe-runtimes.md` are `git add`-ed under the artifact directory

---

## Phase 2: watchOS 11.0 floor proven + runtime-verified on a real watchOS 11.x runtime

**Outcome**: the watch app builds, installs and runs on a watchOS 11.x runtime;
9.0 fails with availability errors; 10.0 is recorded as a green-but-rejected
data point (Series 6+ reach is unchanged either way).

### Changes

#### 1. Runtime prerequisite (no file edit)

```bash
xcodebuild -downloadPlatform watchOS -buildVersion 11.5
xcrun simctl list runtimes | grep -i 'watchOS 11'   # note the runtime identifier

# Apple Watch Series 9 / 10 / SE (2nd gen) device types are present in Xcode 27
xcrun simctl create "Probe Watch S9 (11.5)" \
  com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-9-45mm \
  com.apple.CoreSimulator.SimRuntime.watchOS-11-5
```

Record in `probe-runtimes.md`:
`WATCH11_SIM='platform=watchOS Simulator,id=<UDID>'`.

**Fallback**: same ladder as Phase 1 (strongest available pre-26 watchOS runtime),
recorded as a **named gap** in `probe-runtimes.md` + the PR body. Do not disturb
the shared default `WATCH_TEST_SIM` (`Apple Watch Series 11 (46mm)`).

#### 2. Probe 2a — gate drift (red, no build)

```bash
DEPLOYMENT_TARGET_WATCHOS=10.0 bash scripts/test.sh --unit-only \
  2>&1 | tee <artifact_directory>/probe-watchos10.0-drift-gate.log
```

Expected: exit 1 at the gate, `✗ WATCHOS = 11.0 (expected 10.0)`.

#### 3. Probe 2b — watchOS 9.0 (red)

**Files**: `project.pbxproj` (6 `WATCHOS_DEPLOYMENT_TARGET` literals) and
`SingleThreadCore/Package.swift:8` — **temporary**.

```bash
perl -pi -e 's/(WATCHOS_DEPLOYMENT_TARGET = )11\.0;/${1}9.0;/' \
  SingleThread.xcodeproj/project.pbxproj
perl -pi -e 's/\.watchOS\("11\.0"\)/.watchOS("9.0")/' SingleThreadCore/Package.swift
rg -c 'WATCHOS_DEPLOYMENT_TARGET = 9\.0;' SingleThread.xcodeproj/project.pbxproj  # expect 6

DEPLOYMENT_TARGET_WATCHOS=9.0 make watch-build \
  2>&1 | tee <artifact_directory>/probe-watchos9.0-build.log

git checkout -- SingleThread.xcodeproj/project.pbxproj SingleThreadCore/Package.swift
```

`make watch-build` uses `WATCH_SIM := generic/platform=watchOS Simulator`
(`Makefile:5`), which is the right instrument: the availability check runs
against the deployment target, not the runtime, and a generic destination avoids
booting a device. The watch scheme compiles `SingleThreadWatch` + the shared
`SingleThreadCore`/watch sources, so both `@Observable` and EventKit are in scope.

Expected: `error:` availability diagnostics naming `@Observable`/`Observable`
and/or `requestFullAccessToReminders` / `.fullAccess` at `watchOS 10.0 or newer`
— `make watch-build` must fail.

#### 4. Probe 2c — watchOS 10.0 (recorded data point)

**Files**: same two — **temporary**.

```bash
perl -pi -e 's/(WATCHOS_DEPLOYMENT_TARGET = )11\.0;/${1}10.0;/' \
  SingleThread.xcodeproj/project.pbxproj
perl -pi -e 's/\.watchOS\("11\.0"\)/.watchOS("10.0")/' SingleThreadCore/Package.swift

DEPLOYMENT_TARGET_WATCHOS=10.0 make watch-build \
  2>&1 | tee <artifact_directory>/probe-watchos10.0-build.log

git checkout -- SingleThread.xcodeproj/project.pbxproj SingleThreadCore/Package.swift
git status --short   # no floor files
```

Expected: **succeeds** (EventKit's floor is `watchos(10.0)`; Observation's is
watchOS 10). Record the verdict and the reason it is rejected as a ship floor
(design decision 2: only buys Series 4/5/SE 1 reach, which is not a product
goal). If 10.0 errors, that is a finding — record the exact API.

#### 5. Restore + landed-floor green gate

```bash
rg -c 'WATCHOS_DEPLOYMENT_TARGET = 11\.0;' SingleThread.xcodeproj/project.pbxproj  # expect 6
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-watchos-landed-gate.log
```

Assert `✓ All deployment-target + package-floor literals match`; ignore the three
known local-only macOS `EntitlementStoreTests` failures.

#### 6. Green runtime verification on the real watchOS 11.x runtime

```bash
WATCH_SIM='platform=watchOS Simulator,id=<WATCH11 UDID>' make watch-build
WATCH_TEST_SIM='platform=watchOS Simulator,id=<WATCH11 UDID>' make watch-test
WATCH_TEST_SIM='platform=watchOS Simulator,id=<WATCH11 UDID>' make watch-ui-test
```

`make watch-ui-test` needs a **paired** iPhone+watch simulator — follow the
`simulator-pairing` skill; a watchOS 11.x watch must be paired with a compatible
iPhone runtime (pair the iOS 17.x sim from Phase 1 where possible).

`lib_TestingInterop.dylib` determination (structure requires recording which):
`scripts/test.sh:271-288` bundles that lib into the watch UI runner because the
*26.5* simruntime lacks it. On the 11.x runtime, first try `make watch-ui-test`
unmodified and check the runner launch:
- if it launches and tests pass → the workaround is **not needed** on 11.x;
- if it crashes with `Library not loaded: @rpath/lib_TestingInterop.dylib` → the
  workaround is **needed**; record that, and apply the same `cp` from
  `/Applications/Xcode.app/Contents/Developer/Platforms/WatchSimulator.platform/Developer/usr/lib/lib_TestingInterop.dylib`
  into `DerivedData/Build/Products/Debug-watchsimulator/SingleThreadWatchUITests-Runner.app/Frameworks/`
  before re-running.
Write the verdict (needed / not needed / harmful) into `probe-runtimes.md`; do
**not** edit `scripts/test.sh` for it (that is Phase 3's file, and the workaround
block is unchanged by this ticket).

Smoke install + launch (watch bundle id `app.alanvardy.SingleThread.watchkitapp`):

```bash
xcrun simctl install <WATCH11 UDID> DerivedData/Build/Products/Debug-watchsimulator/SingleThreadWatch.app
xcrun simctl launch <WATCH11 UDID> app.alanvardy.SingleThread.watchkitapp
```

### Verification

#### Automated
- [x] `probe-watchos10.0-drift-gate.log` contains `❌ Deployment-target drift` naming WATCHOS
- [x] `probe-watchos9.0-build.log` contains a compiler `error:` naming `@Observable`/`Observable` and/or the EventKit full-access API
- [x] `probe-watchos10.0-build.log` shows a **successful** watch build (or the recorded API that still pins it)
- [x] After each probe: `rg -c 'WATCHOS_DEPLOYMENT_TARGET = 11\.0;'` → 6 and `git status --short` shows no floor files
- [x] `probe-watchos-landed-gate.log` contains `✓ All deployment-target + package-floor literals match`
- [x] `WATCH_SIM='…id=<WATCH11 UDID>' make watch-build` succeeds
- [x] `WATCH_TEST_SIM='…id=<WATCH11 UDID>' make watch-test` passes
- [x] `WATCH_TEST_SIM='…id=<WATCH11 UDID>' make watch-ui-test` passes, or the `lib_TestingInterop.dylib` outcome is recorded with the crash log

#### Manual
- [ ] `probe-runtimes.md` records the watchOS 11.x runtime build + device UDID, the pairing used, and the `lib_TestingInterop` verdict
- [ ] Smoke launch on the watchOS 11.x sim renders the reminder list (record the observed outcome in `probe-runtimes.md`)
- [ ] All watch probe logs + `probe-runtimes.md` updates committed under the artifact directory

---

## Phase 3: Hardening — gate count guard, evidence record, full gate

**Outcome**: the gate detects *per-platform* literal drift (not just value
drift), the paper trail states the verified floors and corrects the landed
commit's macOS claim, and the full CI-identical gate is green.

### Changes

#### 1. Per-platform literal-count guards

**File**: `scripts/test.sh`
**Action**: modify — replace the collapsed `other_target` / `pkg_other` counters
with per-platform counters (`:130-206` region), and replace the constants block.

Today a watchOS literal swapped for a macOS one still totals 20 and passes.
New constants (replacing the `EXPECTED_TARGET_LITERALS` / `EXPECTED_PACKAGE_LITERALS`
pair):

```bash
DEPLOYMENT_TARGET_IOS="${DEPLOYMENT_TARGET_IOS:-17.0}"
DEPLOYMENT_TARGET_WATCHOS="${DEPLOYMENT_TARGET_WATCHOS:-11.0}"
DEPLOYMENT_TARGET_MACOSX="${DEPLOYMENT_TARGET_MACOSX:-26.5}"
EXPECTED_IOS_LITERALS=8        # IPHONEOS_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_WATCHOS_LITERALS=6    # WATCHOS_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_MACOS_LITERALS=6      # MACOSX_DEPLOYMENT_TARGET in project.pbxproj
EXPECTED_PACKAGE_IOS=1         # .iOS("…") in Package.swift
EXPECTED_PACKAGE_WATCHOS=1     # .watchOS("…") in Package.swift
EXPECTED_PACKAGE_MACOS=1       # .macOS("…") in Package.swift
```

Function body (counters + count checks + summary), values/defaults unchanged:

```bash
verify_deployment_target() {
    local pbxproj="SingleThread.xcodeproj/project.pbxproj"
    local package="SingleThreadCore/Package.swift"
    local drift=0
    local ios_target=0 watchos_target=0 macos_target=0
    local pkg_ios=0 pkg_watchos=0 pkg_macos=0
    local line target val expected

    echo "==> Verifying deployment targets / package floors"
    echo "    (iOS $DEPLOYMENT_TARGET_IOS, watchOS $DEPLOYMENT_TARGET_WATCHOS, macOS $DEPLOYMENT_TARGET_MACOSX)…"

    # 1) Unchanged pbxproj scan; each platform gets its OWN counter.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET = [0-9]+\.[0-9]+;'; then
            target=$(echo "$line" | grep -oE '(IPHONEOS|MACOSX|WATCHOS)')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            case "$target" in
                IPHONEOS) ios_target=$((ios_target + 1)); expected="$DEPLOYMENT_TARGET_IOS" ;;
                WATCHOS)  watchos_target=$((watchos_target + 1)); expected="$DEPLOYMENT_TARGET_WATCHOS" ;;
                *)        macos_target=$((macos_target + 1)); expected="$DEPLOYMENT_TARGET_MACOSX" ;;
            esac
            if [[ "$val" != "$expected" ]]; then
                echo "    ✗ $target = $val (expected $expected)"
                drift=1
            fi
        fi
    done < "$pbxproj"

    # 2) Unchanged Package.swift scan; per-platform counters.
    while IFS= read -r line; do
        if echo "$line" | grep -qE '\.(iOS|watchOS|macOS)\("[0-9]+\.[0-9]+"\)'; then
            target=$(echo "$line" | grep -oE '\.iOS|\.watchOS|\.macOS')
            val=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+')
            case "$target" in
                .iOS)      pkg_ios=$((pkg_ios + 1)); expected="$DEPLOYMENT_TARGET_IOS" ;;
                .watchOS)  pkg_watchos=$((pkg_watchos + 1)); expected="$DEPLOYMENT_TARGET_WATCHOS" ;;
                *)         pkg_macos=$((pkg_macos + 1)); expected="$DEPLOYMENT_TARGET_MACOSX" ;;
            esac
            if [[ "$val" != "$expected" ]]; then
                echo "    ✗ package $target = $val (expected $expected)"
                drift=1
            fi
        fi
    done < "$package"

    # 3) Per-platform count drift: a literal swapped between platforms (or
    #    added/removed) must fail even when the total is unchanged.
    [[ "$ios_target" -eq "$EXPECTED_IOS_LITERALS" ]] || {
        echo "    ✗ IPHONEOS literal count $ios_target (expected $EXPECTED_IOS_LITERALS)"; drift=1; }
    [[ "$watchos_target" -eq "$EXPECTED_WATCHOS_LITERALS" ]] || {
        echo "    ✗ WATCHOS literal count $watchos_target (expected $EXPECTED_WATCHOS_LITERALS)"; drift=1; }
    [[ "$macos_target" -eq "$EXPECTED_MACOS_LITERALS" ]] || {
        echo "    ✗ MACOSX literal count $macos_target (expected $EXPECTED_MACOS_LITERALS)"; drift=1; }
    [[ "$pkg_ios" -eq "$EXPECTED_PACKAGE_IOS" ]] || {
        echo "    ✗ package .iOS count $pkg_ios (expected $EXPECTED_PACKAGE_IOS)"; drift=1; }
    [[ "$pkg_watchos" -eq "$EXPECTED_PACKAGE_WATCHOS" ]] || {
        echo "    ✗ package .watchOS count $pkg_watchos (expected $EXPECTED_PACKAGE_WATCHOS)"; drift=1; }
    [[ "$pkg_macos" -eq "$EXPECTED_PACKAGE_MACOS" ]] || {
        echo "    ✗ package .macOS count $pkg_macos (expected $EXPECTED_PACKAGE_MACOS)"; drift=1; }

    if [[ "$drift" -eq 1 ]]; then
        echo ""
        echo "❌ Deployment-target drift: not every literal matches the settled floor set"
        echo "   (iOS $DEPLOYMENT_TARGET_IOS / watchOS $DEPLOYMENT_TARGET_WATCHOS / macOS $DEPLOYMENT_TARGET_MACOSX)."
        echo "   Fix SingleThread.xcodeproj/project.pbxproj and SingleThreadCore/Package.swift."
        exit 1
    fi
    printf "    ✓ All deployment-target + package-floor literals match\n"
    printf "      (iOS %s × %d, watchOS %s × %d, macOS %s × %d; package .iOS %d, .watchOS %d, .macOS %d)\n" \
        "$DEPLOYMENT_TARGET_IOS" "$ios_target" \
        "$DEPLOYMENT_TARGET_WATCHOS" "$watchos_target" \
        "$DEPLOYMENT_TARGET_MACOSX" "$macos_target" \
        "$pkg_ios" "$pkg_watchos" "$pkg_macos"
}

verify_deployment_target
```

(The comment above the block is preserved except for the macOS correction below.)

#### 2. Correct the false macOS claim

**File**: `scripts/test.sh` (the header comment above the gate, formerly `:131-141`)

The landed commit `53124c3e` claims *"the store's macOS requirement derives from
`IPHONEOS_DEPLOYMENT_TARGET`, not from `MACOSX_DEPLOYMENT_TARGET`"* — **verified
false**. The app target is a native macOS build
(`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`,
`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`, `MACOSX_DEPLOYMENT_TARGET = 26.5`, no
Catalyst), so the macOS listing derives from `MACOSX_DEPLOYMENT_TARGET` and the
Mac App Store listing still requires macOS 26.5. Replace the sentence:

```
# macOS stays 26.5: there is no 18.x version line for macOS under this SDK, and
# the store's macOS requirement derives from IPHONEOS_DEPLOYMENT_TARGET, not
# from MACOSX_DEPLOYMENT_TARGET — which is exactly why macOS and watchOS are
# tracked as separate constants here rather than sharing one floor.
```

with:

```
# macOS stays 26.5 (out of scope for VAR-1014, and unverifiable here: CI is
# macos-26 only). The app target is a native macOS build — SUPPORTED_PLATFORMS
# includes macosx, macOS-only entitlements, no Catalyst — so the Mac App Store
# listing derives from MACOSX_DEPLOYMENT_TARGET, NOT from
# IPHONEOS_DEPLOYMENT_TARGET. That independence is why macOS and watchOS are
# tracked as separate constants with separate literal counts.
```

#### 3. Evidence record

**File**: `<artifact_directory>verification.md`
**Action**: create — the durable paper trail the landed commit lacks.

Contents:
- The verified floor tuple (`iOS 17.0 / watchOS 11.0 / macOS 26.5`) and the
  observed probe floors (16.0 red / watchOS 9.0 red / watchOS 10.0 green-but-rejected),
  each with the **exact API named by the compiler** and a link to its log file.
- The runtime versions actually used (iOS 17.x build, watchOS 11.x build, device
  UDIDs) and the smoke-launch outcomes.
- The `lib_TestingInterop.dylib` verdict on 11.x.
- The macOS-listing correction (native macOS build → `MACOSX_DEPLOYMENT_TARGET`).
- Any **named verification gap** (no installable 17.x/11.x runtime, unpaired
  watch UI run, etc.).
- `git rev-parse --short HEAD` for the commit the gate covered.

#### 4. PR body (`#201`)

**Action**: edit via `gh pr edit 201 --body-file <file>`; PR is currently a draft
with an **empty** body. Body sections: what changed (proof + gate hardening, no
floor values changed), the verified tuple, the probe table, the macOS-listing
correction, the *named* gaps, and the test story —
"no new unit test: the regression surface is `verify_deployment_target()`, proven
red/green by the drift probes below" (repo policy's unit-test requirement is
satisfied by the gate assertions + probe evidence; state this explicitly).

#### 5. Gate-hardening probes (red/green) — run in-line, then restore

```bash
# 3a: watchOS literal swapped for a macOS one (total still 20, must now fail)
perl -pi -e 's/WATCHOS_DEPLOYMENT_TARGET = 11\.0;/MACOSX_DEPLOYMENT_TARGET = 26.5;/ if $. == 965' \
  SingleThread.xcodeproj/project.pbxproj
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-gate-watchos-swap.log
git checkout -- SingleThread.xcodeproj/project.pbxproj

# 3b: one watchOS literal removed (total 19, must fail)
perl -ni -e 'print unless $. == 965' SingleThread.xcodeproj/project.pbxproj
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-gate-literal-removed.log
git checkout -- SingleThread.xcodeproj/project.pbxproj

# 3c: package .watchOS literal removed (must fail on the per-platform package count)
perl -ni -e 'print unless /\.watchOS\("11\.0"\)/' SingleThreadCore/Package.swift
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-gate-package-removed.log
git checkout -- SingleThreadCore/Package.swift

# 3d: correct tree (must pass the gate)
bash scripts/test.sh --unit-only 2>&1 | tee <artifact_directory>/probe-gate-clean.log
```

Each red probe asserts the log contains `❌ Deployment-target drift` **and** that
the run never reached `==> Unit tests`; 3d asserts
`✓ All deployment-target + package-floor literals match`. For 3b/3c the total
count changes too, so the log must name the *specific* platform count line
(`✗ WATCHOS literal count 5`, `✗ package .watchOS count 0`) — that is what proves
the guard is per-platform, not just a total.

#### 6. macOS floor unchanged

```bash
make mac-test        # platform=macOS; MACOSX_DEPLOYMENT_TARGET unchanged at 26.5
```

Confirms the Phase 1–3 work did not disturb the macOS path; the three known
local-only `EntitlementStoreTests` failures are expected and annotated.

#### 7. Format / lint / clean, then the full gate

```bash
make format && make lint      # fast; must be clean before the slow gate
rm -rf DerivedData            # pbxproj/settings changed across phases → stale index
```

Then run `./scripts/test.sh` **once** via the **`run-gate` skill** — one dedicated
async gate subagent, `worktree: true`, multi-hour timeout
(`timeoutMs: 21600000`), `SIM='platform=iOS Simulator,id=BFB5C8FB-5ED5-48AD-9149-298E20FCB4E6'`.
Never `nohup` it ad-hoc. Commit everything (source + artifact logs) first — the
gate worktree branches from the branch tip, so uncommitted changes are not gated.
If two UI-stage contention failures recur, stop re-running locally; CI is
authoritative.

### Verification

#### Automated
- [x] `probe-gate-watchos-swap.log` contains `❌ Deployment-target drift` + `✗ WATCHOS literal count 5` (and no `==> Unit tests`)
- [x] `probe-gate-literal-removed.log` contains `✗ WATCHOS literal count 5` (total-count change alone does not satisfy this)
- [x] `probe-gate-package-removed.log` contains `✗ package .watchOS count 0`
- [x] `probe-gate-clean.log` contains `✓ All deployment-target + package-floor literals match` with `iOS 17.0 × 8, watchOS 11.0 × 6, macOS 26.5 × 6; package .iOS 1, .watchOS 1, .macOS 1`
- [x] `git status --short` clean of floor files after every probe; `rg -c` counts still 8/6/6 and 1/1/1
- [x] `make format` and `make lint` exit 0
- [x] `make mac-test` runs against `platform=macOS` with the floor still 26.5
- [ ] Gate subagent verdict is **PASS** for `git rev-parse --short HEAD` == the tip committed before launch; `gate.md` saved
- [ ] CI on PR #201 is green (authoritative)

#### Manual
- [ ] `verification.md` exists, lists every probe log, the runtime versions/UDIDs, the macOS-listing correction, and any named gap
- [ ] PR #201 body updated and describes the proof, the correction, and the "no new unit test — the gate is the test" rationale
- [ ] No floor value was changed by this ticket: `git diff origin/main -- SingleThread.xcodeproj/project.pbxproj SingleThreadCore/Package.swift` shows only `53124c3e`'s landed content, nothing new
- [ ] The only production-file diff across all three phases is `scripts/test.sh`

---

## Testing Checkpoints

- **After Phase 1**: iOS 16.0 red log captured (naming the pinning API), SPM
  consumer-floor behaviour recorded, landed floors restored (8×17.0 / 1×.iOS 17.0),
  gate green, iOS 17.x build + targeted suites + smoke launch green.
- **After Phase 2**: watchOS 9.0 red / 10.0 green-but-rejected logs captured,
  watch build + watch suites green on the 11.x runtime, `lib_TestingInterop`
  verdict recorded, landed floors restored (6×11.0 / 1×.watchOS 11.0), gate green.
- **After Phase 3**: per-platform count guards red/green-proven (3a–3d),
  `verification.md` + PR body written, `make mac-test` green at 26.5, full
  `./scripts/test.sh` via `run-gate` green, CI green.

Never advance on a red checkpoint, and never leave the tree carrying a probe value.

## Deviations from `structure.md`

1. **Phase 1 probe instrument** — `structure.md` prescribes
   `scripts/test.sh --unit-only` for the iOS floor probe. `--unit-only` runs the
   **macOS-native** suite (`test.sh` unit branch uses `MAC_SIM`), which cannot
   surface an iOS availability error. The plan uses an iOS-simulator
   `build-for-testing` under the pinned destination instead; the gate-drift half
   of the probe stays exactly as prescribed.
2. **Phase 2 probe instrument** — same reasoning, `make watch-build`
   (`generic/platform=watchOS Simulator`) instead of `--unit-only`.
3. **Phase 1 Probe 1b (SPM consumer-floor)** — added beyond `structure.md`:
   a one-build probe with the pbxproj at 16.0 and the package still at 17.0,
   which converts design "Open Risks" item 3 (SPM behaviour when the consumer
   floor is lower than the dependency's) from unverifiable into evidence.
4. **No other additions** — no floor value changes, no runtime `#available`
   branches, no new tests or targets, no CI changes.
