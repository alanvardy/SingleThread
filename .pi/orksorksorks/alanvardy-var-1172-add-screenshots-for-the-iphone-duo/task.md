# Task

Extend `scripts/appstore-screenshots.sh` — currently a simulator-based capture
pipeline for iPhone 6.3", iPad 13", and Apple Watch Series 11 — to also
produce App Store screenshots for the foldable iPhone Duo, on both its inner
and outer displays, in portrait and landscape, carrying the same six screens as
the existing iPhone class.

Per the `app-store-screenshots` skill the Duo's spec pairs are outer
1398 × 2034 and inner 2007 × 2853; the app's Duo outer-display layout detection
(machine `iPhone19,4`) fails safe to the standard layout on the simulator, so
capturing a faithful Duo layout implies a new capture surface (physical device
and/or an app launch seam).
