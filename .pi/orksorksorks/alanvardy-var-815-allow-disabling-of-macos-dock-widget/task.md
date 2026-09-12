# Task

SingleThread currently has no way to remove its widget from the macOS dock — the user wants a macOS-only setting in the Settings menu that disables it. The feature must add that toggle (macOS-only surface), persist the choice, and make the dock widget's presence on macOS honor it.

Key constraints from classify: settings persistence must respect the shared App Group / watch-sync round-trip conventions, and the macOS dock-widget surface has zero existing in-repo precedent (no dock/widget-gallery code exists anywhere in the tree today).