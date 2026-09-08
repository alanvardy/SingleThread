# Design Discussion

## Current State

The app is a free Reminders client with no monetization, no StoreKit code, and
no usage counter (`research.md:Q1`, final observation). Reminders flow through
a single `ReminderStore` (`ReminderStore.swift:145`) with per-platform branches
(iOS → EventKit save, watch → local removal + relay, widget intent → fresh
store + EventKit save or App Group write). Shared state lives in 9 App Group
`UserDefaults` keys, each backed by a `struct Preference` store
(`ShowCompletionGlowPreference.swift:11–27`) and synced phone→watch via
`SkippedReminderSyncService` (`SkippedReminderSyncService.swift:146–174`).
Settings are plumbed `struct ⇄ @AppStorage ⇄ SettingsBindings bag ⇄ sheet
write-back ⇄ pushAll()` (`research.md:Q4`). Tests use Swift Testing with
store injection + `--seed` launch-arg seam for UI-test mutation flows
(`UITestingSeed.swift:27–36`, `SingleThreadUITestsFlows.swift:216–221`).

## Desired End State

After a full freemium gate that counts completions and offers a $2.99 one-time
non-consumable IAP unlock. Verification:

- **Counter**: a new `completionCount` key in App Group `UserDefaults`, 0→100,
  incremented exactly once per successful EventKit save inside
  `ReminderStore.completeReminder`, never on watch-local optimistic removal or
  widget skip. Unit tests confirm key isolation, cap transition, and
  recurring-reminder dedup.
- **Gate**: when `completionCount >= 100` AND `!isEntitled`, Complete/Skip/Delete
  are refused at the model layer (all surfaces). The ContentView action cluster
  is replaced by an upgrade prompt; watch shows "Upgrade on iPhone."
- **Unlock**: `StoreKit 2` non-consumable IAP. `ProductView` presented from
  iPhone only; "Upgrade / Manage Purchase" row in Settings; "Restore Purchases"
  via `AppStore.sync()`. Entitlement state lives in a new
  `EntitlementStore` and syncs to watch over WatchConnectivity.
- **Local dev**: `Products.storekit` wired into Debug scheme LaunchAction.
  Unit tests (Swift Testing) cover counter semantics, cap transition, restore
  path, re-count-after-purchase; UI tests (`--seed` seam) verify unlock flow
  renders after cap and actions re-enable post-purchase.

## Patterns to Follow

1. **New store-struct: `CompletionCounterStore`** — `init(defaults: UserDefaults
   = AppGroup.defaults, key: String = "completionCount")`, with `var count: Int`
   (reads `defaults.integer(forKey:)` — safe, 0-defaulted), `func increment()`
   (sets `count + 1`), and `func resetForTesting()`. Follows the injectable-defaults
   pattern from `ShowCompletionGlowPreference.swift:11–27` and
   `SkippedReminderStore` at `ReminderSkip.swift:121–135`. Tests use unique UUID
   keys for isolation (`ExcludedListStoreTests.swift:9–12`).

2. **New store-struct: `EntitlementStore`** — `@MainActor @Observable` class
   holding `var isEntitled: Bool`. Listens to `Transaction.updates` (StoreKit 2
   stream). `ReminderStore` takes it as an injectable dependency alongside
   `skipStore` / `excludeStore` (`ReminderStore.swift:14–16`). `Observable` so
   SwiftUI views react to entitlement changes without polling.

3. **Gate in the model** — `ReminderStore` gains a `canMutate` computed property:
   `return entitlementStore.isEntitled || completionCounter.count < 100`. Each
   mutating method checks it: `completeReminder` returns `false` (extends existing
   false-at-`:156` pattern), `skipCurrentReminder` no-ops via `guard`, `deleteReminder`
   no-ops via `guard`. The model enforcement is the safety net covering all
   surfaces including widget intents.

4. **Counter increment point** — inside the `#else` (iOS/macOS) branch of
   `completeReminder` at `ReminderStore.swift:158–162`, after `eventStore.save`
   succeeds and before `return true`. The `#if os(watchOS)` branch never increments
   (no EventKit save). Completes arriving from watch relay re-enter the phone
   branch (`AppViewModel.swift:41–43`) and DO increment. Widget-intent completes
   also run the iOS branch (`ReminderIntents.swift:19–24`) and DO increment. This
   is a single-point-of-truth addition in the convergence point identified by the
   research (`research.md:Q1`).

5. **WatchConnectivity sync for entitlement** — `isEntitled: Bool` added to
   `pushAll()` payload (`SkippedReminderSyncService.swift:146–174`), with a
   new `PayloadKey.entitled` (`:235–247`). Watch receives in `apply(context:)`
   (`:270–325`) → new `handleEntitlementReceived` hook → `EntitlementState` holder
   (modeled on `ShowDateState`, `ShowDateState.swift:21–24`). Phone pushes on
   StoreKit `Transaction.updates` event. Watch never calls StoreKit APIs.

6. **iPhone purchase UI** — `ProductView` presented as a sheet when the gate fires.
   Upgrade row in `SettingsView` (`SettingsView.swift:30–104`) adds a "Purchase"
   NavigationLink to a new `PurchaseSettingsView`. "Restore Purchases" button
   calls `AppStore.sync()`. Follows `SettingsBindings` bag pattern for
   presentation state, `.sheet(isPresented:)` convention from
   `ContentView.swift:109–141`, and Section-based grouping from existing
   `SettingsView` (`:32–95`).

