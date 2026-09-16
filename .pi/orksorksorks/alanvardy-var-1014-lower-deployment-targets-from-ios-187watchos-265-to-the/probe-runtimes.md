# Probe runtimes — Phase 1 (iOS 17.0 floor proof)

## Runtime availability investigation (2026-09-16)

**Attempted**: `xcodebuild -downloadPlatform iOS -buildVersion <v>` for every
candidate below. **Result**: the Xcode 27.0 (27A266a) download catalog serves
**only iOS 26.x / 27.x runtimes**; every pre-26 release was rejected:

| Version | Result |
|---|---|
| 17.0, 17.2, 17.4, 17.5, 17.5.1, 17.6, 17.6.1 | `not available for download` |
| 18.0, 18.2, 18.3, 18.4 | `not available for download` |
| 19.0, 20.0 | `not available for download` |
| 21.0, 22.0, 23.0, 24.0, 25.0 | `not available for download` |
| 26.0 (23A343) | ✅ served, downloaded (7.99 GB) |

No `iOS 17.x Simulator Runtime.dmg` exists locally to import via
`xcrun simctl runtime add`; no older Xcode app is installed. Xcode is
27.0 (`/Applications/Xcode.app` only), matching AGENTS.md's "Local Xcode
27.0 vs CI 26.6" note.

## ⚠️ NAMED VERIFICATION GAP

The task/design wants the app *runtime-verified on an actual pre-Liquid-Glass
OS* (iOS 17.x runtime). **No pre-26 iOS runtime is obtainable in this
environment** (catalog refuses all of 17.x–25.x; no importable .dmg; no older
Xcode). Per `plan.md` Phase 1 fallback, this is a **named gap**, not hidden:
- The compile-time red probes (1a/1b/1c) are **unaffected**: availability
  diagnostics come from SDK annotations + the deployment target, not from the
  sim runtime.
- The green runtime leg degrades to the **strongest available (oldest)**
  runtime: **iOS 26.0 (23A343)**, which is still Liquid-Glass line but older
  than the local default 26.5 — it verifies install/build/launch on a
  non-default-dot runtime only.
- A genuinely pre-Liquid-Glass (iOS ≤ 25.x) run remains unverified locally;
  the PR body (Phase 3) must state this gap.

## iOS 26.0 probe device

- Device: `Probe iPhone 15 (26.0)`
- UDID: **`DD998B17-B378-4CD2-8D51-6A89FE96ABB0`**
- Runtime: `com.apple.CoreSimulator.SimRuntime.iOS-26-0` (26.0 — 23A343)
- Device type: `com.apple.CoreSimulator.SimDeviceType.iPhone-15`
- Booted: yes

```
IOS17_SIM='platform=iOS Simulator,id=DD998B17-B378-4CD2-8D51-6A89FE96ABB0'
```

(The plan's `IOS17_SIM` name is retained for drop-in substitution in commands;
the underlying runtime is 26.0, not 17.x — see the named gap above.)

## Smoke-launch outcome (iOS 26.0 sim)

Bundle id `app.alanvardy.SingleThread`, built at landed floors (17.0/11.0/26.5)
and installed into the `Probe iPhone 15 (26.0)` device. Observed via
`simctl launch` + `log show`:

- App launches and stays alive (`launchctl list` shows
  `UIKitApplication:app.alanvardy.SingleThread` with exit state 0; no crash).
- **EventKit authorization prompt appears**: SpringBoard log shows
  `Received request to activate alertItem: <SBUserNotificationAlert … title: "SingleThread" would like to access your Reminders…>` and the app log
  shows `(EventKit) Requesting full access to reminders`.
- Prompt **grant** path (`simctl privacy … grant reminders` then relaunch):
  app relaunches, fetches reminder lists (`REMStore Invocation`,
  `FETCH START {name: REMEventKitBridgingDataViewInvocation_fetchLists}`), and
  stays alive — the reminder-list path renders without crash. (Deny path not
  exercised; grant path confirmed enough for the smoke goal on the degraded
  runtime.)
- Screenshots saved locally at `/tmp/launch-26.png`, `/tmp/launch-26b.png`,
  `/tmp/launch-26-granted.png` (not committed).

Caveat (repeat of the named gap): this is iOS **26.0**, not a pre-Liquid-Glass
runtime — it validates the launch/authorization/fetch path on a non-default
(older) dot release only.

## Green suite-run detail

Plan step 6 names `scripts/test-one.sh SingleThreadTests/EventKitStoringTests`,
but there is no suite with that name: `SingleThreadTests/EventKitStoringTests.swift`
contains `ReminderStoreWriteTests` (12 ran), `ReminderStoreLifecycleTests` (9 ran)
and `ReminderStoreAvailableListsTests` (2 ran) — plus `ReminderStoreTests` (34 ran).
Each printed `ok: N case(s) ran` with N > 0, satisfying the plan's intent. The
raw plan spelling `…/EventKitStoringTests` matches zero cases and exits 1;
the real suite names were used instead.