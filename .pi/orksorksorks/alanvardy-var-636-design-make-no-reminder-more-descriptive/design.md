# Design Discussion

Branch: `alanvardy-var-636-design-make-no-reminder-more-descriptive`
Task: Make the iOS "No Reminders" empty state more descriptive, so a user landing
on it understands the current state and what to do next.

## Current State

- The empty branch is the `else if store.reminders.isEmpty` arm of `reminderList`
  (`SingleThread/ContentView.swift:251`, condition at `:254`). It renders
  `ScrollView { ContentUnavailableView("No Reminders", systemImage: "checklist",
  description: Text("You don't have any reminders yet.")) }` over `bottomBar`
  (`ContentView.swift:253-265`). `ContentUnavailableView` is a SwiftUI framework
  type — three usages, all in `ContentView.swift` (`:228`, `:242`, `:255`).
- The branch fires **solely** on `store.reminders.isEmpty`
  (`ContentView.swift:251,254`). `reminders` is the date-windowed fetch
  (`ReminderStore.swift:150-170`): overdue-up-to-30-days through end of today
  when `showsUndatedReminders` is off, with nil date predicate otherwise.
  Future-dated reminders and (when the toggle is off) undated ones are never
  fetched at all. So a user whose only reminders are future-dated or undated
  sees a misleading "You don't have any reminders yet".
- The all-hidden case is separate: `allSkipped = !reminders.isEmpty &&
  visibleReminders.isEmpty` (`ContentView.swift:181-182`) → "All Done"
  (`ContentView.swift:242`). Persisted skip/exclude sets drive it
  (`SkippedReminderStore` in `ReminderSkip.swift:97-124`,
  `ExcludedProjectStore.swift:8-26`).
- Empty-state affordances today: pull-to-refresh (`.refreshable { await
  store.reload() }`, `ContentView.swift:262`) and the mic/`bottomBar`
  (`ContentView.swift:317-344`, mic at `:348-357`), always layered in this branch.
- Companion surfaces diverge: watch `noRemindersState` is plain `Text("No
  Reminders")` + a labeled `Refresh` button with **no icon or description**
  (`WatchReminderView.swift:110-116`); widget `.empty` passes `message: nil` via
  `messageView` (`NextThingWidget.swift:95-96`).
- The empty state is exercised by previews (`ContentView.swift:470-473`) and the
  `loadsReminders: false` test path (`SingleThreadTests.swift:10,18`); no test
  asserts the placeholder body strings (research Open Areas).

## Desired End State

The iOS empty state becomes contextual. It distinguishes two reasons "no
reminders are showing" and adapts title/body/icon accordingly:

1. **Truly empty library** — the account has no incomplete reminders at all.
   Copy keeps the current shape ("No Reminders" + guidance to add one / refresh).
2. **Reminders exist but are hidden by the view** — there are incomplete
   reminders outside today's date window (future-dated, undated when the toggle
   is off, or older than the 30-day overdue cutoff). Copy says "Nothing due
   today", explains that only today/overdue (and undated, per the toggle) show,
   and offers next steps.

Both arms keep today's affordances (pull-to-refresh + the mic `bottomBar`) and
express actions through copy, not new controls. The same reason signal drives
consistent copy on the watch and widget surfaces.

### Verification
- Unit tests assert the new body strings appear for each sub-state
  (truly-empty vs hidden-by-window) using the `ContentView(loadsReminders:
  false)` + `String(describing: view.body)` pattern.
- The existing accessibility audit (`SingleThreadUITests.swift:24-33`) and
  SwiftLint accessibility rules still pass (descriptions remain `Text`, icons
  stay hidden).
- Watch + widget render a matching description (watch `Text`, widget
  `messageView` message) driven by the same store signal.

## Patterns to Follow

- **Reuse the store-as-source-of-truth model.** Data lives in `ReminderStore`;
  the view derives booleans (cf. `allSkipped`, `ContentView.swift:181-182`)
  rather than duplicating storage. Add the "why is it empty" signal to the
  store so iOS, watch, and widget share one answer.
- **Reuse `ContentUnavailableView(title, systemImage:, description:)`** for the
  iOS empty state (already the No Reminders affordance, `ContentView.swift:255`)
  and keep its `description:` as a `Text` (accessibility audit reads it).
- **Keep the branch-level affordances** exactly where they are: pull-to-refresh
  `.refreshable` (empty → `store.reload()`, `ContentView.swift:262-263`) and the
  mic `bottomBar` overlay (`ContentView.swift:265`). The mic is the "add a
  reminder" path (`ContentView.swift:379-399`) — don't duplicate it.
- **Keep per-branch icon names shared by convention** (`checklist` for empty,
  `checkmark.circle` for All Done), already aligned between iOS and widget.
- **For the companion surfaces**, extend their *existing* presentment rather
  than invent new layout: watch adds a `Text` description beside the
  `noRemindersState` headline (`WatchReminderView.swift:110-116`); widget passes
  the message into the existing `messageView` (`.empty`, `NextThingWidget.swift:95-96`).
