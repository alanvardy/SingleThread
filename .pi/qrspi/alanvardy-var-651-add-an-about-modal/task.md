# Task: Add an About modal (VAR-651)

Add an "About" entry to the main app's Settings screen that opens a modal/screen
presenting author and copyright information: "Copyright 2026 Alan Vardy" and a
"Made with love by a lone developer" line. The modal should also investigate
whether the author is permitted to include a personal email address for user
feedback (routing any such link through the app's existing link-handling
pattern), and should display the app's version/build metadata sourced from the
bundle. This is a user-facing iOS/macOS surface; the watchOS target has no
settings surface today.