# Task — Work on settings in macOS

In the macOS build of the SingleThread app, opening a submenu inside the
Settings sheet (for example "Interface") renders the submenu's title and back
button almost vertically centered instead of flush with the top of the
settings panel. The fix should place the subtitle and back button at the top
of the settings card for every sub-settings screen inside the Settings sheet.

This is a navigation/layout fix on the shared iOS+macOS Settings UI; there is a
draft PR (github.com/alanvardy/SingleThread/pull/151) for this work.