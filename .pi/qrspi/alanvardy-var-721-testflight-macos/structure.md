# Structure Outline

## Approach

The macOS path is already wired (one multiplatform app target, native non-Catalyst
build, `make mac-build`/`mac-test`). We finish it bottom-up: get the static
build/entitlement foundation right, then make macOS unit tests part of the local
gate, then a signed local launch, then distribution automation, then the human
upload doc. **No new Swift/domain code** — "tests" here are build gates, the
deployment-target guard, `plutil`/`bash -n` lint, and a documented manual smoke
checklist. Two steps are inherently only-verifiable-by-a-human (first signed
launch, first archive/export) and are flagged where they surface.

---

## Stage 1: Build Configuration Foundation (schema)

Deliver the two static config edits everything above depends on: the In-App
Purchase capability in the macOS entitlements, and an unambiguous iOS-only widget
target (no stray macOS-widget build).

**Files**:
- `SingleThread/SingleThread.entitlements`
- `SingleThread.xcodeproj/project.pbxproj`

**Key changes**:
- Entitlements — add the IAP capability:
  ```xml
  <key>com.apple.developer.in-app-purchases</key>
  <array/>
  ```
  (No `Products.storekit`/`unlockProductID` change — those stay the single source.)
- Widget target `SUPPORTED_PLATFORMS` — drop `macosx` in both configs
  (`project.pbxproj:1016` Debug, `:1047` Release):
  ```
  SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
  ```

**Tests**: a lint + build gate (no new unit tests — nothing testable in Swift):
- `plutil -lint SingleThread/SingleThread.entitlements` → well-formed plist
- `make mac-build` / `make mac-test` stay green (builds are unsigned → entitlement has no runtime effect yet)
- `make build` (iOS) stays green; widget still embeds on iOS only
- `./scripts/test.sh` deployment-target guard stays green — `MACOSX_DEPLOYMENT_TARGET`
  literal count is unchanged (6: `:765,:815,:841,:870,:898,:922`; the widget declares none)

**Verify**: `plutil -lint` + `make build` + `make mac-build` all pass. The IAP
entitlement's runtime assertion is deferred to Stage 3's signed `codesign` dump.

---

## Stage 2: macOS Unit Tests Enter the Local Full Gate

`scripts/test.sh` currently does a macOS **build-only** step, so macOS unit tests
never run in the local pipeline (CI has a separate `mac-tests` job). Convert it to
a real unit-test run and tighten the guard's literal-count assertion while in the file.

**Files**:
- `scripts/test.sh`

**Key changes**:
- Full-mode macOS step (`test.sh:267-277`) — build-only → build + test:
  ```bash
  xcodebuild -scheme "$SCHEME" \
    -destination "$MAC_SIM" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    test -only-testing:SingleThreadTests
  ```
- Guard (`test.sh:116-117`): `EXPECTED_TARGET_LITERALS=16` / `EXPECTED_PACKAGE_LITERALS=3`
  are defined but never referenced. Wire them into `verify_deployment_target`:
  ```bash
  [[ $((ios_target + other_target)) -eq "$EXPECTED_TARGET_LITERALS" ]] || drift=1
  [[ $((pkg_ios + pkg_other)) -eq "$EXPECTED_PACKAGE_LITERALS" ]] || drift=1
  ```

**Tests / Verify**: `./scripts/test.sh` full mode now runs `SingleThreadTests` on
`platform=macOS` and passes; the guard counts assert 16 target literals + 3 package
literals and pass. `make mac-test` unchanged and still green.

---

## Stage 3: Local Signed Launch — `make mac-run`

First signed, launchable macOS app. `make mac-run` builds **without**
`CODE_SIGNING_ALLOWED=NO` (automatic `"Apple Development"` / team `6NWX2DHB9Q`),
then opens the built `.app`. This is where Stage 1's IAP entitlement becomes
observable and where the freemium surface is exercised against a real `EKEventStore`.

**Files**:
- `Makefile` (add `mac-run`, next to `mac-build`/`mac-test`)
- `SingleThread/SingleThread.entitlements` (no change — consumed here)

