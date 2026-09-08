# Task: Exclude Projects (VAR-619)

Add a control in the settings menu where the user can select multiple projects to exclude from being processed. Reminders belonging to an excluded project should be filtered out of the app's single-thread reminder flow (not shown or acted upon), while everything else continues to work as before.

In this codebase, reminders come from Apple Reminders via EventKit, and "projects" corresponds to the user's reminder lists (calendars). The exclusion should be persisted across launches and kept consistent with the existing state/persistence patterns across the app's surfaces.