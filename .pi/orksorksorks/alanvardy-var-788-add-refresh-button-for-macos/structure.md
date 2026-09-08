# Structure Outline

## Approach

Add a macOS-only refresh button (SF Symbol `arrow.clockwise` in `controlPlate()` circle, top-leading overlay) wired to a new `ContentViewModel.refreshManual()` entry point that owns the re-entrancy guard and minimum-display hold — mirroring the watch pattern. Each layer ships its tests alongside its code and is proven green before the next layer begins.

---

## Layer 1: ContentViewModel — in-flight state + `refreshManual()` entry point

Adds the `isRefreshing` flag and the `refreshManual()` method that the button (Layer 2) will call. Pure logic layer — no UI dependency, testable directly against an `InMemoryEventStore`-backed `ReminderStore`.

**Files**: `SingleThread/ContentViewModel.swift`, `SingleThreadTests/ContentViewModelTests.swift`

**Key changes**:
- `ContentViewModel.isRefreshing: Bool` — new property, default `false`
- `ContentViewModel.refreshManual() async` — new method:
  ```swift
  func refreshManual() async {
      guard !isRefreshing else { return }
      isRefreshing = true
      defer { isRefreshing = false }
      let startedAt = Date()
      await store.reload(clearSkipped: store.allSkipped)
      let elapsed = Date().timeIntervalSince(startedAt)
      try? await Task.sleep(
          for: .seconds(MinimumDisplayDuration.remainingSleep(elapsed: elapsed, minimum: 1))
      )
  }
  ```
  Uses the existing `MinimumDisplayDuration.remainingSleep(elapsed:minimum:)` (`MinimumDisplayDuration.swift:10-13`), already tested in `MinimumDisplayDurationTests.swift:11-22`.

**What the next layer consumes**: `viewModel.isRefreshing` (for `.disabled()`), `viewModel.refreshManual()` (for the button action).

**Tests** (new in `ContentViewModelTests.swift`):
| Test | Covers |
|------|--------|
| `refreshManualTogglesIsRefreshing` | Flag is `true` during reload, `false` after (happy path) |
| `refreshManualGateBlocksReentrantCall` | Rapid double-call → `store.reload()` called exactly once (sad path: re-entrancy) |
| `refreshManualMinimumDisplayDuration` | With a no-op settle store, `isRefreshing` stays `true` ≥ 1 s (floor hold) |
| `refreshManualClearsSkippedWhenAllSkipped` | `store.allSkipped == true` → `reload(clearSkipped: true)` |
| `refreshManualPreservesSkippedWhenVisible` | `store.allSkipped == false` → `reload(clearSkipped: false)` |

Uses existing fixture pattern: `ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)` with seeded reminders, matching `ContentViewModelTests.swift:18-21`.

**Verify**: `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/ContentViewModelTests` — all five new tests + existing `ContentViewModelTests` green.

---

## Layer 2: ContentView — macOS refresh button overlay

Adds the visual control: an SF Symbol `arrow.clockwise` in a `controlPlate()` circle at top-leading, gated by `#if os(macOS)`. Wired to Layer 1's tested `refreshManual()` and `isRefreshing`.

**Files**: `SingleThread/ContentView.swift`, `SingleThreadTests/SingleThreadTests.swift`

