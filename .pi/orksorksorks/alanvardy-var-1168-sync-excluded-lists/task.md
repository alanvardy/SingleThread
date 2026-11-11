# Task

Sync the excluded-lists feature to iCloud. Today excluded/skipped reminders are
persisted in the shared App Group `UserDefaults` and propagated only between the
paired phone and watch over WatchConnectivity, so they do not sync across a
user's devices via iCloud.

Introduce iCloud-backed storage for the excluded lists that coexists with the
existing App Group/WatchConnectivity path.
