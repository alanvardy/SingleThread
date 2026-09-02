# Implementation Plan

## Overview

Finish the already-wired macOS path so `SingleThread` builds, signs, and launches as a native Mac app, and has a documented, repeatable path to a TestFlight-for-macOS upload — with macOS unit tests entering the local full gate. **No new Swift/domain code**; every change is build config, automation, or docs.

> **Deviation from structure.md (corrected here):** structure.md Stage 2 says
> `EXPECTED_TARGET_LITERALS=16`. Verified against the pbxproj, the actual literal
> count is **20** (IPHONEOS ×8 at project.pbxproj:762,812,840,869,897,921,1006,1037;
> MACOSX ×6 at :765,815,841,870,898,922; WATCHOS ×6 at :962,990,1074,1096,1120,1144).
> The in-script comment "WATCHOS (all 2: watch target)" is stale too — there are 3
> watch targets (app + watch UI tests + watch tests) × 2 configs = 6. This plan wires
> the constant to **20** and fixes the comment. Wiring it to 16 would make the guard
> fail every run.

---

## Stage 1: Build Configuration Foundation (schema)

### Changes

#### 1. Add the In-App Purchase capability to the macOS entitlements
**File**: `SingleThread/SingleThread.entitlements`
**Action**: modify

Add the IAP entitlement key (empty array — the real products are resolved from
`Products.storekit` at runtime; no product ID is hard-coded here):

```xml
<dict>
	<key>com.apple.developer.in-app-purchases</key>
	<array/>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	...
</dict>
```

Insert the `com.apple.developer.in-app-purchases` key as the first entry in the
`<dict>`. `plutil -lint` accepts any key order, so this is cosmetic-only correctness.
Do **not** touch any other key. Do **not** change `Products.storekit` or
`EntitlementStore.unlockProductID` (still the single source of truth).

#### 2. Make the widget target iOS-only
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Two lines only — the widget target's `SUPPORTED_PLATFORMS`, in both its build
configs (Debug at :1016, Release at :1047). The app (:772/:822), unit tests
(:847/:876), and UI tests (:904/:928) targets keep `macosx`; only the widget loses
it.

Before (both configs, identical):
```
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
```
After:
```
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
```

Line numbers are stable in this stage (no other pbxproj edit moves lines). Prefer
two line-anchored edits rather than a global replace (the `macosx` string appears in
6 other blocks that must be left alone):

```bash
sed -i '' '1016s/ macosx//' SingleThread.xcodeproj/project.pbxproj
sed -i '' '1047s/ macosx//' SingleThread.xcodeproj/project.pbxproj
```

Confirm the numbers first (`grep -n 'SUPPORTED_PLATFORMS' SingleThread.xcodeproj/project.pbxproj`);
the only two that should become `"iphoneos iphonesimulator";` are the ones in blocks
headed `51AA3F4B0000000000000000 /* Debug */` and `51AA3F4C0000000000000000 /* Release */`
(the widget target). If line numbers have drifted, use `edit` with the block-header
comments as unique anchors spanning down to their `SUPPORTED_PLATFORMS` lines.

### Verification

#### Automated
- [x] `plutil -lint SingleThread/SingleThread.entitlements` → `SingleThread/SingleThread.entitlements: OK`
- [x] `grep -n 'SUPPORTED_PLATFORMS' SingleThread.xcodeproj/project.pbxproj` shows the widget at 1016/1047 as `"iphoneos iphonesimulator";` and the app/tests/UI-tests blocks still `"iphoneos iphonesimulator macosx"`
- [x] `make build` (iOS) stays green — widget still embeds on iOS only (`platformFilter = ios` added to the widget embed build-file — the plan asserted it already existed, but only the target dependency had it; without it `make mac-build` breaks with a PlugIns copy step)
- [x] `make mac-build` stays green (unsigned → the new entitlement has no runtime effect yet)
- [x] `./scripts/test.sh --unit-only` deployment-target guard stays green (the widget declares no `MACOSX_DEPLOYMENT_TARGET`, so the 6-literal count is unchanged)

