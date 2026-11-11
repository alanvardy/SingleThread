# Task

Sync the excluded-lists feature to iCloud. Today excluded/skipped reminders are
persisted in the shared App Group `UserDefaults` and propagated only between the
paired phone and watch over WatchConnectivity, so they do not sync across a
user's devices via iCloud. Introduce iCloud-backed storage for the excluded
lists that coexists with the existing App Group/WatchConnectivity path.

## Why LARGE

Triggers: `UNKNOWNS`, `NEW_SURFACE`, `CONVENTION_RISK`, `DESIGN_SIGN-OFF`,
`CROSS_CUTTING (unknown ordering)`, `SCHEMA`. The ticket requires choosing and
integrating an iCloud sync mechanism (CloudKit vs `NSUbiquitousKeyValueStore`),
with conflict/merge semantics, into the existing shared App Group persistence
path (`AppGroup.defaults`) that already syncs phone↔watch over
WatchConnectivity — new integration on shared/convention code with multiple
viable designs and a data-format/back-compat decision, so it needs research,
design, and phased work.
