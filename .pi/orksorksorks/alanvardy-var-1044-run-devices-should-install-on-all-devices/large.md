# Task

Extend `scripts/run-devices.sh` so the build-and-install script covers all
four device platforms: iPhone, iPad, macOS, and Apple Watch. iPhone/iPad
(via devicectl iOS discovery) and macOS (host build + launch) legs already
exist; the missing work is a watchOS leg — discovering a paired real Apple
Watch with `xcrun devicectl`, building the installable watch app, and
running the install + launch for it.

## Why LARGE
UNKNOWNS (plus a new platform boundary in a multi-platform script): the
watchOS real-device mechanics are unproven and hardware-gated — how
devicectl lists a real watch (platform/deviceType fields, reachability via
the paired iPhone), whether install targets the watch UDID directly or the
companion, and what destination/config/signing + DerivedData product path
the `SingleThreadWatch` scheme needs for a real device — so the watch leg
needs a research/spike pass before an approach can be committed to.