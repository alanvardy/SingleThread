# VAR-765 — Add skip pattern nudge

When a reminder has been skipped more than five times, instead of silently cycling
to the next reminder again, the app should surface a gentle prompt asking whether
the user wants to delete it, reschedule it, or break it down into smaller pieces.

Today a skip is recorded as an idempotent identifier in a pruned set — there is no
per-reminder skip count, so the "skipped more than five times" signal does not exist
yet and will require new persisted state. Reschedule and break-down are also not
existing flows today.