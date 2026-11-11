# Done

- **What was built**: `scripts/run-devices.sh` now builds, installs, and launches
  SingleThread on every reachable iPhone/iPad and Apple Watch, including a
  newly paired "iPhone Duo". Two real defects were fixed:
  1. **Discovery**: the iOS filter no longer pre-skips a paired physical
     iPhone/iPad because Developer Mode is off (the Duo reports
     `iPhone19,4` / `developerModeStatus: disabled`), and it gained the missing
     `hardwareProperties.reality == "physical"` guard so booted iOS simulators
     are never treated as install targets.
  2. **Provisioning (the actual install blocker)**: the iOS build lacked
     `-allowProvisioningUpdates` / `-allowProvisioningDeviceRegistration`, and
     the script built once for `generic/platform=iOS`. A generic destination has
     no *destination device*, so a new phone was never registered and its
     install failed with `0xe8008012` ("This provisioning profile cannot be
     installed on this device"). The script now builds **per device** with
     `-destination "id=<udid>"` plus both flags, and the same per-destination
     treatment was applied to the Apple Watch leg (falling back to one generic
     watch build when only an unreachable watch is present). The first device
     compiles; the rest only re-sign against the shared team profile.
- **Commit SHA(s)**: `0f41f670` (discovery filter + fixture/tests),
  `f6b7a628` (review: gate wording + offline Duo flow check), plus the
  per-destination provisioning fix on this branch. PR #246.
- **Verification**:
  - `./scripts/test-run-devices.sh` → **21/21 checks pass** (syntax, shellcheck,
    both discovery filters, all control-flow replays).
  - **Real hardware run** (`RUN_MAC=0 ./scripts/run-devices.sh`): the Duo and the
    iPad were each built at their own destination, installed, and launched →
    summary `iPhone/iPad: 2/2 launched`. Direct checks:
    `xcrun devicectl device install/launch --device 00008160-001C408C34900036`
    both succeeded on the Duo.
  - After registration, the embedded `iOS Team Provisioning Profile` lists all
    five devices (was three) including the Duo `00008160-001C408C34900036`.
- **Remaining manual items**:
  - The Duo's **Developer Mode is now `enabled`** (confirmed live via
    `xcrun devicectl list devices`), so build/install/launch all succeed on it.
  - The iPhone 16 Pro Max is currently `unavailable` (locked/off-network) and
    the Apple Watch tunnel is down; both are counted as failed steps by design
    and are unrelated to this change.
  - No full CI gate was run (the change touches only `scripts/`; Swift
    format/lint/unit gates are unaffected). Gate can run via the `run-gate`
    skill if required before merge.