#### Manual
- [ ] Open the pbxproj in Xcode (or inspect) — the `SingleThreadWidget` target shows no macOS in Supported Platforms; the `SingleThread` app target still shows iPhone/iPad/Mac

---

## Stage 2: macOS Unit Tests Enter the Local Full Gate

### Changes

#### 1. Run the macOS unit tests in `scripts/test.sh` full mode
**File**: `scripts/test.sh`
**Action**: modify

Replace the build-only macOS step (current lines 267–277) with a build+test step:

Before:
```bash
    echo ""
    echo "==> macOS build…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      build
```

After:
```bash
    echo ""
    echo "==> macOS unit tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadTests
```

(No `-parallel-testing-enabled` here — matches the existing `make mac-test` idiom.
`-configuration Debug` is explicit because `mac-test` relies on the scheme default;
being explicit is harmless and mirrors the other steps.)

#### 2. Wire the dead `EXPECTED_*_LITERALS` constants into the guard
**File**: `scripts/test.sh`
**Action**: modify

Fix the constant + stale comment (currently lines 110–117):

```bash
#   IPHONEOS_DEPLOYMENT_TARGET (all 8: app, unit + UI tests, widget) = 18.7
#   MACOSX_DEPLOYMENT_TARGET   (all 6: app, unit + UI tests)         = 26.5
#   WATCHOS_DEPLOYMENT_TARGET  (all 6: watch app + watch UI tests + watch tests) = 26.5
#   Package.swift floor literals: .iOS = 18.7, .watchOS = 26.5, .macOS = 26.5
DEPLOYMENT_TARGET_IOS="${DEPLOYMENT_TARGET_IOS:-18.7}"
DEPLOYMENT_TARGET_OTHER="${DEPLOYMENT_TARGET_OTHER:-26.5}"
EXPECTED_TARGET_LITERALS=20    # all *_DEPLOYMENT_TARGET in project.pbxproj (8+6+6)
EXPECTED_PACKAGE_LITERALS=3    # .iOS/.watchOS/.macOS in Package.swift
```

Then add two drift checks **after** the Package.swift `while` loop and **before**
the `if [[ "$drift" -eq 1 ]]` block in `verify_deployment_target`:

```bash
    [[ $((ios_target + other_target)) -eq "$EXPECTED_TARGET_LITERALS" ]] || drift=1
    [[ $((pkg_ios + pkg_other)) -eq "$EXPECTED_PACKAGE_LITERALS" ]] || drift=1
```

If these fire, the existing `❌ Deployment-target drift` message + `exit 1` already
abort correctly; no new message is required (optionally extend the final `printf` to
include the expected totals, but not required).

### Verification

#### Automated
- [x] `bash -n scripts/test.sh` passes (syntax)
- [x] `./scripts/test.sh --unit-only` passes (guard counts assert 20 target + 3 package literals, both matching)
- [x] `./scripts/test.sh --ui-only` passes (guard runs in all modes)
- [x] Full `./scripts/test.sh` runs `SingleThreadTests` on `platform=macOS` and completes green — **PASSED end-to-end** on 2026-09-02 (`✅ All CI checks passed.`, exit 0). Two environment adaptations were required: (1) a web search showed CI already covers watch/pair infra; (2) this machine's watchOS 26.5 simruntime is missing `lib_TestingInterop.dylib` so the watch UI runner crashes at launch — fixed by commit `8b26d8c` which bundles the Xcode-side lib into the runner (no-op on CI). Manual confirmation of the `==> macOS unit tests…` step in the full-gate output:
  - [x] Full-mode output shows the `==> macOS unit tests…` step and the pass banner after it (observed in the green run)
- [x] `make mac-test` still green and unchanged — used as the macOS-step proxy (same `test -only-testing:SingleThreadTests` on `platform=macOS` command the new full-mode step runs; passed on `My Mac`)

#### Manual
- [x] Confirm the full-mode output now shows a `==> macOS unit tests…` step (not `==> macOS build…`) — **confirmed in the green 2026-09-02 full run** (log line 2528: `==> macOS unit tests…`, followed by `✅ All CI checks passed.`)

---

