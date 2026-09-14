# Design Discussion

Branch `alanvardy-var-766-…` — spike: group-registered watch test harness for
cross-container verification (VAR-766).

---

## Current State

The watch app has **no entitlements file at all**. `CODE_SIGN_ENTITLEMENTS`
matches only the iOS app (`pbxproj:740-742` Debug, `:790-792` Release), the
widget (`:1000,:1031`) — never the watch app target (`:941-987`) or the two watch
test targets (`:1059-1149`). `REGISTER_APP_GROUPS = YES` appears only on the
iOS/macOS app target (`pbxproj:772,822`).

Result: on the watch, `UserDefaults(suiteName: "group.app.alanvardy.SingleThread")`
returns nil and `AppGroup.defaults` falls back to `.standard`
(`AppGroup.swift:13-19`; `PendingCompletionStore.swift:8-9`). The doc comment
names the fallback trigger "watchOS, unregistered simulators, and previews"
(`AppGroup.swift:13-15`).

This makes a real bug **unobservable** on the current setup:

- iOS writes `completionCount` into the group via `CompletionCounterStore`
  (`ReminderStore.swift:246,278`; `CompletionCounterStore.swift:33-46`) and
  pushes it (`SkippedReminderSyncService.swift:208`).
- The watch's `pushAll()` *reads* `completionCount` from an explicitly
  `.standard` store — `completionCounter: CompletionCounterStore(defaults:
  .standard)` (`WatchAppViewModel.swift:244`; sync-service stores `:232-243`).
- The watch's receive path *persists* into `AppGroup.defaults`
  (`WatchAppViewModel.swift:197-199`) — which, unregistered, is `.standard`.

Because the group never resolves on the watch, "group" and "standard" are the
same physical container, so the divergence (receive → group vs. push ←
`.standard`) is invisible. Every repo document asserts this as a fact
(`…var-721…/q4-findings.md:82`; `…var-747…/research.md:52`) but **no in-repo
evidence establishes whether a group-registered watchOS build can hold the
suite at all** — it is enforced by *build configuration*, not any runtime check.

The watch has no reset machinery. The only `resetPersistedState` is iOS-side
(`UITestingSeed.swift:62-68`, clears 24 `persistedKeys` from both containers),
called only from `--seed` (`AppViewModel.swift:275`). Watch state persists
across relaunches — that is *why* the `--ui-testing-*` per-launch overrides
exist (`WatchAppViewModel.swift:46-49`).

---

## Desired End State

A reusable watch-side harness that exercises the watch app **with the App Group
entitlement registered**, so the cross-container read/write behavior can be
verified for real. Concretely:

1. **The watch app target is group-registered** — an entitlements file +
   `CODE_SIGN_ENTITLEMENTS` + `REGISTER_APP_GROUPS = YES` on
   `SingleThreadWatch`, mirroring the iOS pattern (`pbxproj:740-742,772`).
2. **A watch unit test proves the container mechanics** (in `SingleThreadWatchTests`,
   which is already hosted in the watch app — `pbxproj:1106,1122`):
   - **Probe**: `UserDefaults(suiteName:)` resolves (non-nil) — proves
     registration actually took effect.
   - **Divergence**: `completionCount` written to `AppGroup.defaults` does
     *not* appear in `UserDefaults.standard` (and the `.standard`-backed
     sync-service store reads a different value). Green = divergence confirmed.
3. **No new targets.** Reuse `SingleThreadWatchTests`; `EXPECTED_TARGET_LITERALS`
   stays 20 (`scripts/test.sh:116,176`).
4. **Existing watch tests keep passing** — they use custom `.standard` UUID keys
   or clear both containers (`ShowEnableActionButtonsStateTests.swift:7-10,57-61`),
   so they are resilient to the group now resolving.
5. **A short runbook** documenting the harness + how successor tickets reuse it.

Verification of correctness = the new watch unit test passes (both assertions),
and the existing watch unit + UI suites still pass against the now-registered
watch app (`make watch-test`, `make watch-ui-test` — `Makefile:87-98`), plus the
full gate `./scripts/test.sh` once, by the parent, after phases commit.

---

## Patterns to Follow

- **Container choice is the single source of truth**: every shared value round-
  trips through `AppGroup.defaults`, never bare `.standard` (`AGENTS.md:53-57`).
  The one *deliberate* exception is the watch sync-service stores
  (`WatchAppViewModel.swift:232-244`) — the divergence under test. The harness
  must write through `AppGroup.defaults` (not `.standard`) except where it is
  explicitly asserting the divergence.
- **Entitlement wiring mirrors iOS**: single `com.apple.security.application-groups`
  array (`SingleThread/AppGroup.entitlements:5-7`); `REGISTER_APP_GROUPS = YES`
  (`pbxproj:772,822`). The watch entitlements file should match this shape.
- **Suite name is a single production site** — `AppGroup.suiteName`
  (`AppGroup.swift:10`). The harness reads the suite name, never re-hardcodes
  `"group.app.alanvardy.SingleThread"`.
- **Test isolation like existing store tests**: fresh-UUID suite names are the
  established pattern (`BoolPreferenceStoreTests.swift:54-55`); for the shared
  group suite, clear both containers before/after, mirroring
  `ShowEnableActionButtonsStateTests.swift:7-10,57-61`.
- **Unit tests use Swift Testing** (`@Test`, `#expect`), not XCTest
  (`SingleThreadWatchTests/`; `AGENTS.md`); unit-test names must not start with
  `test`/`testing`.
