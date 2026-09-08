# Task: iPadOS reminder container opacity (VAR-722)

The container (card) that the current reminder is shown in appears
transparent on iPhone but opaque on iPad, in both light and dark modes.
The behavior should be consistent between the two devices. The macOS build
is out of scope (it is not functioning properly and its appearance cannot be
relied on). Investigate what causes the iPadOS divergence in how the
reminder card's container/background is rendered and resolve it so the
container renders the same way on iPad as it does on iPhone.