## Stage 3: Local Signed Launch — `make mac-run`

### Changes

#### 1. Add `make mac-run`
**File**: `Makefile`
**Action**: modify

Add to `.PHONY` and add the target next to `mac-build`/`mac-test`. Distinguishing
feature: **no** `CODE_SIGNING_ALLOWED=NO`, so the build signs with automatic
`"Apple Development"` / team `6NWX2DHB9Q`, then opens the built app.

Update the `.PHONY` line:
```make
.PHONY: build watch-build test ui-test simverify mac-build mac-test mac-run mac-distribute coverage coverage-ui coverage-all check clean lint format periphery watch-ui-test watch-test
```

Add the target:
```make
mac-run:
	xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' \
	  -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build
	open '$(DERIVED_DATA)/Build/Products/Debug/SingleThread.app'
```

- **Files**: `SingleThread/SingleThread.entitlements` is **compiled-into** this build
  via the existing `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` setting — no new change here;
  it's listed so the stage is self-contained.

### Verification

#### Automated
- [x] `make -n mac-run` echoes the two commands (dry-run sanity; does not launch the app)

#### Manual (the honest bar — no automatable assertion exists; the human signs off here)
- [ ] `make mac-run` completes the build, signs, and opens `SingleThread.app`
- [ ] `codesign -dv --entitlements - DerivedData/Build/Products/Debug/SingleThread.app 2>&1` shows `com.apple.security.app-sandbox`, `com.apple.security.application-groups`, `com.apple.security.device.audio-input`, `com.apple.security.personal-information.calendars`, **and** `com.apple.developer.in-app-purchases` (proves Stage 1)
- [ ] First launch shows the Reminders TCC prompt; granting loads reminders (`personal-information.calendars` + `NSRemindersUsageDescription` align)
- [ ] Reminders render; complete / skip / delete work; `c` / `s` keyboard shortcuts work
- [ ] Settings → upgrade surface (PurchaseSettingsView) loads `Products.storekit` products and the unlock flow opens (freemium surface exercised against real `EKEventStore`)
- [ ] **Contingency (only if needed):** if `DerivedData/Build/Products/Debug/SingleThread.app` proves non-deterministic between clean/incremental builds, add a tiny `scripts/run-macos.sh` that resolves the path via `xcodebuild -showBuildSettings | grep BUILT_PRODUCTS_DIR` and have `mac-run` call it. Only do this if the standard path misbehaves.

> ⚠️ Cross-cutting, only-verifiable-here: first signed launch, the macOS TCC surface,
> and macOS StoreKit `.storekit` resolution have no automatable assertion. These stay
> tracked as Open Risks in design.md and are confirmed by a human at this step.

---

## Stage 4: Distribution Automation — Archive → Export

### Changes

#### 1. Checked-in export options plist
**File**: `exportOptions.plist` (repo root)
**Action**: create

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>6NWX2DHB9Q</string>
</dict>
</plist>
```

#### 2. Distribution script
**File**: `scripts/distribute-macos.sh` (repo root)
**Action**: create (make executable: `chmod +x`)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild archive -scheme SingleThread -destination 'generic/platform=macOS' \
  -configuration Release -archivePath build/SingleThread.xcarchive

xcodebuild -exportArchive -archivePath build/SingleThread.xcarchive \
  -exportPath build/ -exportOptionsPlist exportOptions.plist
```

Outputs `build/SingleThread.pkg`. `build/` is already gitignored (`.gitignore`).

#### 3. `make mac-distribute`
**File**: `Makefile`
**Action**: modify

Add the target (after `mac-run`) and ensure `mac-distribute` is in `.PHONY` (already
covered by the Stage 3 `.PHONY` edit — keep both edits on the same line in mind):

```make
mac-distribute:
	bash scripts/distribute-macos.sh
```

### Verification

