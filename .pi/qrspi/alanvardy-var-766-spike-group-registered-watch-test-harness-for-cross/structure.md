# Structure Outline

## Approach

Register the App Group entitlement on the **production watch target** (config
layer), then add a hosted watch unit test (Swift Testing) that probes the
registration and hard-asserts the group↔`.standard` divergence, then document
the reusable harness. No new targets — `SingleThreadWatchTests` is reused and
`EXPECTED_TARGET_LITERALS` stays 20.

---

## Stage 1: Entitlements Registration (config layer — bottom)

Give `SingleThreadWatch` the App Group entitlement so `AppGroup.defaults`
(`AppGroup.swift:13-19`) resolves to a real suite instead of falling back to
`.standard`. This is the "schema/migration" of the spike: everything above it
assumes the suite exists. Green tests here prove the registration actually took
effect and broke nothing.

**Files**
- `SingleThreadWatch/AppGroup.entitlements` — **new**, byte-mirror of
  `SingleThread/AppGroup.entitlements:5-7`.
- `SingleThread.xcodeproj/project.pbxproj` — watch app target configs
  (`:941-987`, Debug **and** Release).
- `SingleThreadWatchTests/AppGroupRegistrationTests.swift` — **new** test file.

**Key changes**
- `com.apple.security.application-groups = ["group.app.alanvardy.SingleThread"]`
  (plist — same single-element array shape as iOS, but the value is read from
  `AppGroup.suiteName` when asserted, never re-hardcoded).
- `CODE_SIGN_ENTITLEMENTS = "SingleThreadWatch/AppGroup.entitlements";` on the
  watch app target Debug + Release configs (mirrors iOS `:740-742,790-792`).
- `REGISTER_APP_GROUPS = YES;` on the watch app target (mirrors iOS `:772,822`).
- **No new target** ⇒ no `EXPECTED_TARGET_LITERALS`/`EXPECTED_PACKAGE_LITERALS`
  edits, no scheme `TestAction`, no `-only-testing`, no Makefile/CI changes.

**Tests** — in `AppGroupRegistrationTests.swift` (Swift Testing, no `test` prefix):
- `suiteResolvesOnWatch()` (happy): `#expect(UserDefaults(suiteName:
  AppGroup.suiteName) != nil)` — the registration probe, the spike's core
  unknown.
- Regression (sad-path guard): the existing watch unit suite still runs green —
  e.g. `ShowEnableActionButtonsStateTests` clears both containers
  (`:7-10,57-61`), so it must tolerate the group now resolving.
- Negative outcome (not a test, a finding): if the probe fails, the spike's
  answer is "registration does not take effect on the watchOS simulator" —
  record it in the runbook and **stop here**; Stages 2–3 collapse into that
  negative write-up.

**Verify**

`make watch-test` (targeted `-only-testing:SingleThreadWatchTests`) — probe green
and zero regressions before moving up.

---

## Stage 2: Harness — Cross-Container Divergence (container-mechanics layer)

Deliver a small reusable probe/assertion helper plus the divergence test that
proves the group suite and `UserDefaults.standard` are now two distinct
containers on the registered watch. This is the spike's acceptance criterion.

**Files**
- `SingleThreadWatchTests/AppGroupHarness.swift` — **new** helper.
- `SingleThreadWatchTests/AppGroupRegistrationTests.swift` — extend (probe +
  divergence, or add `AppGroupDivergenceTests.swift`).

**Key changes**
- Helper (reads `AppGroup.suiteName`, never re-hardcodes the string):
  ```swift
  enum AppGroupHarness {
      /// True when the hosted watch bundle registered the shared group.
      static func suiteExists() -> Bool {
          UserDefaults(suiteName: AppGroup.suiteName) != nil
      }
      /// Seed `completionCount` into the group without touching `.standard`.
      static func seedCompletionCountInGroup(_ count: Int) {
          AppGroup.defaults.set(count, forKey: CompletionCounterStore.defaultsKey)
      }
  }
  ```
- Divergence test (uses `CompletionCounterStore(defaults:)`, the exact store
  back-end the watch sync service invokes — `WatchAppViewModel.swift:244` reads
  `.standard` while the receive path persists to the group `:197-199`):
  ```swift
  @Test func completionCountDivergesBetweenContainers() {
      // clear both containers first (mirrors ShowEnableActionButtonsStateTests)
      AppGroupHarness.seedCompletionCountInGroup(7)
      defer { /* remove key from AppGroup.defaults AND .standard */ }
      #expect(CompletionCounterStore(defaults: AppGroup.defaults).count == 7)
      #expect(CompletionCounterStore(defaults: .standard).count == 0)
      #expect(UserDefaults.standard.object(forKey:
          CompletionCounterStore.defaultsKey) == nil)
  }
  ```

**Tests**
- `completionCountDivergesBetweenContainers()` (happy): write-to-group does not
  appear in `.standard`, and the `.standard`-backed store reads 0.
- `writingStandardDoesNotLeakIntoGroup()` (sad): seed `.standard` only, assert
  group stays absent — proves the divergence is bidirectional, not one-way.
- `suiteResolvesOnWatch()` (from Stage 1): re-run to satisfy the design-ordering
  "probe first, then hard-assert" (`design.md` decision #3).

**Verify**

`make watch-test` green — probe + both divergence tests + the existing 36 watch
`@Test`s (`scripts/count_tests.sh:11`). A **failing** divergence assertion here
is a legitimate finding (e.g. "no divergence"), reported rather than worked
around.

---

## Stage 3: Runbook (documentation layer)

Document the harness and how successor tickets (T1.2 / T2.1) reuse it — the
last deliverable, written once the mechanics are proven.

**Files**
- `docs/WatchAppGroupHarness.md` — **new** (repo already holds runbooks here:
  `docs/SimulatorManualVerification.md`, `docs/TestFlight-macOS.md`).

**Key changes**
- No code types. Content: what the harness asserts (probe vs. divergence), how
  to run it (`make watch-test`), the negative-result recording procedure, and a
  template for adding a successor shared value to the divergence test.

**Tests**

None — a manual/doc checkpoint: every command pasted is copy-paste runnable and
the suite is referenced as `AppGroup.suiteName`, never a hardcoded literal.

**Verify**

Manual read of the runbook; then the **full gate `./scripts/test.sh` once, by
the parent**, after phases commit (per `conventions.md` §1, not per-stage).

---

## Testing Checkpoints

- **After Stage 1** — `make watch-test` green (probe + existing watch unit
  suite). If the probe fails: record negative finding, stop (harness/runbook
  seek nothing further).
- **After Stage 2** — `make watch-test` green (probe + both divergence tests +
  existing suite). This is the spike's acceptance test.
- **After Stage 3** — `./scripts/test.sh` green once (full gate, parent only) +
  `make watch-ui-test` to confirm the now-registered watch app still launches
  and passes UI tests.

## Cross-cutting note (flagged, not re-designed)

The probe test is written **inside** Stage 1's test file because registration is
the only observable artifact of that layer — there is no intermediate check
between "pbxproj edited" and "suite resolves". That collapse of config→assertion
is intrinsic to a build-configuration change, not a vertical-slice violation:
the probe is the config's test, the divergence assertions are the mechanics'
tests, and the runbook is prose-only.