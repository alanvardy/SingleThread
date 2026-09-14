# Implementation Plan

## Overview

Register the App Group entitlement on the production watch target, add a hosted watch unit test that hard-asserts the group↔`.standard` divergence, and document a reusable harness for cross-container verification. No new targets — `EXPECTED_TARGET_LITERALS` stays 20.

---

## Phase 1: Entitlements Registration

Give `SingleThreadWatch` the App Group entitlement so `AppGroup.defaults` resolves to a real suite instead of falling back to `.standard`. Prove registration took effect via a probe test.

### Changes

#### 1.1 Create watch entitlements file

**File**: `SingleThreadWatch/AppGroup.entitlements` — **new**
**Action**: create

Byte-mirror of `SingleThread/AppGroup.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.app.alanvardy.SingleThread</string>
	</array>
</dict>
</plist>
```

#### 1.2 Wire entitlements + App Group registration in pbxproj

**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify — two config blocks, four insertions total

The watch app target has two build configs:
- `51AA3F2B000000000000000C /* Debug */` (lines ~941–966)
- `51AA3F2C000000000000000D /* Release */` (lines ~967–992)

Both currently start with:

```
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
```

**Edit A — Debug config**: replace the two-line pair above with:

```
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "SingleThreadWatch/AppGroup.entitlements";
				CODE_SIGN_STYLE = Automatic;
				REGISTER_APP_GROUPS = YES;
```

**Edit B — Release config**: same replacement in the Release block (identical before-text).

Both `CODE_SIGN_ENTITLEMENTS` and `REGISTER_APP_GROUPS` are needed per `design.md` decision #1 — mirroring the iOS pattern (`pbxproj:740-742,772,822`) on the watch target.

#### 1.3 Create probe test

**File**: `SingleThreadWatchTests/AppGroupRegistrationTests.swift` — **new**
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

@MainActor
@Suite(.serialized)
struct AppGroupRegistrationTests {
    /// Probes registration took effect: the suite initializer returns a
    /// non-nil UserDefaults instance when the host app is entitled.
    @Test
    func suiteResolvesOnWatch() {
        let defaults = UserDefaults(suiteName: AppGroup.suiteName)
        #expect(defaults != nil,
            "App Group suite must resolve on a registered watch build. " +
            "If this fails, registration does not take effect on the " +
            "watchOS simulator — record the negative finding and stop.")
    }
}
```

**Design note (from `structure.md` Stage 1)**: If this probe fails, the spike's answer is "registration does not take effect on the watchOS simulator" — record it in the runbook and **stop here**; Stages 2–3 collapse into the negative write-up.

### Verification

#### Automated
- [x] `make watch-test` passes — probe green + all existing 36 `@Test`s in `SingleThreadWatchTests` still green

#### Manual
- [ ] If `suiteResolvesOnWatch()` fails: record the negative finding, do **not** proceed to Phase 2/3

---

## Phase 2: Harness — Cross-Container Divergence

Deliver a small reusable probe/assertion helper plus divergence tests that prove the group suite and `UserDefaults.standard` are two distinct containers on the registered watch. This is the spike's acceptance criterion.

### Changes

#### 2.1 Create harness helper

**File**: `SingleThreadWatchTests/AppGroupHarness.swift` — **new**
**Action**: create

```swift
import Foundation
import SingleThreadCore

/// Reusable harness for cross-container verification on the watch.
/// Reads `AppGroup.suiteName` — never re-hardcodes the suite literal.
enum AppGroupHarness {
    /// True when the hosted watch bundle registered the shared group.
    static func suiteExists() -> Bool {
        UserDefaults(suiteName: AppGroup.suiteName) != nil
    }

    /// Seed `completionCount` into the group without touching `.standard`.
    static func seedCompletionCountInGroup(_ count: Int) {
        AppGroup.defaults.set(count, forKey: CompletionCounterStore.defaultsKey)
    }

