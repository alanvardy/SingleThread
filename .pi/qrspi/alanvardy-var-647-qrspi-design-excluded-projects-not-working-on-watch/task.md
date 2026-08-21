# Task: Excluded projects not working on watch (VAR-624)

Adding a project to the exclusion list on the iPhone does not hide that project's
reminders on the Apple Watch, even several minutes later. The fix must ensure that
excluded-project state (titles) set on one device propagates to the watch and that the
watch's live reminder flow is refreshed to honor it — matching how the other synced
preferences (skip set, sort option, show-undated, show-date) already behave across the
phone↔watch WatchConnectivity sync.

The underlying feature (VAR-619, "Exclude Projects") is already implemented: phone and
watch both wire `onExcludedProjectsChanged → pushExcludedProjectTitles`, the sync service
saves received titles to an `ExcludedProjectStore`, and `ReminderStore` filters by
`excludedProjectTitles` in `visibleReminders` and refreshes the set during `reload()`.
This task is a bug fix on top of that working feature.