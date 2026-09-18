# Phase 3 Warning Inventory

Captured from three build shapes (`DerivedData/logs/{ios-build,watch-build,mac-unit-test}.log`)
on local Xcode 27.0. Gate: `bash scripts/tests/warning-check/run.sh` passes.

## Distinct warning messages (deduped union)

| # | Diagnostic (message text) | Where | Decision |
|---|---------------------------|-------|----------|
| 1 | `'SKPaymentTransactionState' is deprecated: first deprecated in iOS 18.0 / macOS 15.0 - Use PurchaseResult from Product.purchase(confirmIn:options:)` | `StoreKitTest.framework/Headers/SKTestTransaction.h:34:32` (SDK/toolchain-owned header) | **Allowlist** (existing Phase 1 entry, reconciled) |
| 2 | `'nonisolated(unsafe)' has no effect on property 'observationTask', consider using 'nonisolated'` | `SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift:91:13` | **Source fix** → add `@ObservationIgnored` (keeps `@Observable` from lowering to a tracked peer; plain `nonisolated` is a compile error on the mutable stored property, so this is the only warning-free form — same pattern as `PreferenceHolder.observer`) |
| 3 | `comparing non-optional value of type 'WCSessionUserInfoTransfer' to 'nil' always returns true` | `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:38:40` | **Source fix** → enqueue then `return true` (compiler-proven always-true; the transport always enqueues) |
| 4 | `variable 'view' was never mutated; consider changing to 'let' constant` | `SingleThreadTests/SettingsViewTests.swift:422:17` | **Source fix** → `let view` |

Only 4 distinct items — well under the ~10-item split threshold; no package/SPM
config involved. No split needed.

## Post-fix verification
- After all three source fixes, every build shape compiles with **zero**
  source-located warnings on a fully clean `DerivedData/` (iOS `build-for-testing`,
  watch `build`, macOS unit `test -only-testing:SingleThreadTests`).
- macOS unit-test run exits 65 solely from the three pre-existing
  `EntitlementStoreTests` failures documented in AGENTS.md (isEntitledSurvivesStoreRecreation,
  initialRefreshSettlesResolvedFlag, hostStoreKitIsClean). The earlier
  `SettingsViewTests/showMenuBarExtraDefaultsToShownInBag()` failure was a cascade
  of the `var view` warning (fixed by `let view`); it passes now (25 SettingsViewTests pass).
- StoreKitTest allowlist entry red-first proven: disabled → `check_warnings` exits 1 naming
  exactly the SKTestTransaction.h:34 diagnostic; restored → exits 0.