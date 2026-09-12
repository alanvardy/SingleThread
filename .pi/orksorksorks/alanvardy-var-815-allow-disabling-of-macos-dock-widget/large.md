# Task

SingleThread currently has no way to remove its widget from the macOS dock — the user wants a macOS-only setting in the Settings menu that disables it. The feature must add that toggle (macOS-only surface), persist the choice, and make the dock widget's presence on macOS honor it.

## Why LARGE

Matched triggers: **UNKNOWNS**, **NEW_SURFACE**, **CROSS_CUTTING (unknown ordering)**, with **CONVENTION_RISK** secondary.

- UNKNOWNS: codebase recon found **zero in-repo references to any macOS dock widget** (no "dock" symbol anywhere in source; the only WidgetKit widget, `NextThingWidget`, is iOS-only via `platformFilter = ios` and `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`). How the dock widget appears on macOS — system-hosted widget surface vs. app-launched, and what API/mechanism governs showing/hiding it — is unknown and needs research/spike before any implementation approach exists. The disable mechanism itself (runtime toggle vs. build/registration change) is an open design question.
- NEW_SURFACE: there is no existing dock-widget integration/gating code to extend; the feature introduces a new interface between the settings surface and the macOS dock-widget presence.
- CROSS_CUTTING (unknown ordering): touches the Settings UI (macOS-only toggle), the macOS platform surface (dock widget), and settings persistence — with no existing pattern carrying this exact shape end to end (recon found no macOS dock code of any kind; the closest precedent, `enableActionButtons`, is a different shape).
- CONVENTION_RISK: persistence lives in the shared `UserDefaults`/`AppGroup.defaults` conventions (watch-synced vs `.standard`-local), and the choice of where this macOS-only boolean lives must respect the App-Group round-trip rule.