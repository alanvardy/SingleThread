# Task — VAR-749 Localization

Add translations for all supported languages to the SingleThread app. All
user-facing copy across the iOS app, watchOS app, widget, and the
SingleThreadCore package is currently hardcoded English, and no localization
infrastructure (string catalogs, InfoPlist.strings, lproj directories) exists
in the project today. The work also covers researching what localization
options are available for the app's App Store listing (app store metadata,
product page).

This change spans all four targets and moves ~130+ distinct user-facing
strings out of hardcoded literals into a localized form, including
Info.plist usage descriptions, accessibility labels, AppIntent titles, and
local-notification copy — while keeping existing unit and UI tests passing.