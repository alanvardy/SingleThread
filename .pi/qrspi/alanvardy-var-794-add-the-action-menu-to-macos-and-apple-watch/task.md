# VAR-794 — Add the action menu to macOS and Apple Watch

The three-action menu (Skip / Reschedule / Delete) already exists on all three
platforms behind the `enableActionButtons` toggle, but that toggle is only
reachable from iOS Settings, so the menu is unusable on macOS and Apple Watch
without also running the iOS app. This ticket makes the toggle-gated action
menu reachable on macOS (a Settings row in the macOS settings sheet) and on
Apple Watch (a new control surface — with a design decision on whether the
watch flips the flag on-device and relays it back to the phone, or reads a
phone-authoritative value). The toggle-off path (direct skip) must behave
identically to today.