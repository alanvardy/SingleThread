# Task

Extend `scripts/run-devices.sh` so the build-and-install script covers all
four device platforms: iPhone, iPad, macOS, and Apple Watch. iPhone/iPad
(via devicectl iOS discovery) and macOS (host build + launch) legs already
exist; the missing work is a watchOS leg — discovering a paired real Apple
Watch with `xcrun devicectl`, building the installable watch app, and
running the install + launch for it.

The watchOS real-device mechanics are unproven and hardware-gated, so the
research phase must establish (a) how `run-devices.sh` works today, (b) how
the watch target is configured and built, (c) what identity the phone and
watch must share, and (d) how devicectl represents and installs onto a real
watch — before an approach can be committed to.
