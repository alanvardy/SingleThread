# Task — Add a Privacy Guide

The SingleThread iOS app currently exposes no user-facing explanation of the
data it handles. We want to add a "Privacy" guide — a screen reachable from the
Settings screen that explains in plain language what data the app reads,
stores, and syncs (Apple Reminders via EventKit, the shared App Group
UserDefaults, the Watch connectivity sync, and the locally-cached background
image), and how that data is used. The goal is transparency — telling users
that reminders stay on-device / in iCloud and are not sent anywhere else —
presented consistently with the existing settings sub-views and platform
gating (iOS + macOS share one app target; watchOS is separate).