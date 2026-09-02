# Research Questions

## Context

The freemium purchase flow spans SingleThreadCore (`EntitlementStore`, `ReminderStore.canMutate`, `CompletionCounterStore`) and the iOS app's view layer (`ContentView.bottomBar`, `UpgradePromptButton`, `PurchaseSettingsView`), with the entitlement flag also synced to the watch over WatchConnectivity. Related test coverage lives in SingleThreadTests (`EntitlementStoreTests`, `EntitlementSyncTests`) and SingleThreadUITests (`SingleThreadUITestsFlows`). Focus on how the entitlement flag is derived, rendered, and tested across these layers.

## Questions

1. Trace how `EntitlementStore.isEntitled` gets its value from process start to the first view evaluation: where is it initialized, when is the first StoreKit refresh triggered relative to app boot, and what is its value before that refresh completes? Include the `init()` observation task, `refreshEntitlement()`, `observeTransactionUpdates()`, and `sync()` in the trace.

2. How does `EntitlementStore.isEntitled` flow into `ReminderStore.canMutate`, and how does `ContentView.bottomBar` decide between the action cluster, the mic button, and `UpgradePromptButton`? Map the full condition chain (`canMutate`, `canDictate`, `showsActionButtons`, `showMicrophoneButton`) and the platform branches (`os(iOS)` / `os(macOS)`).

3. What patterns already exist in this codebase for deferring UI until an async or unknown state is settled — e.g. `ReminderStore.authorizationStatus` (`.notDetermined` → `ProgressView`), `PurchaseSettingsView`'s product loading (nil → "Loading…"), and any other loading/not-yet-known states? How do views using `@Observable`, `.onChange(of:)`, `@State`, and `Binding` typically react to late state transitions?

4. Is entitlement ever persisted or cached locally, or is `isEntitled` always re-derived from `Transaction.currentEntitlements` on every process start? What does `EntitlementStoreTests.isEntitledSurvivesStoreRecreation` and `isEntitledIsFalseByDefault` reveal about the intended initial-state contract, and how do the unit tests drive real StoreKit APIs (`SKTestSession`)?

5. How is the entitlement flag shipped to the watch (`EntitlementState.apply`, `SkippedReminderSyncService.onEntitlementReceived`, context-push keys in `AppViewModel.setupEntitlementObservation`), and how is `isEntitled` initialized and updated on the watch side? If the iOS flag's lifecycle or initial value changed, which sync tests and watch code paths would be affected?

6. What test seams exist for driving entitlement state — `EntitlementStore(testingWithEntitled:)`, the `--seed` launch arg's `isEntitled` field, `InMemoryEventStore` — and how do the existing UI tests (`testUpgradePromptAppearsWhenGated`, `testSettingsHasPurchaseRow`, `testPurchaseSheetHasRestoreButton`) set up and assert gated versus entitled rendering? What startup-timing behavior can these seams actually observe (e.g. `waitForExistence`)?