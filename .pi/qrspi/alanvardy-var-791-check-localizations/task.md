# Task — Check localizations

Audit every localization in the SingleThread app (iOS app, Core SPM package,
watch app, and widget extension) across all six locales (en, zh-Hans, es, ja,
de, fr) and fix any entry where the "translation" is actually still English
(or effectively identical to the English source). This guarantees that users
in non-English locales genuinely see translated UI.

The deliverable is a verification that all non-English localizations are
real translations, corrected where they are not — ideally with a regression
guard so English copies can't silently return.