#### Automated
- [x] `bash -n scripts/distribute-macos.sh` passes (syntax)
- [x] `plutil -lint exportOptions.plist` → `exportOptions.plist: OK`
- [ ] `make mac-distribute` runs `xcodebuild archive` to successful completion — **BLOCKED (human/portal prerequisite, not a script bug)**: the signed archive fails at `GatherProvisioningInputs` because the installed Mac Team Provisioning Profile for `app.alanvardy.SingleThread` does not carry `com.apple.developer.in-app-purchases` (added in Phase 1). Fix: enable *In-App Purchase* on the App ID in the developer portal and regenerate the profile (see Stage 5 prerequisites). Proof the script is sound: the identical archive with `CODE_SIGNING_ALLOWED=NO` → `ARCHIVE SUCCEEDED`. Also no Distribution cert or registered Xcode account on this machine. This wall manifests at `archive`, one step earlier than the plan's documented exportArchive signing wall — same root cause.

#### Manual
- [ ] Archive succeeds; `-exportArchive` produces `build/SingleThread.pkg` (best-effort locally: it may stop at the signing wall if the team's Distribution cert is not on this Mac — that is a documented human-upload concern, not a script bug)
- [ ] The `.pkg` upload itself is **intentionally not automated** (requires an ASC API key — a portal secret); deferred to the Stage 5 doc

---

## Stage 5: Documentation — `docs/TestFlight-macOS.md`

### Changes

#### 1. Release/upload runbook
**File**: `docs/TestFlight-macOS.md` (repo root)
**Action**: create

Sits alongside the existing `docs/SimulatorManualVerification.md`. Content (human-facing,
reproducible, no rediscovery):

- **Portal prerequisites** (secret/portal actions an agent cannot perform):
  - Create the macOS app record for `app.alanvardy.SingleThread` in App Store Connect
  - Add the `unlimited` non-consumable IAP product (id must match `EntitlementStore.unlockProductID` — reference the constant, never inline the id)
  - Mint an ASC API key (used only for manual upload, not checked into CI)
- **Local smoke**: run `make mac-run` and walk the Stage 3 checklist (prompt → render → complete → skip → delete → unlock)
- **Build & upload**: run `make mac-distribute`, then upload `build/SingleThread.pkg` via Transporter/App Store Connect
- **Reference commands** the doc may cite must all exist and work: `make mac-run`, `make mac-distribute`, `make mac-test`, `make mac-build`
- Note the IAP capability now present in `SingleThread/SingleThread.entitlements` and that `Products.storekit`/`unlockProductID` remain the single source of truth

### Verification

#### Automated
- [x] (none — doc only; but guard against drift) `grep -n 'unlockProductID' SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift` confirms the symbol the doc references exists and holds the id

#### Manual
- [ ] Review pass: every command the doc references is committed and working; the product id in the doc is sourced from `EntitlementStore.unlockProductID`, not hard-coded
- [ ] The doc's smoke checklist maps 1:1 to the Stage 3 manual checklist

---

## End-to-End Checklist (run once, after all stages)

- [x] `make format` then `make lint` pass (no Swift changes in this ticket, but the guard edits in `test.sh` are bash — `bash -n` covers them; run lint anyway to keep the gate honest) — **passed in the full gate** (format/lint/SwiftLint steps all green)
- [x] Full `./scripts/test.sh` passes end-to-end (now includes the macOS `SingleThreadTests` run) — **green 2026-09-02** (exit 0; includes the local `lib_TestingInterop` workaround commit `8b26d8c`)
- [x] `make build` and `make mac-build` both green — verified during Stage 1/Phase 1 (`TEST BUILD SUCCEEDED` / macOS `BUILD SUCCEEDED`)
- [x] `plutil -lint SingleThread/SingleThread.entitlements exportOptions.plist` green — both pass
- [x] `bash -n scripts/test.sh scripts/distribute-macos.sh` green — both pass

## Notes on Deviations from structure.md

1. **`EXPECTED_TARGET_LITERALS` is 20, not 16** (structure.md Stage 2). Verified by
   counting pbxproj literals (8 IPHONEOS + 6 MACOSX + 6 WATCHOS). Also corrected the
   stale in-script comment ("WATCHOS all 2" → "all 6"). Everything else follows
   structure.md as written.
2. No other deviations. Stage order, file list, and no-new-Swift-code constraint are
   all preserved.