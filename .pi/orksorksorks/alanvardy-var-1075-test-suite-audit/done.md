# Done

- **Branch / head SHA**: `alanvardy-var-1075-test-suite-audit` at `03c59904`
  (full CI-identical gate confirmed at `9219a69a`; `03c59904` is the
  docs-only report-status follow-up).
- **Mechanical checks**:
  - `make format` clean, `make lint` → 0 violations / 0 serious across 214 files.
  - Full `./scripts/test.sh` gate **PASS** at `9219a69a` via the `run-gate`
    async managed worktree (SIM pinned by UDID `D8020BD8-…`, watch 26.5 UDID
    unpaired): deployment-target checks, format, `swiftlint --strict`, warning
    self-test (20 fixtures), iOS + watch builds, Periphery (`No unused code
    detected`, zero findings), iOS UI tests, watch UI tests, watch unit tests,
    macOS unit tests, warning epilogue → `✅ All CI checks passed.`
  - Targeted macOS `EntitlementStoreTests` pre-check: 8/8 passed on this dirty
    host; the canary recorded an *expected failure* (`withKnownIssue`) as
    designed.
  - Gate worktree torn down and its `pi-subagents/gate-576dd88-…` branch
    deleted (reachable from the pushed ticket branch).
- **Review outcome** (one bounded `reviewer`, fresh context, report citations
  cross-checked by hand):
  - **Blocker B1 fixed** — `audit-report.md` §6 was stale after commit
    `4180ee4d`: rewritten as "Host StoreKit store — dirty-host accommodation"
    with corrected lines (`:43`, `:83`, `:108`, `:129`) and the non-failing
    canary semantics.
  - **Fix applied** — `hostStoreKitIsClean()` is no longer a discarded read: it
    reports a dirty host as a `withKnownIssue` carrying the old actionable
    "Clear via Xcode → Debug → StoreKit → Manage Transactions…" message, so
    the signal is visible while CI can never be turned red by host state
    (your explicit requirement). Verified live on this machine.
  - **Reviewer false positive rejected** — the claimed §2a/§4 citation drift
    (`ShowDateState`, `ShowEnableActionButtonsState`, `AppGroup.defaults`) was
    checked against source and is correct as written; no edit made.
  - **Declined / deferred** — N1 (no-op `waitUntil { emitted.count == 1 }`)
    and the F2 guard comment were not applied; both are cosmetic.
  - Report status updated to "Confirmed — full gate passed at `9219a69a`".
- **Remaining manual items** (for you, not blocking merge):
  - Build + run the iOS app, add the "Next Thing" widget to a simulator home
    screen, confirm it renders a reminder or the no-access message (behavior
    unchanged by the Phase 2 extraction).
  - Optionally comment out one preference read in
    `NextThingDisplayPreferences` locally and confirm a unit case fails, to
    prove the tests bind to the extraction (red-first check).
  - **User triage decision** on audit-report §4: the five watch `Show*State`
    holders persist to `UserDefaults.standard` while
    `ShowEnableActionButtonsState` uses `AppGroup.defaults` — intentional
    (watch-local) or a latent bug? Left recorded, not fixed.