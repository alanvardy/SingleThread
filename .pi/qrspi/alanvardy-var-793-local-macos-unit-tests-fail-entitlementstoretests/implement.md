# Implementation Summary — var-793

Ticket: Local macOS unit tests fail — `EntitlementStoreTests` entitlement state
leaks from StoreKit DB.

## Outcome (accepted: diagnostic-only end state, option A)

The plan's core mechanism — `SKTestSession.clearTransactions()` isolating the
macOS test run from the host store — was **empirically disproven** (see
"Findings" below) and Phase 2 was reverted. What ships is the horizontal
foundation work that is independently correct, plus a diagnostic canary that
turns the two opaque StoreKit failures into one actionable message. On this
host the two real-StoreKit tests + the canary are **expected to fail** with
`isEntitled → true`; that failure is diagnosed, not silent.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `fc1ed75` | Bounded-Poll Helper — `wait(for:timeout:)` replaces the two async-wait primitives |
| 2     | `57acc23` → reverted `0affbae` | Shared `SKTestSession` + `clearTransactions()` — **disproven, reverted** |
| 3     | `462e8fe` | `hostStoreKitIsClean` canary — actionable failure with product IDs |
| 4     | `18d39dc`, `025fd38` | `reset-storekit.sh` reworked to clear the real host store + ASCII-only fix |
| docs  | `d10c83b` | Diagnostic-only end state documented in plan.md / SKILL.md / script |

## Automated Checks

- [x] `make lint` (swiftformat --lint + swiftlint --strict) — 0 violations / 188 files
- [x] `make mac-test` — 5 non-StoreKit `EntitlementStoreTests` pass; the 2 StoreKit tests fail identically to pre-stage (no regression, Phase 1 gate)
- [x] `make mac-test` — canary fires with `["app.alanvardy.SingleThread.unlimited"]` + the reset instruction (Phase 3)
- [x] `bash -n scripts/reset-storekit.sh` — syntax clean; script validated end-to-end (stops agent, backs up + clears `storeUser.db`, restarts agent)
- [x] `./scripts/test.sh` (full gate attempt): Formatting, SwiftFormat, SwiftLint, Build, Watch build, Periphery — **all passed**; iOS simulator unit tests — **575 passed, 0 failed**, including **all 8 `EntitlementStoreTests`** (canary + both StoreKit tests pass on the sim's clean store). The run was externally SIGKILL'd before the UI/watch stages by simulator contention with another session's run on the same iPhone 17 sim (RequestDenied loop observed) — no test failure.
- [ ] `./scripts/test.sh` macOS stage — **expected fail on this host**: `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` (see Findings). CI (fresh runner, no account dirt) is unaffected.

## Findings (var-793 — established with evidence)

1. **Swift static stored properties initialize lazily on first access.** The
   Phase 2 shared `SKTestSession` was never referenced, so `clearTransactions()`
   never ran; the original gate "failure" was a no-op, not a real test. Even
   after force-touching (`_ = Self.testSession` in all three tests, lint-clean),
   the two tests still failed — **the shared-session hypothesis is falsified**.
2. **The unsigned macOS test run reads the real host store, not the
   SKTestSession store.** `Transaction.currentEntitlements` in a fresh real
   `EntitlementStore()` resolves against the host account/daemon state.
3. **The entitled transaction is account/daemon-scoped, not a deletable local
   file.** A probe test (bare `for await` over `Transaction.currentEntitlements`,
   no session, no purchase) returned `["app.alanvardy.SingleThread.unlimited"]`
   even after: `make reset-storekit`, wiping BOTH Group Containers stores
   (`group.com.apple.storekit` and `group.com.apple.appstoreagent`), and
   SIGKILL of every `storekitd`/`storekitagent`/`appstoreagent`. The run
   re-seeds it on first read.
4. **The only local, green signal is the iOS simulator**: there all 8 tests
   pass (575/575 in the full gate's unit stage), confirming the code changes
   are sound and the failures are purely host-account-specific.
5. `-only-testing:<bundle>/<suite>/<method>` sub-suite filters execute zero
   tests on this setup (`xcresulttool totalTestCount: 0`) — earlier
   "subset passes" during investigation were no-ops; only suite-level or
   bundle-level runs are valid signals.

## Manual Verification Items (from the plan)

- [ ] Confirm the two failing tests fail with `!isEntitled == false` (not a different assertion or a timeout) — Phase 1
- [ ] Verify `isEntitledIsFalseByDefault` / `hasResolvedEntitlementIsFalseByDefault` see an empty store and pass; no `SKServiceErrorDomain Code=2` / config-saving errors — Phase 2
- [ ] On a dirty host: canary failure message lists the specific product IDs and the Xcode reset instruction — Phase 3 (verified locally: yes)
- [ ] On a clean host (or after reset): canary passes — **unreachable via file-level reset on this host** (account-scoped); remaining avenue is Xcode → Debug → StoreKit → Manage Transactions… while the dev app runs
- [ ] `make reset-storekit` runs without errors, finds and clears the store — Phase 4 (verified locally: yes)
- [ ] `make mac-test` — 7/7 on a previously-dirty host — **known-fail on this host** (see Findings); CI is green
- [ ] Full `./scripts/test.sh` passes locally — everything through iOS unit tests passed; macOS stage is the documented known-fail; UI/watch stages were not reachable in the gate attempt (external SIGKILL) and are unaffected by this diff