# Task

Fix the appearance preference so selecting "System" actually follows the
device's appearance. Currently, when a user starts on System (which correctly
samples dark mode), switches to Light, and then switches back to System, the app
stays in Light instead of returning to the device's appearance. All three
appearance modes (System, Light, Dark) should take effect consistently and the
System choice should re-apply whichever appearance the device is currently in.