# Done

- **What was built**: `scripts/run-devices.sh` now builds/installs/launches on the
  new iPhone Duo in addition to the iPhone 16 Pro. The iOS discovery filter no
  longer pre-skips a paired physical iPhone/iPad just because Developer Mode is
  off (which is why the Duo — productType `iPhone19,4`, `developerModeStatus:
  disabled` — was silently omitted), and it gained the missing
  `hardwareProperties.reality == "physical"` guard (parity with the watch filter)
  so booted iOS simulators are never treated as install targets. A device with
  Developer Mode off still qualifies and gets an actionable stderr note.
- **Commit SHA(s)**: `0f41f670` (implementation + fixture/tests),
  `f6b7a628` (review fixes: gate wording + end-to-end Duo install flow check).
  Both pushed to `alanvardy-var-1166-add-iphone-duo-to-run-devicessh` (PR #246).
- **Verification**: `bash -n` + `shellcheck -S warning` clean on both scripts;
  `./scripts/test-run-devices.sh` → **21/21 checks pass**, including the new
  offline checks: Duo emitted with Developer Mode off, simulated iOS device
  excluded, Developer-Mode warning, and a control-flow replay asserting
  `iPhone/iPad: 3/3 launched` with the Duo in the set. Also replayed the real
  live inventory (`xcrun devicectl list devices -j`): the Duo and the 16 Pro Max
  are classified, the physical iPad installs, and the ~12 iOS simulators are
  excluded.
- **Reviewer findings**: one bounded `reviewer` pass returned **no blockers**.
  Nits fixed: (1) the zero-device gate's "No iPhone/iPad with Developer Mode
  enabled found." wording was stale once the gate was removed → reworded to
  "No reachable iPhone/iPad found." and its flow-test expectations updated;
  (2) missing end-to-end coverage for the dev-mode-off iOS path → added a flow
  check using the main fixture. No nits deferred.
- **Remaining manual items**:
  - **The Duo's Developer Mode is currently `disabled`** (confirmed live via
    `xcrun devicectl list devices`). The script will now *include* the Duo and
    attempt the install, but `devicectl device install` cannot succeed until the
    setting is enabled on the device: **Settings → Privacy & Security → Developer
    Mode** (then reboot/confirm). This is a device-side action, not a code change.
  - At recon time **both iPhones report `tunnelState: unavailable`** (locked /
    off-network), so they are pre-flighted as *unreachable* and counted as failed
    steps until unlocked and on this Mac's Wi-Fi. The iPad and simulators are
    unaffected.
  - No full CI gate was run (per SMALL scope: targeted verify only). The change
    touches only `scripts/`, so Swift format/lint/unit gates are unaffected.
