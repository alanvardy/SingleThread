# Task — Organized Settings menu

The Settings screen is currently a single long `Form` with thirteen
preferences packed together. The goal is to reorganize it into four themed
sub-views reachable by navigation: **Interface** (Appearance, Text size, Allow
landscape, Show microphone, Show action buttons), **Reminder** (Show date, Show
list, Recurrence indicator, Reminder alerts), **Filtering and sorting** (Sort by,
Show undated reminders, Excluded lists), and **Background** (Background, Background
fade, credit for Wallpaper).

The reorganization must preserve the existing persistence, widget reload, and
Apple Watch sync behavior of every setting. The root sheet stays a
`NavigationStack`; the four groups become pushed sub-views following the
established `ExcludedListsView` pattern.