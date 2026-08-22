# Design — Add a Background (VAR-590)

## Current State

- **No networking anywhere.** Zero `URLSession`/`URLRequest`/`BGTask` hits across
  app, Core, watch, widget (`research.md` Q2). This feature introduces the
  codebase's first network path.
- **No file-system storage anywhere** — persistence is exclusively UserDefaults
  wrapper structs in Core bound to `AppGroup.defaults` or `.standard`
  (`research.md` Q3). This feature introduces the first disk-persisted binary.
- Root view: single ZStack, first child `Color.systemBackground.ignoresSafeArea()`
  — the only full-bleed layer; content follows; settings gear is a
  `.overlay(alignment: .topTrailing)` on the ZStack
  (`SingleThread/ContentView.swift:61-88`). A background image slots naturally
  as a new child between the color and the content.
- Appearance is applied at **UIWindow level**
  (`SingleThread/AppDelegate.swift:15-23`), re-applied on activation
  (:45-48). The ZStack background color resolves light/dark automatically;
  any photo layered above it participates without per-view appearance logic.
- Settings state lives as `@AppStorage` in ContentView; SettingsView owns none
  of it (`SettingsView.swift:47-48`). Phone-only cosmetic keys use `.standard`
  (`appearanceMode`, `textSize`, `showMicrophoneButton`,
  `ContentView.swift:184-200`); cross-surface keys use App Group.
- No footer exists on the main Settings Form; only footer precedent is
  `ExcludedProjectsView`'s (`SettingsView.swift:30`).
- Failure convention: mutate observable state only after the throwing op
  succeeds; catch → `Logger` (subsystem `app.alanvardy.SingleThread`) → keep
  prior state (`ReminderStore.swift:141-183`).
- Test seams: `--seed '<json>'` launch args + `InMemoryEventStore`
  (`SingleThreadApp.swift:105-125`); `UITestingSeed.resetPersistedState()`
  removes nine keys from both defaults suites (`UITestingSeed.swift:41-61`).
  Accessibility audit enforces hit regions/dynamic type/labels over layered
  visuals but not contrast (`research.md` Q6).

### Endpoint contract (verified live)

`GET https://vardy.cc/unsplash` → `200 application/json`:
```json
{"url": "https://images.unsplash.com/photo-…?…&w=1080", "photographer": "NEOM",
 "created_at": "2026-08-22 18:23:29"}
```
Fetch is two-step: JSON metadata, then JPEG download from `url`.

## Desired End State

1. On iPhone/iPad, the main reminder list renders over a nature photograph at
   50% opacity (faded onto the system background), full-bleed under safe areas.
2. First successful fetch populates the photo silently; until then the screen
   looks exactly as today (plain systemBackground).
3. The stored photo refreshes when older than one hour, checked at app launch,
   refreshed in the background — UI never blocks or flashes on refresh.
4. A failed fetch keeps showing the last stored photo (or no photo if none).
5. Settings gains a "Background" toggle (default on) that hides/shows the
   photo without deleting stored data.
6. The main Settings Form shows a footer: "Photo by {photographer} on
   Unsplash" matching the *stored* photo's metadata.
7. Verified by: unit tests for the store (age gating, failure retention,
   toggle) and UI tests for rendering + settings toggle.

## Patterns to Follow

- **Store pattern**: `@MainActor @Observable final class …Store`
  (`ReminderStore.swift:8-9`) with an injected-defaults init and async methods
  kicked off from `.task` (`ReminderStore.swift:124-139`,
  `ContentView.swift:89-92`).
- **Layering**: new image layer as ZStack child between background color and
  content with `.ignoresSafeArea()` (`ContentView.swift:61-68`); do NOT
  introduce `safeAreaInset` or extra windows.
- **Failure handling**: save-to-disk first, then flip observable state; catch →
  Logger category, keep prior value (`SkippedReminderSyncService.swift:120-121`,
  `ReminderStore.swift:141-183`).
- **Async idiom**: plain `async` methods + fire-and-forget `Task {}` from
  MainActor context (`ReminderStore.swift:220-225`); settle delays via
  `try? await Task.sleep` are available but likely unnecessary here.
- **Settings wiring**: `@AppStorage("backgroundEnabled", store: .standard)` in
  ContentView + Toggle in SettingsView taking a Binding, like
  `showMicrophoneButton` (`ContentView.swift:195-196`,
  `SettingsView.swift:124-127`).