7. **`Products.storekit`** — wired into the Debug scheme's `LaunchAction` as a
   `StoreKitConfigurationFileReference`. No `.xcconfig` files (none exist,
   `research.md:Q5`). Local-only; CI uses `SKTestSession` in unit tests.

8. **Test infrastructure** — counter tests: `@MainActor @Suite(.serialized)`
   suite with UUID-keyed store (`ReminderStoreTests.swift:5–6`,
   `ExcludedListStoreTests.swift:9–12`). Gate tests: inject a pre-seeded
   counter and fake entitlement into `ReminderStore`, assert `canMutate`
   transitions and mutation methods are no-ops when gated. UI tests: `--seed`
   JSON extended with `completionCount` / `isEntitled` fields; verify upgrade
   sheet renders after cap and actions re-enable after purchase sim
   (`UITestingSeedTests.swift:12–67`, `SingleThreadUITestsFlows.swift:21–25`).

9. **Key registration** — `completionCount` and `isEntitled` added to
   `UITestingSeed.persistedKeys` (`UITestingSeed.swift:52–67`), `PayloadKey`
   (`SkippedReminderSyncService.swift:235–247`), and the `@AppStorage` / store
   layer. Maintain the existing string-literal-by-convention discipline.

## Patterns NOT to Follow

- **Raw `UserDefaults.bool(forKey:)` reads** — the widget's `showUndatedReminders`
  read (`NextThingWidget.swift:71`) is a known inconsistency; do NOT replicate
  it. Always go through a store-struct.
- **Watch double-write** — existing `Show*State` holders both save to the
  service store AND call `preference.set()` on receive; do NOT replicate.
  `EntitlementState` should own the canonical `.standard` value and not
  double-persist.
- **Missing `persistedKeys` entries** — `backgroundFadePercent` is missing from
  the reset list; do NOT skip the new keys there.
- **`.disabled(_:)` for broad access control** — the codebase uses conditional
  rendering (`ContentView.swift:383–385, 406–414`) more than `.disabled()`
  (only 2 sites, `research.md:Q3`). Prefer conditional rendering: show upgrade
  prompt in place of action cluster when gated.

## Design Decisions

1. **Dedicated `CompletionCounterStore`**: Option A — new store-struct following
   the existing `Preference` convention. Matches `ShowCompletionGlowPreference`,
   testable in isolation, keeps `ReminderStore` surface small.

2. **Model-level gate**: Option A — `ReminderStore` enforces the gate. All nine
   completion surfaces (iPhone swipe/cluster, context menu delete, watch relay,
   widget intent) converge through `ReminderStore`; enforcing at the model is
   the only way to guarantee one check for all paths.

3. **Increment on EventKit save**: Option A — inside the `#else` branch after
   `eventStore.save` succeeds. Single point for phone, widget, and watch-relay
   completions; watch-local branch never increments (correct, no EventKit write).

4. **Watch entitlement via WatchConnectivity**: Option A — sync `isEntitled` in
   `pushAll()` payload. Watch stores locally, gates actions, shows "Upgrade on
   iPhone" prompt. No silent data loss.

5. **Skip gating on watch**: Option A — skip/deletes are gated when
   `completionCount >= 100 && !entitled`. Free tier gets unlimited
   skips/deletes until the completion cap is hit, then everything gates.

## What We're NOT Doing

- **No subscriptions.** This is a one-time non-consumable IAP.
- **No server-side validation.** The counter is client-side truth (App Group
  `UserDefaults`). It resets on app deletion (standard iOS behavior).
- **No consumable IAPs.** One product, one purchase, permanent unlock.
- **No watch StoreKit UI.** `ProductView` and purchase flow are iPhone-only.
  Watch shows "Upgrade on iPhone" prompt only.
- **No widget skip counting.** Widget `SkipReminderIntent` does not consume
  free completions — only `CompleteReminderIntent` does.
- **No RevenueCat or third-party paywall.** StoreKit 2 native APIs only.
- **No changes to the watch relay's fire-and-forget semantics.** The existing
  `sendMessage(replyHandler: nil)` pattern is unchanged; counter increments
  only when the phone receives and executes the relayed completion.

## Open Risks

- **Watch relay delivery gap**: phone-side counter increment depends on the
  phone receiving the watch's `sendMessage` (`replyHandler: nil`,
  `SkippedReminderSyncService.swift:180`). If the phone is unreachable, the
  watch removed the reminder locally but the counter never increments. Low
  risk — the delivery gap exists today for skip/delete and hasn't caused
  issues; the counter undercounts slightly worst-case, which favors the user.

- **App deletion resets counter**: App Group `UserDefaults` are deleted when
  the last app in the group is removed. A user who deletes and reinstalls
  resets their counter — this is a model-level decision (client-side truth),
  not a bug. The purchase restores via `AppStore.sync()`; the counter does
  not restore.

- **StoreKit 2 greenfield**: no existing StoreKit patterns in the codebase
  (`research.md:Q5`). The `@Observable` `EntitlementStore` listening to
  `Transaction.updates` is a new pattern being introduced. Unit-testing
  StoreKit 2 requires `SKTestSession` and `StoreKitTest` (also new). This
  is the highest-risk area — plan research tasks accordingly.

- **Recurring-reminder counting rule**: "once per reminder" implies a
  recurring-reminder series completion counts once, not once per recurrence
  instance. `EKReminder` has an `isRecurrence` flag — the increment logic
  must check it. The task mentions this rule but does not specify the exact
  dedup mechanism. Clarify during implementation.