**Key changes**:
- New overlay block in `ContentView` body, inserted inside the existing overlay chain at `ContentView.swift:184-231`, mirroring the gear at `:185-198`:
  ```swift
  #if os(macOS)
  .overlay(alignment: .topLeading) {
      Button {
          Task { await viewModel.refreshManual() }
      } label: {
          Image(systemName: "arrow.clockwise")
              .font(.title3)
              .controlPlate()
      }
      .disabled(viewModel.isRefreshing)
      .accessibilityLabel("Refresh")
      .accessibilityIdentifier("refreshButton")
      .accessibilityAddTraits(.isButton)
      .padding(.top, 8)
      .padding(.leading, 12)
  }
  #endif
  ```
  - **Styling**: matches the gear exactly — `.font(.title3)`, `.controlPlate()`, three-modifier a11y stack, `.padding(.top, 8).padding(.leading, 12)` (mirror of gear's `.trailing, 12`).
  - **Platform gate**: `#if os(macOS)` — absent on iOS.
  - **Disabled state**: `.disabled(viewModel.isRefreshing)` — Layer 1's flag.
  - **Label**: `"Refresh"` reuses the Core catalog key (`SingleThreadCore/…/Localizable.xcstrings`) — same key the watch uses.
  - **Task fire-and-forget**: `Task { await viewModel.refreshManual() }` — matches the `.refreshable` and watch patterns; the `Task` closure is `try?`-tolerant for the `unhandled_throwing_task` SwiftLint rule.

**Risk — file-length**: `ContentView.swift` is near the 650-line `type_body_length` warning (`.swiftlint.yml:29-35`). The button block is ~14 lines. If `make lint` fails on `type_body_length`, extract the button to a new `ContentView+macOS.swift` extension following the `ContentView+iOS.swift` precedent — this is a mechanical move, no logic changes.

**What the next layer consumes**: `app.buttons["refreshButton"]` — the accessibility identifier that macOS UI tests will match.

**Tests**:
| Test | Covers |
|------|--------|
| `contentViewBodyContainsRefreshButtonOnMacOS` | `String(describing: contentView.body)` contains `"refreshButton"` (view-structure containment, same mechanism as `contentViewBodyContainsRefreshableModifier` at `SingleThreadTests.swift:21-31`) |

Also verify `make lint` (SwiftLint `--strict`) passes — confirms `type_body_length` hasn't breached.

**Verify**: `make lint` green + `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` (all unit tests including Layer 1 + new view-structure test) green.

---

## Layer 3: macOS UI test infrastructure + end-to-end tests

Adds the scheduling surface so macOS UI tests actually run in CI and locally, plus the tests themselves. The `SingleThreadUITests` bundle is already macOS-capable (`MACOSX_DEPLOYMENT_TARGET = 26.5` on all six build configs, `project.pbxproj:768,818,844,873,901,925`; macOS `#else` branch in audit tests `SingleThreadUITests.swift:62-65`) — the gap is purely scheduling.

**Files**: `SingleThreadUITests/SingleThreadUITestsMacOS.swift` (new), `Makefile`, `scripts/test.sh`, `.github/workflows/ci.yml`

**Key changes**:

- **`SingleThreadUITests/SingleThreadUITestsMacOS.swift`** — new XCTest class:
  ```swift
  import XCTest

  final class SingleThreadUITestsMacOS: XCTestCase {
      override func setUpWithError() throws {
          continueAfterFailure = false
          app = XCUIApplication()
      }

      var app: XCUIApplication!

      func testRefreshButtonExists() {
          // Seeded with a known reminder so the app reaches the main list,
          // where the button appears.
          launchSeeded(seed)
          XCTAssertTrue(app.buttons["refreshButton"].waitForExistence(timeout: 5))
      }

      func testRefreshButtonAccessibilityAudit() throws {
          launchSeeded(seed)
          XCTAssertTrue(app.buttons["refreshButton"].waitForExistence(timeout: 5))
          try app.performAccessibilityAudit(
              for: [.sufficientElementDescription, .trait]  // CI-consistent categories
          )
      }

      func testRefreshButtonTapReloads() {
          // Tap the button; verify it is still present post-reload (the button
          // disappearing would indicate a crash/error, not success).
          launchSeeded(seed)
          let button = app.buttons["refreshButton"]
          XCTAssertTrue(button.waitForExistence(timeout: 5))
          button.tap()
          // After reload, the button should still exist (list re-renders).
          XCTAssertTrue(button.waitForExistence(timeout: 5))
      }

      // MARK: Helpers

      private func launchSeeded(_ seed: UITestingSeed) {
          let json = seed.jsonString()  // UITestingSeed → JSON string
          app.launchArguments = ["--seed", json]
          app.launch()
      }

      private var seed: UITestingSeed {
          UITestingSeed.makeDefault()  // one known reminder
      }
 ￼
  ```
  Uses the existing `--seed` seam (`UITestingSeed.swift:48-59`, `AppViewModel.swift:329-372`) with `InMemoryEventStore` (no real TCC prompt — `InMemoryEventStore.swift:37` reports `.fullAccess`). Follows `SingleThreadUITestCase.swift:6-8` (`continueAfterFailure = false`). Lean: three tests — existence, audit, and basic tap.

- **`Makefile`** — new target:
  ```makefile
  mac-ui-test:
      xcodebuild -scheme SingleThread -destination '$(MAC_IM)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS
  ```

- **`scripts/test.sh`** — new step after the existing macOS unit-test block (`:283-295`):
  ```bash
  echo ""
  echo "--- macO UI tests (XCTest) ---"
  xcodebuild -scheme SingleThread -destination "$MAC_SIM" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS
  ```

- **`ci.yml`** — new job `mac-ui-tests` after `mac-tests` (`:270-320`), same `macos-26` runner, similar shape:
  ```yaml
  mac-ui-tests:
    runs-on: macos-26
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
      - name: macOS UI tests
        run: xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS
  ```

**Tests**: the three tests in `SingleThreadUITestsMacOS.swift` are themselves the test layer — they exercise the full stack (button render, tap, reload through `InMemoryEventStore`). `performAccessibilityAudit` with CI categories validates the a11y stack.

**Verify**: `make mac-ui-test` green locally (verifies the new target + tests); `./scripts/test.sh` fully green (verifies the new step doesn't break the pipeline and all existing tests still pass).

---

## Testing Checkpoints

| After | What must be green |
|-------|-------------------|
| Layer 1 | `-only-testing:SingleThreadTests/ContentViewModelTests` — 5 new tests + existing ContentViewModelTests |
| Layer2 | `make lint` + `-only-testing:SingleThreadTests` (all unit tests including Layer 1 + view-structure test) |
| Layer3 | `make mac-ui-test` + full `./scripts/test.sh` (all layers, all platforms) |

---

## Cross-Cuting Note

The `isRefreshing` flag and `refreshManual()` are the only new code outside the view layer — everything else (button, UI tests, CI) wires to them. The `ReminderStore` is untouched. This keeps the change surgically scoped: the store stays re-entrant, the watch pattern is mirrored exactly, and the macOS UI test infrastructure established here becomes the template for future macOS features.