- **UI tests are avoided** here — the divergence is a container-level assertion,
  not a user flow; AGENTS.md's default-clear bar for UI tests is not met.

**Patterns NOT to follow:**

- iOS's `--seed` JSON global-reset model (`UITestingSeed.swift`) is **not**
  copied to the watch — the watch deliberately uses small per-launch flags and
  has no reset machinery (`WatchAppViewModel.swift:108-162`); adding a second
  reset paradigm now is scope creep (see Q4 decision / "What We're NOT Doing").
- Do **not** route the harness through WatchConnectivity or a phone+watch
  pair. App Groups are same-device containers; phone↔watch never share a suite,
  and sync already moves through `WCSession` (`SkippedReminderSyncService.swift:200-243`).
  The harness is intra-watch: two containers on one watch simulator.
- Do **not** assert that existing tests *assume* the fallback — we verified they
  are resilient, but any test that suddenly fails post-registration is a real
  finding to report, not to paper over.

---

## Design Decisions

1. **Register on the production watch target, not a new variant.** Chosen:
   Option A. Rationale — the vulnerabilities the spike is surfacing exist
   *between* the group and `.standard`; the cheapest way to make that observable
   for real is to give the existing watch app the entitlement and let the already-
   hosted `SingleThreadWatchTests` ride along. A dedicated target would incur the
   full new-target checklist (`AGENTS.md:104-107`) including an
   `EXPECTED_TARGET_LITERALS` 20→21 bump (`scripts/test.sh:116,176`) for zero
   additional signal. This branch is the safe place to observe what a registered
   watch break.

2. **Watch unit test (Swift Testing) as the verification vehicle.** Chosen: Option
   A. Direct container reads/writes, hosted process inherits the app's
   entitlements, deterministic, no pairing (`SKILL.md:1-27` vs CI's fresh unpaired
   sim `ci.yml:391-401`), and it leaves a self-checking regression.

3. **Hard assertion with an explicit registration probe.** Chosen: Option A +
   probe. Order: first `#expect(UserDefaults(suiteName:) != nil)` (registration
   took effect), then hard-assert the write-to-group / not-in-`.standard`
   divergence. A failing second assertion is a *finding* (either "no divergence"
   or "suite can't hold on watchOS sim") — both are legitimate spike outcomes,
   but the probe disambiguates them from mis-wiring.

4. **Minimal reusability surface — helper + runbook, no watch reset machinery.**
   Chosen: Option B. Provide a small probe/assertion helper plus a documented
   runbook; skip building a watch-side `resetPersistedState` equivalent. Client
   tests clean both containers locally as the existing store tests already do.

5. **Reuse existing launch seams; no new flags.** Chosen: Option A. The unit test
   drives the container directly (no UI launch). Where an app-launch path is
   needed for evidence, reuse `--ui-testing-gated`, which already seeds
   `completionCount` at cap into `AppGroup.defaults` (`WatchAppViewModel.swift:26-28`);
   post-registration that seed lands in the real group while the sync-service
   store still reads `.standard` (`:232-244`).

---

## What We're NOT Doing

- **No new targets** (app variant, unit, or UI-test) and therefore **no**
  `EXPECTED_TARGET_LITERALS`/`EXPECTED_PACKAGE_LITERALS` changes, no new scheme
  `TestAction` wiring, no new `-only-testing` entries, no Makefile/CI matrix
  edits (`scripts/test.sh:116-117,176-177`; `AGENTS.md:104-107`).
- **No watch-side `resetPersistedState`** or persisted-state tooling beyond what
  a test's own `defer` cleanup needs.
- **No new launch-argument seam** in the `--ui-testing-*` family.
- **No WatchConnectivity / phone+watch pairing** in the harness — the divergence
  is intra-watch (two containers, one simulator).
- **No change to the sync *protocol*** — we are not fixing the divergence, only
  making it observable. The actual fix belongs to T1.2/T2.1.
- **No StoreKit, no real EventKit store, no macOS/Widget surfaces.**

---

## Open Risks

- **Does a watch unit-test process inherit the host app's App Group?** The
  harness assumes `UserDefaults(suiteName:)` resolves inside the hosted test
  bundle (host = entitled watch app). This is the spike's core unknown and is
  exactly what the registration probe asserts first. If it resolves *only* in
  the app process and not the test bundle, fall back to a `--ui-testing-*`
  launch probe or an app-side surfaced value (revisit Q2's Option B/C).
- **Can a watchOS simulator hold a non-standard suite at all?** Unverified
  in-repo; same-device App Groups should work on the watchOS simulator, but
  phone↔watch never share. If it cannot, the probe fails and the spike's
  finding is "registration does not take effect on the watchOS simulator" — a
  valid, valuable negative result to record in the runbook.
- **Existing watch tests may be less resilient than expected** if any of them
  writes through an `AppGroup.defaults`-backed store but only clears `.standard`.
  We reviewed the suite — the clearing tests clear both
  (`ShowEnableActionButtonsStateTests.swift:7-10,57-61`) — but a post-registration
  failure is a finding, not a false alarm.
- **`REGISTER_APP_GROUPS` semantics on watchOS** differ from iOS (iOS app is the
  host; watch is embedded). The iOS line (`pbxproj:772`) is the template, but
  watch-side application-groups registration may require the containing iOS
  app's entitlements to also list the group — a device-only concern; simulator
  is the spike's scope.
- **Local watchOS 26.5 runner workaround** (`lib_TestingInterop.dylib` bundling,
  `scripts/test.sh:257-269`) must still apply to any watch test run; not touched
  by this spike.