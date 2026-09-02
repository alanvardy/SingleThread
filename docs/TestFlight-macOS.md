# TestFlight for macOS — Release & Upload Runbook

How a signed `SingleThread` macOS build gets from this repo into TestFlight. Unlike
the iOS path, a Mac release passes through three distinct gates: **portal capability
setup** (a human, once), the **signed local smoke** (`make mac-run`), and the
**archive/upload** (`make mac-distribute` + Transporter). Steps exist because the
ticket wired the macOS build to sign with the team's certificates and added the
In-App Purchase capability to the App Sandbox entitlements — both of which the
developer portal must know about before anything signs.

## Why the portal step is mandatory first

Phase 1 added `com.apple.developer.in-app-purchases` to
`SingleThread/SingleThread.entitlements`. Provisioning profiles only carry
capabilities that were enabled on the App ID **in the portal** — and the current
Mac team profile for `app.alanvardy.SingleThread` predates that. Until the portal is
fixed, both signed flows fail in one place:

- `make mac-distribute` aborts at `xcodebuild archive` with
  `GatherProvisioningInputs` → *"Entitlement com.apple.developer.in-app-purchases not
  found and could not be included in profile"* (observed during implementation; the
  script itself is sound — the identical archive with `CODE_SIGNING_ALLOWED=NO`
  succeeds).
- `make mac-run` signs with the same profile and hits the same wall.

`--ui-testing`/`--seed` flows and `CODE_SIGNING_ALLOWED=NO` builds (CI, unit tests)
are unaffected.

## Portal prerequisites (human, one-time)

None of these can be done from the repo — they take the certificates, keys, and
portal access that live with the team owner:

1. **Enable In-App Purchase on the App ID `app.alanvardy.SingleThread`** in the
   Apple Developer portal, then **regenerate and re-download the Mac Team
   Provisioning Profile** (and update it in Xcode's signing for the `SingleThread`
   target if needed). This unblocks both `make mac-run` and `make mac-distribute`.
2. **Register the development team in Xcode → Settings → Accounts** and install the
   **Distribution certificate** for team `6NWX2DHB9Q`. Without the cert, even a
   profile-accurate archive stops at export ("no distribution cert found").
3. **Create the macOS app record** for `app.alanvardy.SingleThread` in App Store
   Connect (the iOS record does not double as a macOS one).
4. **Add the `unlimited` non-consumable IAP product** on the macOS record. Its
   product ID must match `EntitlementStore.unlockProductID`
   (`SingleThreadCore/Sources/SingleThreadCore/EntitlementStore.swift`), currently
   `app.alanvardy.SingleThread.unlimited`. Treat the constant as the source of truth —
   if the two ever disagree, StoreKit resolves no products. `Products.storekit` (the
   local dev catalog) and `unlockProductID` remain the single source of truth for
   product identity; nothing else in the codebase hard-codes the id.
5. **Mint an App Store Connect API key** (App Store Connect → Users and Access →
   Integrations). It is used **only** for manual uploads — it is a portal secret and
   must never be checked into CI or this repo.

## Local signed smoke — `make mac-run`

Verifies the signed build end to end against a real `EKEventStore` before anything
is archived:

```bash
make mac-run
```

Checklist:

- [ ] Build completes, signs with automatic `"Apple Development"` / team
      `6NWX2DHB9Q`, and opens `SingleThread.app`
- [ ] `codesign -dv --entitlements - DerivedData/Build/Products/Debug/SingleThread.app 2>&1`
      lists `com.apple.security.app-sandbox`, `com.apple.security.application-groups`,
      `com.apple.security.device.audio-input`, `com.apple.security.personal-information.calendars`,
      **and** `com.apple.developer.in-app-purchases`
- [ ] First launch shows the Reminders TCC prompt; granting it loads reminders
- [ ] Reminders render; complete, skip, and delete work; `c` / `s` keyboard shortcuts work
- [ ] Settings → upgrade surface loads `Products.storekit` products and the unlock
      flow opens (freemium surface exercised against the real store)

If `make mac-run` fails at signing with the profile error above, the portal step is
not complete. If the `DerivedData` app path ever proves non-deterministic between
clean/incremental builds, resolve it via
`xcodebuild -showBuildSettings | grep BUILT_PRODUCTS_DIR` and point `mac-run` at that.

## Build & upload — `make mac-distribute`

```bash
make mac-distribute
```

`scripts/distribute-macos.sh` archives with `generic/platform=macOS` Release and
exports with `exportOptions.plist` (`method = app-store-connect`, automatic signing,
team `6NWX2DHB9Q`). Output lands at `build/SingleThread.pkg`; `build/` is gitignored.

Upload path:

```bash
# via Transporter (Xcode → Xcode Cloud / Transporter app), or App Store Connect web
# > Select the macOS app record > pick build/SingleThread.pkg
```

Then wait for App Store Connect processing, fill out TestFlight compliance, and
submit for beta review. Uploads are intentionally manual: they need the ASC API key
or a logged-in App Store Connect session, not repo state.

## Reference commands (all committed and current)

| Command | What it does |
|---------|--------------|
| `make mac-run` | Builds signed Debug for `platform=macOS` and opens the app (Stage 3 smoke) |
| `make mac-distribute` | `xcodebuild archive` + `-exportArchive` → `build/SingleThread.pkg` |
| `make mac-test` | Runs `SingleThreadTests` on macOS (`CODE_SIGNING_ALLOWED=NO`) |
| `make mac-build` | Builds macOS Debug unsigned (`CODE_SIGNING_ALLOWED=NO`) |

The macOS unit-test run also runs inside the full gate (`./scripts/test.sh`), so a
broken Mac build fails CI, not just the manual runs.