# Task

Create a marketing README for the SingleThread GitHub repo and set the repo
description, so that a visitor landing on the GitHub page is drawn to download
the app and is redirected to the App Store page.

**What to do:**

1. **Author a marketing `README.md` at the repo root** (it does not exist
   yet). Use the existing marketing page at `../vardy` — `alanvardy.dev/SingleThread`
   — as the design/copy inspiration. The README should be consumer-facing
   marketing copy, not developer docs. It should:
   - Sell what SingleThread does: **shows one Apple Reminder at a time for
     calm, focused momentum** (this is the current repo description).
   - Include a prominent **"Download on the App Store" badge/link** that
     redirects visitors to the app's App Store page. Use Apple's official
     badge assets and the correct app-store link (see the
     `app-store-badges` skill).
   - Be a greeting for a non-technical visitor, so link/redirect them to the
     App Store rather than to source code.
   - Consider light/dark badge variants and any official marketing-toolbox
     guidance from the `app-store-badges` skill.
2. **Set the GitHub repo description** for `alanvardy/SingleThread` (currently
   the marketing headline above). If the ticket implies a new/shorter
   description, update it via `gh repo edit` — otherwise keep the existing
   one; confirm the intended description text.

**Sources / inspiration:**
- Marketing page: `../vardy` single-thread page at `alanvardy.dev/SingleThread`
- App Store badge assets: `~/.pi/agent/skills/app-store-badges/SKILL.md`
- Doc/doc-formatting conventions for the repo: `AGENTS.md`

## Why SMALL

Single module (repo-root docs), one new file + one repo setting, no code,
schema, or shared-code change; approach is fully known from the existing
marketing page; no design/architecture decision; no unit tests needed (content
change only). Criteria A–F hold.

## Key files

- `README.md` (new — repo root)
- GitHub repo `alanvardy/SingleThread` description (via `gh repo edit`)
- Inspiration: `alanvardy.dev/SingleThread` (`../vardy` SingleThread page)
- Skill: `~/.pi/agent/skills/app-store-badges/SKILL.md`
