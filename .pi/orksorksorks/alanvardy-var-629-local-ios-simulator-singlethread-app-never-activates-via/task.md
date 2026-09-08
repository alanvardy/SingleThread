# Task

Debug why the SingleThread iOS app (Debug build) never reaches the
active/foreground state when launched headlessly on the local iOS Simulator via
`xcrun simctl launch`, on device `iPhone 17` (UDID `D7AC0D41-275E-47C5-B603-BC7FA08D1BB4`,
iOS 26.5). The app process stays alive and `application(_:didFinishLaunchingWithOptions:)`
does fire, but screenshots keep showing SpringBoard and
`applicationDidBecomeActive` / `applicationWillEnterForeground` never fire. Finalize a
report and remediation for the manual on-simulator verification path (cold-launch
appearance, runtime toggling, device-appearance following) so it is unblocked.
Automated verification (unit, UI, accessibility tests; CI) already passes.