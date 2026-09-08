# Task: Freemium Plan — 100-Completion Counter with $2.99 One-Time Unlock

SingleThread's freemium monetization: track a persistent lifetime completions
counter locally (client-side truth, no server), and gate the app behind a
one-time **$2.99** non-consumable in-app purchase (StoreKit receipt) once the
free tier's 100-completion cap is consumed. The counter is incremented only on
a successful EventKit save, once per reminder, and persists in the shared App
Group `UserDefaults` (same seam as skipped IDs / excluded projects).

All completion paths (iPhone swipe / context-menu / action cluster, watch
relay, widget intend) must share one counter and one entitlement check. When
the cap is hit and the user isn't entitled, Complete/Skip/Delete actions are
gated and route to an upgrade sheet (`ProductView`); an Upgrade / Manage
Purchase row is added to Settings, with Restore Purchases via
`AppStore.sync()`. Purchase UI lives on iPhone only; the watch must funnel
exhausted-cap users to the phone. Widget skips don't consume free completions
(only completion does).

Local dev uses a `Products.storekit` config wired into the Debug scheme; unit
tests (Swift Testing) cover counter semantics, the cap transition, the restore
path, and the recurring-reminder counting rule; UI tests use the `--seed` seam
to verify the unlock flow renders after the cap and actions are disabled
below entitlement.