- **Footer precedent**: `Section { } footer: { Text(…) }` on a Form
  (`SettingsView.swift:30`).
- **Test injection**: protocol seam + recording fake (pattern of
  `EventKitStoring` / `FakeEventStore`, `EventKitStoring.swift:7-42`);
  isolated per-test state via UUID-keyed or temp-dir suites
  (`AppearanceModeTests.swift:92-94`); add new persisted keys to
  `UITestingSeed.resetPersistedState()` (`UITestingSeed.swift:41-61`).

### Anti-patterns to avoid

- Do NOT route this through `ReminderStore` or the App Group suite — it is
  phone-local cosmetic state (`.standard` at most), never synced to
  watch/widget via `SkippedReminderSyncService`.
- Do NOT block first render on the network (no spinner gating the list).
- Do NOT add per-view light/dark branching for the photo — window-level
  appearance handles surrounding chrome automatically.

## Design Decisions

1. **Architecture — app-layer store**: new `BackgroundImageStore`
   (`@MainActor @Observable final class`) living in `SingleThread/` (app
   target), behind a small protocol seam so unit tests inject fakes.
   Cosmetic phone-only concern stays out of SingleThreadCore; mirrors how
   `AppDelegate`/dictation concerns live app-side. Injected into ContentView
   through its existing convenience-init pattern.
2. **Persistence — Application Support + sidecar metadata**: photo bytes at
   `Application Support/SingleThread/background.jpg`; metadata (photographer
   name, fetched-at epoch) as a sidecar JSON next to it. Durable across cache
   eviction, honoring "keep last successfully stored image". Freshness reads
   the sidecar (no extra UserDefaults keys → no `resetPersistedState()` churn);
   UI tests remove the whole directory instead.
3. **Refresh lifecycle — launch-only**: ContentView's existing `.task` calls
   `await backgroundImage.refreshIfNeeded(maxAge: 3600)` alongside
   `store.start()`. Always render stored bytes immediately; network runs after.
   No `scenePhase` observer (new pattern avoided; hourly staleness doesn't
   justify it).
4. **Rendering — 50% fade onto systemBackground**: ZStack order =
   `Color.systemBackground` → `Image.resizable().scaledToFill()`
   `.ignoresSafeArea()`.opacity(0.5) → content. Photo shows regardless of
   appearance mode; fade against the variant-resolving base color keeps both
   modes readable.
5. **Toggle — default ON, hide-only**: `backgroundEnabled` Bool in
   `.standard` defaults, Toggle in SettingsView. Off hides the image view;
   disk data and credit logic stay intact so re-enabling restores instantly.
6. **Credit — footer from stored metadata**: main Settings Form gets a footer
   Section reading photographer from the store's published metadata ("Photo by
   X on Unsplash"); empty while no photo exists. Credit always matches the
   visible photo because both come from the same sidecar write.
7. **Network client — minimal URLSession usage inside the store**: two
   `URLSession.shared.data(from:)` calls (metadata, then image). Validate
   content-type/HTTP status; reject non-2xx and non-image payloads. No
   third-party deps, no caching layer beyond our own disk copy.

## What We're NOT Doing

- No widget or watch rendering of the background; nothing added to
  `SkippedReminderSyncService` payloads, App Group defaults, or the watch app.
- No image caching library, no Unsplash SDK, no attribution link-out web view.
- No periodic timers, BGTask, or scenePhase-based refreshing — launch-only.
- No user-facing error alerts for failed fetches — silent retention per task.
- No migration/versioning scheme for the sidecar format beyond tolerant
  decoding (missing/corrupt sidecar ⇒ treated as "no valid stored image").
- No change to accessibility-audit scope; contrast between photo and text is
  untested today and remains so.

## Open Risks

- **Readability**: a busy photograph at 50% may hurt reminder-text contrast;
  audit won't catch it. Mitigate during implementation by eyeballing dark/light
  with several photos; opacity constant is a single tunable.
- **Unsplash URL variance**: query params (`crop`, `fit`, `w=1080`) could
  change server-side; validation should key off HTTP status + image decodability,
  not exact params.
- **First-launch flash-in**: photo appears mid-session after first successful
  fetch — acceptable (silent), but confirm it isn't jarring in UI testing.
- **iPad layout**: scaledToFill crops differently across aspect ratios;
  verify on `iPad (A16)` simulator per CI matrix.