    /// Remove `completionCount` from both containers (cleanup).
    static func clearCompletionCount() {
        AppGroup.defaults.removeObject(forKey: CompletionCounterStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: CompletionCounterStore.defaultsKey)
    }
}
```

#### 2.2 Add divergence tests

**File**: `SingleThreadWatchTests/AppGroupDivergenceTests.swift` — **new**
**Action**: create

Reasoning for separate file (not extending `AppGroupRegistrationTests.swift`): the probe test is the gate — if it fails, Stages 2–3 aren't reached. A separate file keeps the gate independent and lets `AppGroupDivergenceTests` be the reusable template for successor tickets.

```swift
import Foundation
import SingleThreadCore
@testable import SingleThreadWatch
import Testing

/// Proves the group suite and `UserDefaults.standard` are distinct containers
/// on the registered watch — the spike's acceptance criterion.
///
/// Uses `CompletionCounterStore(defaults:)`, the exact store back-end the
/// watch sync service invokes (`WatchAppViewModel.swift:244` reads `.standard`
/// while the receive path persists to the group `:197-199`).
@MainActor
@Suite(.serialized)
struct AppGroupDivergenceTests {
    // MARK: Happy-path

    /// Write-to-group does not appear in `.standard`, and the
    /// `.standard`-backed store reads 0.
    @Test
    func completionCountDivergesBetweenContainers() {
        defer { clearBoth() }

        AppGroupHarness.seedCompletionCountInGroup(7)

        // Group-backed store sees the written value
        #expect(
            CompletionCounterStore(defaults: AppGroup.defaults).completionCount == 7,
            "group store must read the value written to the group")

        // Standard-backed store (the watch sync-service divergence) reads 0
        #expect(
            CompletionCounterStore(defaults: .standard).completionCount == 0,
            "standard store must NOT see group-only writes — " +
            "without divergence this bug is unobservable")

        // Raw `.standard` also empty
        #expect(
            UserDefaults.standard.object(forKey: CompletionCounterStore.defaultsKey) == nil,
            "raw .standard should be empty after group-only write")
    }

    // MARK: Sad-path

    /// Write to `.standard` only — group stays absent. Proves divergence
    /// is bidirectional, not one-way.
    @Test
    func writingStandardDoesNotLeakIntoGroup() {
        defer { clearBoth() }

        let store = CompletionCounterStore(defaults: .standard)
        store.increment()
        store.increment()

        #expect(
            AppGroup.defaults.object(forKey: CompletionCounterStore.defaultsKey) == nil,
            "group must stay empty when only .standard is written")
    }

    // MARK: Cleanup

    private func clearBoth() {
        AppGroupHarness.clearCompletionCount()
    }
}
```

#### 2.3 Re-run probe test

No code change needed — `suiteResolvesOnWatch()` from Phase 1 is already in `AppGroupRegistrationTests.swift`. It re-runs automatically with `make watch-test`. The probe must stay green before divergence assertions are meaningful; the design ordering (`design.md` decision #3) is "probe first, then hard-assert".

### Verification

#### Automated
- [x] `make watch-test` passes — probe + both divergence tests + existing 36 watch `@Test`s

#### Manual
- [ ] If `completionCountDivergesBetweenContainers()` fails: that is a legitimate spike finding (e.g. "no divergence on watchOS simulator") — record it in the runbook
- [ ] If `writingStandardDoesNotLeakIntoGroup()` fails: likewise a legitimate finding

---

## Phase 3: Runbook

Document the harness and how successor tickets (T1.2 / T2.1) reuse it.

### Changes

#### 3.1 Create runbook

**File**: `docs/WatchAppGroupHarness.md` — **new**
**Action**: create

Content:

```markdown
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
```

### Verification

#### Manual
- [ ] Read the runbook — every command pasted is copy-paste runnable
- [ ] Confirm the suite is referenced as `AppGroup.suiteName`, never a hardcoded literal
- [ ] `./scripts/test.sh` passes (full gate, once, by parent after phases commit)
- [ ] `make watch-ui-test` passes — the now-registered watch app still launches and passes UI tests

---

## Implementation Order

1. **Phase 1** → verify `make watch-test` green. If probe fails → stop, record negative finding.
2. **Phase 2** → verify `make watch-test` green (probe + divergence + existing suite). This is the spike's acceptance test.
3. **Phase 3** → write runbook. Then **full gate `./scripts/test.sh` once, by parent** (not per-phase).