**Key changes**:
```make
mac-run:
	xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' \
	  -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build
	open '$(DERIVED_DATA)/Build/Products/Debug/SingleThread.app'
```
(Launch path is the standard DerivedData product location; a small
`scripts/run-macos.sh` is only added if the `.app` path proves non-deterministic.)

**Verify (manual — the honest bar, no automatable test exists)**:
- `make mac-run` signs + launches; `codesign -dv --entitlements - SingleThread.app`
  shows app-sandbox, app-group, audio-input, calendars **and** `in-app-purchases` (proves Stage 1)
- Reminders TCC prompt appears; reminders render; complete / skip / delete / `c` / `s`
  shortcuts work; PurchaseSettingsView loads `Products.storekit` and unlock functions
- Smoke checklist (prompt → render → complete → skip → delete → unlock) becomes a
  section in the Stage 5 doc

> ⚠️ **Cross-cutting, only-verifiable-here**: first signed launch, the macOS TCC
> surface, and macOS StoreKit `.storekit` resolution have no automatable assertion.
> These are stubbed/tracked as Open Risks in design.md and confirmed by a human at this step.

---

## Stage 4: Distribution Automation — Archive → Export

Turn `xcodebuild archive` + `-exportArchive` into a repeatable local command that
produces an uploadable `.pkg`, mirroring the existing plain-`xcodebuild` idiom (no fastlane).

**Files**:
- `exportOptions.plist` — **new** (repo root, checked in)
- `scripts/distribute-macos.sh` — **new**
- `Makefile` (add `mac-distribute`)

**Key changes**:
- `exportOptions.plist`:
  ```xml
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>6NWX2DHB9Q</string>
  ```
- `distribute-macos.sh`:
  ```bash
  xcodebuild archive -scheme SingleThread -destination 'generic/platform=macOS' \
    -configuration Release -archivePath build/SingleThread.xcarchive
  xcodebuild -exportArchive -archivePath build/SingleThread.xcarchive \
    -exportPath build/ -exportOptionsPlist exportOptions.plist
  ```
  → outputs `SingleThread.pkg`.
- `Makefile`: `mac-distribute:` → `bash scripts/distribute-macos.sh`.

**Tests / Verify**:
- `bash -n scripts/distribute-macos.sh` (syntax)
- `plutil -lint exportOptions.plist`
- `make mac-distribute` runs to completion locally. Honest bar: **archive succeeds**;
  `-exportArchive` may stop at the signing wall if the team's Distribution cert isn't
  on this Mac — that's a documented human-upload concern, not a script bug. The `.pkg`
  upload itself is intentionally **not** automated (ASC key is a portal secret).

---

## Stage 5: Documentation — `docs/TestFlight-macOS.md` (top layer)

The human-facing layer recording the portal/secret steps and the smoke checklist so a
release can be reproduced without rediscovering anything.

**Files**:
- `docs/TestFlight-macOS.md` — **new**

**Key content**:
- Create macOS app record for `app.alanvardy.SingleThread`; add the `unlimited`
  non-consumable product; mint an ASC API key
- Run `make mac-run` smoke (points at the Stage 3 checklist)
- Run `make mac-distribute`, upload the `.pkg`
- Reference `unlockProductID` as the single product source (no hard-coded id)

**Verify (manual)**:
- Doc review: every command referenced (`make mac-run`, `make mac-distribute`,
  `make mac-test`) is committed and working; product id matches
  `EntitlementStore.unlockProductID`.

---

## Testing Checkpoints

After each stage, its gate must be green before advancing:

| Stage | What must be green |
|-------|--------------------|
| 1 | `plutil -lint` + `make build` + `make mac-build` + deployment-target guard |
| 2 | `./scripts/test.sh` runs macOS `SingleThreadTests`; guard count assertions pass |
| 3 | `make mac-run` launches; `codesign` entitlement dump shows `in-app-purchases`; human smoke passes |
| 4 | `bash -n` + `plutil -lint` + `make mac-distribute` archives (export best-effort locally) |
| 5 | Doc review: commands real, product id from `unlockProductID` |