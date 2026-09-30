# Task

Make URLs in a Reminder's **title** and **notes** render as tappable links in
SingleThread, opening in the user's default browser/app. Today
`ReminderDisplay.titleAttributed` / `notesAttributed` flow through
`CodeSpanFormatter`, which only styles backtick code spans and never sets a
`.link` attribute, so URLs are literal text.

Scope IN: `ReminderCardView` (iOS + macOS) and `ReminderDisplayRow` (used by
`FilteredRemindersListView` and the AI Sort Rules preview), for both `title`
and `notes`. Scope OUT: the Watch app (`WatchReminderView`) and the widget
(`NextThingWidget`) — they stay code-span-only (see Known gaps). Both
`ReminderDisplayRow` call sites are plain `Form`s with no row tap or
`NavigationLink`, so there is no tap conflict.

## Detection rules
- Match explicit `http://` and `https://` URLs plus `www.`-prefixed text.
- Scheme matching case-insensitive; normalise scheme to lowercase.
- `www.` without a scheme is normalised by prepending `https://` so it opens.
- Hosts with an explicit scheme match even when not public
  (`http://localhost:3000`, `http://192.168.1.5:8080`).
- Do NOT match bare domains (`example.com`), email addresses, phone numbers.
- Code spans win: a URL inside backticks (`` `https://x.com` ``) stays code.
- Strip trailing `.` `,` `;` `:` `!` `?` `)` `]` `}` only when they are
  unbalanced inside the URL; keep balanced ones (`https://en.wikipedia.org/wiki/Foo_(bar)`).
- Stop the URL at the first character that cannot appear in one
  (`https://x.comを参照` links only `https://x.com`).

## Behaviour and presentation
- Link taps use the system `openURL` action, routed through the app's injected
  `URLOpening` so the existing `--url-opener-spy` seam records it (mirroring
  `ContentViewModel.openInReminders`).
- The scene installs an `OpenURLAction` forwarding to the injected `URLOpening`;
  the handler must call the captured original action to avoid recursion.
- Link runs get explicit accent foreground colour, no underline
  (deterministic under `.foregroundStyle(.secondary)` for notes).
- Notes keep `lineLimit(3)` in the card; links past the cap are accepted.

## Architecture (dictated)
- Refactor `CodeSpanFormatter.format(_:)` into a segmenter:
  `CodeSpanFormatter.segments(in:) -> [Segment]`, where `Segment` is
  `.plain(String)` / `.code(String)`. Preserve code-span behaviour and existing
  tests; internals move.
- New pure `LinkFormatter` in `SingleThreadCore` runs link detection over
  `.plain` segments only and builds the final `AttributedString`.
- `ReminderDisplay` keeps `titleAttributed` / `notesAttributed` (code-span-only)
  and adds `titleAttributedWithLinks` / `notesAttributedWithLinks`. The card and
  `ReminderDisplayRow` adopt the new pair; widget and watch keep the old ones.

## Accessibility
`ReminderCardView.content` collapses via `.accessibilityElement(children: .combine)`,
and inline `Text` links are not exposed to the accessibility tree. Keep
`.combine` and add an `.accessibilityCustomAction` per detected link. Label:
`"Open link to %@"` with the URL's host.

## Localization
Add `"Open link to %@"` to all six languages (`de, en, es, fr, ja, zh-Hans`) in
the `SingleThreadCore` `Localizable.xcstrings`, in the same change.

## Known gaps (do not implement)
- Widget: WidgetKit has no per-run link hit-testing; widget link support is a
  separate feature.
- Watch: out of scope by decision.

## Acceptance criteria
- `LinkFormatter` and the `CodeSpanFormatter` segmenter land in `SingleThreadCore`.
- Table-driven unit tests cover every detection rule, happy and sad paths
  (malformed URLs, unbalanced punctuation, code-span precedence, `www.`
  normalisation, CJK adjacency).
- `ReminderCardView` uses `titleAttributedWithLinks` / `notesAttributedWithLinks`;
  `ReminderDisplayRow` uses `titleAttributedWithLinks` (title only — it never
  renders notes).
- `NextThingWidget` and `WatchReminderView` unchanged, no link affordance.
- Link taps route through the injected `URLOpening`.
- UI test asserting `--url-opener-spy` records the tapped URL, **best-effort**:
  inline links are not addressable via the accessibility tree, so fall back to a
  coordinate tap inside the `Text`; if flaky, drop the UI test and rely on unit
  tests plus manual verification. Document which path was taken.
- `.accessibilityCustomAction` per link; `"Open link to %@"` in all six languages.
- `./scripts/test.sh` passes.
- Manual verification step added to `docs/SimulatorManualVerification.md`.

## Why MEDIUM
MULTI_MODULE breadth: the change spans the `SingleThreadCore` package
(`CodeSpanFormatter` refactor, new `LinkFormatter`, `ReminderDisplay`,
`Localizable.xcstrings`) and iOS/macOS views (`ReminderCardView`,
`ReminderDisplayRow`) plus tests/docs — well over 5 files. M1 (approach known,
no new technology, an existing pattern to follow) and M2 (no schema/migration,
no new subsystem/integration, no design sign-off) hold — the ticket's spec
dictates the architecture, layering, and ordering, so no research or design
phase is needed.

## Key files
- `SingleThreadCore/` — `CodeSpanFormatter` (refactor to `segments(in:)`),
  new `LinkFormatter`, `ReminderDisplay` (`titleAttributed`/`notesAttributed`
  + new `...WithLinks` pair), `Localizable.xcstrings`.
- iOS/macOS app — `ReminderCardView` (card + `content`, accessibility),
  scene/`OpenURLAction` + injected `URLOpening`, `ReminderDisplayRow`.
- `NextThingWidget` / `WatchReminderView` — unchanged (confirm only).
- `SingleThreadTests/` (Swift Testing, table-driven), UI test
  (`--url-opener-spy`), `docs/SimulatorManualVerification.md`.
- Injection seam: `URLOpening` / `--url-opener-spy` via `ContentViewModel.openInReminders`.