- **Testing pattern:** `ContentView(loadsReminders: false)` + seeded store
  (`SingleThreadTests.swift:17-22`) with `String(describing: view.body)`
  assertions on the copy.

**Anti-patterns to NOT follow:**
- The watch empty state's iconless, descriptionless `Text` bis-only presentment
  (`WatchReminderView.swift:110-116`) is what we're improving, not propagating.
- The stale UI-test comment at `SingleThreadUITests.swift:22-23` (claims
  `--ui-testing` shows "Requesting access…", but `ContentView.swift:43-45` maps
  `loadsReminders: false` to the empty branch) should be corrected, not trusted.
- The current single-copy "You don't have any reminders yet" (`ContentView.swift:255`)
  is the misleading copy this task replaces.

## Design Decisions

1. **Why-empty signal lives in the store**: add a `ReminderStore` property
   (e.g. `public private(set) var hasHiddenReminders: Bool`) computed during
   reload by comparing the broader incomplete-reminder set against the
   windowed `shown` set. — Because the iOS, watch, and widget all render the
   same empty/gone case (Q4=both), and only the store sees the underlying
   library. Stays a Bool so surfaces keep control of their own copy.
2. **Broaden the reload query to detect hidden reminders**: `reload()`
   currently fetches only the date-windowed predicate (`ReminderStore.swift:161-166`).
   Fetch the full incomplete set (windowed predicate `nil`/`nil`), derive
   `shown` with the existing in-window filter, and mark `hasHiddenReminders`
   when some fetched-but-not-shown. (When `showsUndatedReminders` is already
   true, the broad set is already in hand — only the narrow mode needs the
   wider query.) (Q2=one-extra-lookup.)
3. **Two sub-state copies at the view layer**: inside the empty branch
   (`store.reminders.isEmpty`), branch on `store.hasHiddenReminders`:
   truly-empty copy vs. "due later" copy; pick icon accordingly (keep
   `checklist`, or `calendar` for the hidden case) (Q1=both).
4. **Actions stay copy-driven**: no new buttons. The pull-to-refresh and the
   mic `bottomBar` remain the sole affordances (Q3=both-branch A). Copy names
   them ("Tap the microphone to add a reminder", "Pull to refresh").
5. **Roll the same signal+copy out to watch and widget** for consistency:
   add a description to `watch noRemindersState` text, and pass a real message
   to the widget's `.empty` via `messageView` (Q4=both-surfaces).
6. **Test the new copy**: add Swift Testing assertions on both copy variants;
   tighten up the mutually ambiguous (fix `SingleThreadUITests.swift:22-23`)
   so tests reflect the actual empty branch (Q5=add tests, fix mismatch).

## What We're NOT Doing

- **No new visible action/affordance** on the iOS empty state (no "Add
  Reminder" / "See upcoming" button); dictation + pull-to-refresh already cover
  the two next actions, and Q3 forbids adding controls.
- **No changes to the schema-relevant All Done branch** — skips, exclusions,
  and the all-hidden state behavior stay as-is (only copy consistency across
  height surfaces, if needed).
- **No change to skip/exclusion persistence** (`SkippedReminderStore`,
  `ExcludedProjectStore`, `UserDefaults`/AppGroup) — that plumbing is untouched.
- **No new layout primitives**: iOS reuses `ContentUnavailableView`; watch
  reuses its VStack; widget reuses `messageView`.
- **No change to the auth-gated states** (`authGatedContent`, `ContentView.swift:221-228`).
- **No behavior change to the normal windowing** for what's displayed — visible
  reminders are unchanged; we only add detection of out-of-window reminders.
- **No separate persistence of the new signal** — it's derived from the fetch.

## Open Risks

- **Broader reload fetch cost.** Fetching all incomplete reminders (vs. the
  window) adds an EventKit round trip when `showsUndatedReminders` is false.
  Reminder lists are typically small, but for very large libraries this is a
  per-reload regression. Mitigate by reusing an already-broad fetch when the
  mode already queries all, and measuring at implementation time.
- **Detectability on watch product line.** The watch reads EventKit read-only;
  confirm a broad incomplete-reminder fetch is available/cheap there too so the
  widget/watch copy stays accurate.
- **Copy length vs. accessibility.** Longer description text must still satisfy
  the hit-region / element-description / dynamic-type audits and SwiftLint
  accessibility rules — keep every sub-state's copy (especially widget's) short.
- **"All All-Done" vs "hidden" interplay.** Since excluded projects are filtered
  in `visibleReminders` (`ReminderStore.swift:92-96`), all-excluded lands on the
  All Done branch, not the empty branch. Confirm the two sub-cases don't bleed
  into each other once `hasHiddenReminders` is added.
- **Stale test divergence.** The `--ui-testing` behavior/comment mismatch is
  pre-existing; adding copy assertions while it's unresolved could produce
  flaky or misleading failures. Resolve the claim first.