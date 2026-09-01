# Research Questions

## Context

This repo is a SwiftUI reminders app ("SingleThread") with four targets —
an iOS app (which also compiles for macOS), a watchOS app, a widget
extension, and a local SPM package (`SingleThreadCore`) for the model layer.
User-facing copy today is hardcoded English string literals scattered
through the sources; the Xcode project has no localization infrastructure
(string catalogs, `.lproj` variant groups, or `InfoPlist.strings`) and its
`knownRegions`/`developmentRegion` are set to `en`/`Base`. Explore how
user-facing text and locale-sensitive formatting are currently handled in
each of these areas, and what external surfaces carry copy that lives
outside the app source. Do NOT propose solutions or a plan — describe what
exists and how it works today, with `file:line` references.

## Questions

1. **String inventory across targets.** Where exactly do user-facing
   strings live in each of the four targets, and what kinds do they fall
   into (visible labels, navigation titles, accessibility labels, empty
   states, toasts/feedback, local-notification title/body, widget gallery
   copy, AppIntent titles)? Which strings are shared across two or more
   targets, and roughly how many distinct strings does each target hold?

2. **Localization plumbing in the Xcode project.** What build settings and
   project attributes relevant to localization already exist in
   `SingleThread.xcodeproj/project.pbxproj` (e.g. `knownRegions`,
   `developmentRegion`, string-catalog preferences, `SWIFT_EMIT_LOC_STRINGS`,
   `STRING_CATALOG_GENERATE_SYMBOLS`)? How are resources and any variant
   groups organized in the pbxproj, and does any localization file type
   (`.xcstrings`, `.strings`, `.stringsdict`, `.lproj`) exist anywhere in
   the repo today?

3. **Dynamic and locale-sensitive formatting.** Which user-facing strings
   involve interpolation, pluralization, dates, or formatted values — e.g.
   recurrence summaries ("Every N days"), percent/label interpolation,
   version strings, notification bodies containing counts, and priority
   display names? Where are these formatted today, and do any of them
   currently use locale-aware APIs?

4. **Info.plist user-facing values.** How are user-visible Info.plist
   values (usage-description strings like microphone/reminders/speech,
   `CFBundleDisplayName`, widget display name, `NSHumanReadableCopyright`)
   set for each target — via `INFOPLIST_KEY_*` build settings, generated
   Info.plists, or a physical Info.plist file — and is any of that copy
   currently localized?

5. **Tests' dependence on string literals.** Which unit and UI tests assert
   on exact user-facing strings or accessibility labels (e.g. row titles,
   buttons, empty-state text, a11y labels in UI-test flows or the
   accessibility audit)? How are these strings referenced — copied literal,
   helper constants, accessibility identifiers — and how many call sites
   would be affected if literals moved into a localization layer?

6. **External and system-owned copy.** Which user-facing strings come from
   outside the app source — StoreKit `Product` metadata (display name,
   description, price) rendered in purchase UI, AppIntent titles exposed to
   the system, widget configuration display name/description shown in the
   widget gallery — and where do those originate?

7. **App Store / storefront copy.** What is currently known about the
   app's App Store Connect listing (app name, subtitle, description,
   keywords, screenshots) and its primary language? Is there any tooling,
   metadata, or documentation in the repo referencing App Store Connect or
   storefront content, and what do App Store listing localization options
   consist of for a small developer without such tooling?