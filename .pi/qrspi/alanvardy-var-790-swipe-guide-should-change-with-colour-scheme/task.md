# Task

The swipe guide on reminder cards (the "Swipe left to skip | Swipe right to complete" hint) is stuck on a fixed dark appearance even when the system or the app's appearance setting is light. The fix should make the swipe guide's colors (plate fill, separators, hint tints, dismiss button) adapt to the active colour scheme — light and dark — the same way the rest of the card UI already does.

The guide must keep its existing behavior: the default-shown visibility, the permanent-dismiss path, the Settings toggle, accessibility labels, and the launch-seam-based UI tests must all continue to work. Existing unit tests that pin the current hard-coded dark fill will need to be updated to match the new adaptive colors.