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
- **Local host reset**: `make reset-storekit` stops `storekitd`, clears the
  local sandbox transaction store for `app.alanvardy.SingleThread`, and
  restarts the daemon. Use when `make mac-test` fails with
  `isEntitled == true` on a development Mac that has completed purchases
  (see `EntitlementStoreTests.hostStoreKitIsClean` for the canary guard).