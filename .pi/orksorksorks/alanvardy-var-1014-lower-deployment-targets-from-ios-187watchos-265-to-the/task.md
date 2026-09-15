# Task

Lower the app's deployment targets from iOS 18.7 / watchOS 26.5 to a proven
lower floor so the App Store listing no longer requires the newest point
release. The hard floor is iOS 17.0 / watchOS 10.0 (pinned by `@Observable` —
23 uses across the four source trees — and by `EKAuthorizationStatus.fullAccess`
/ `requestFullAccessToReminders` in the EventKit store code); the ticket
recommends iOS 17.0 / watchOS 11.0 as the sweet spot, with watchOS 10.0 only
if Series 4/5/SE 1 reach is wanted.

The change must verify the actual floor via re-probing the iOS 16.0 / watchOS
9.0 boundaries, confirm runtime behaviour on pre-Liquid-Glass OS versions, and
pass the full `./scripts/test.sh` gate.