---
name: storekit
description: Set up and debug StoreKit in SingleThread — the premium product ID, the StoreKit config file, and sandbox/real-device testing. Use when a purchase does not appear, a debug session shows "nothing to tap", or when editing Products.storekit / EntitlementStore.
---

# StoreKit (SingleThread)

- **Product ID single source of truth**: `EntitlementStore.unlockProductID`
  (`SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`).
  Never hard-code the id in views or dictation code — a mismatch makes
  purchases fail silently ("nothing to tap"). Gate UI on
  `EntitlementStore.isEntitled`.
- Keep `SingleThread/Products.storekit` (the StoreKit configuration file)
  and the scheme's `StoreKitConfigurationFileReference` in sync — the
  storefront simulates exactly what that file lists.
- **Real-device testing**: requires a sandbox tester account added in App
  Store Connect (Users and Access → Sandbox), a build signed for that
  account, and the signed **Paid Applications Agreement** — until then the
  store shows nothing to tap and `SKProductsRequest` returns empty.
- Debug with `PaymentQueue` / transaction logs; the product id flows from
  `PurchaseSettingsView` through `ReminderStore`/`EntitlementStore`.
- **Local host reset**: `make reset-storekit` stops the host `storekitagent`
  LaunchAgent, backs up and clears the encrypted per-user transaction store
  (`~/Library/Group Containers/group.com.apple.storekit/Library/Caches/storeUser.db`
  + `-wal`/`-shm`), then restarts the agent. Use when `make mac-test` fails with
  `isEntitled == true` on a development Mac that has completed purchases.
  `EntitlementStoreTests.hostStoreKitIsClean` guards the suite and names this
  command in its failure message. The macOS unit stage is unsigned
  (`CODE_SIGNING_ALLOWED=NO`), so it reads this real host store — not any
  `SKTestSession` store.
- **var-793 limitation (verified 2026-09-06)**: clearing these files is
  *necessary but not sufficient* — `make mac-test` re-seeds the store from
  account-scoped sandbox state during the run itself, so `isEntitled`
  (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`) and
  `hostStoreKitIsClean` still fail on a dirty host even after
  `make reset-storekit` (also after SIGKILL of all storekit daemons and wiping
  `group.com.apple.appstoreagent` too). This is diagnosed, not silently green.
  The remaining avenue to a locally green suite is Xcode → Debug → StoreKit →
  Manage Transactions… while the development app runs (no CLI equivalent
  exists). Do not chase further file-level resets for this; the entitlement is
  account/daemon-scoped and re-created on first read in the run.