#if os(iOS)
import SingleThreadCore
import SwiftUI

// MARK: - Main Toolbar

extension ContentView {
    /// Single attach point for every iOS toolbar item. Later phases add the
    /// top-leading/top-trailing items here rather than attaching more toolbars.
    @ToolbarContentBuilder
    var mainToolbar: some ToolbarContent {
        if viewModel.dictation.canDictate,
           showMicrophoneButton,
           viewModel.store.hasResolvedEntitlement,
           viewModel.store.canMutate,
           viewModel.showsActionButtons {
            ToolbarItemGroup(placement: .bottomBar) {
                completeToolbarItem
            }
        }
    }

    var completeToolbarItem: some View {
        Button {
            Task { await viewModel.completeCurrentReminder() }
        } label: {
            Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
        }
        .accessibilityLabel(SharedStrings.completeReminderAccessibility)
        .accessibilityIdentifier("completeButton")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
