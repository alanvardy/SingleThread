# Task

Add lightweight momentum feedback to Single Thread's single-card interface —
a subtle completion streak and/or a "you have cleared five today" moment —
to give positive reinforcement without cluttering the single-card UI. The
ticket bodies itself leaves the mechanism open ("like a subtle streak or a
you have cleared five today moment"), so the product decision and the
persisted-state + UI work behind it must be designed before implementation.

## Why LARGE

DESIGN_SIGN-OFF (ticket explicitly offers two alternative product designs —
streak vs. daily-count badge — with a clutter trade-off needing a human
decision); CROSS_CUTTING (new persisted state/counting in the ReminderStore
data model plus a new UI feedback surface on the card); UNKNOWNS (streak
semantics: calendar-day vs. session counting, where it surfaces, watch-sync
behavior, dismissal/clutter rules); SCHEMA/CONVENTION_RISK (new persisted
values flowing through the shared AppGroup-defaults persistence convention
shared with the watch).