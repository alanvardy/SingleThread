# Task

Replace the settings menu — currently a gear-shaped `Menu` overlaid in the
top-trailing corner of the main reminders view — with a separate settings
screen that the user navigates into, with a back button in the top-left to
return. The new screen keeps the existing preferences (appearance, text size,
landscape orientation, and the microphone button) and their persisted
`@AppStorage` state, but presents them as their own view instead of a popup
menu.