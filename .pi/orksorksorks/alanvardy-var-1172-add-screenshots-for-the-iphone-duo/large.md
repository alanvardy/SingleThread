# Task

Extend `scripts/appstore-screenshots.sh` — currently a simulator-only capture
pipeline for iPhone 6.3", iPad 13", and Apple Watch Series 11 — to also produce
App Store screenshots for the foldable **iPhone Duo**. The Duo captures must
carry the same six screens as the existing iPhone class
(`1-main-dark`, `2-empty-dark`, `3-options-light`, `4-options-reminder-dark`,
`5-main-light`, `6-no-reminders-dark`), for **both the inner and the outer
display**, in **both portrait and landscape**. Per the `app-store-screenshots`
skill the Duo's spec pairs are **outer 1398 × 2034** and **inner 2007 × 2853**,
and the app already distinguishes the outer display via
`DuoDisplay`/`DuoOuterPortrait` (machine `iPhone19,4`), a path that deliberately
fails safe to the standard layout on the simulator.

## Why LARGE

**UNKNOWNS + NEW_SURFACE + CONVENTION_RISK.** There is no iPhone Duo simulator
device type (`simctl list devicetypes` has none; the only Duo is the physical
device identified by `uname` as `iPhone19,4`), so how a `simctl`-based script
captures it at all — inner vs outer, folded vs unfolded, portrait vs landscape —
is unresolved, and the app's Duo-specific layout detection cannot fire in the
simulator (falls back to `.standard`). Shipping this means a new capture surface
(physical-device path and/or an app launch seam to force Duo inner/outer +
orientation), new committed wallpaper slots/manifest entries, output-tree and
size-verification changes for the two new pixel pairs, and a design decision
about the Duo-class upload support, which the skill currently records as **not
live in App Store Connect** ("ignore it").
