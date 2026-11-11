#if os(iOS)
    import SingleThreadCore
    import SwiftUI

    // MARK: - ToolbarAction

    enum ToolbarAction: Hashable, CaseIterable {
        case complete
        case dictate
        case skip
    }

    // MARK: - ToolbarActionSet

    /// The iOS toolbar's action gating, extracted from `bottomBar`'s former
    /// `#if os(iOS)` branch so every entitlement state is unit-testable. It hides
    /// items rather than disabling them (do not add an `isEnabled` path).
    struct ToolbarActionSet: Equatable {
        let actions: [ToolbarAction]
        let showsUpgradePrompt: Bool

        static func make(
            hasResolvedEntitlement: Bool,
            canMutate: Bool,
            showsActionButtons: Bool) -> Self {
            guard hasResolvedEntitlement else {
                return Self(actions: [], showsUpgradePrompt: false)
            }
            guard canMutate else {
                return Self(actions: [], showsUpgradePrompt: true)
            }
            return Self(
                actions: showsActionButtons ? ToolbarAction.allCases : [.dictate],
                showsUpgradePrompt: false)
        }
    }

    // MARK: - Main Toolbar

    extension ContentView {
        /// Single attach point for every iOS toolbar item. Later phases add the
        /// top-leading/top-trailing items here rather than attaching more toolbars.
        @ToolbarContentBuilder var mainToolbar: some ToolbarContent {
            if viewModel.dictation.canDictate, showMicrophoneButton {
                ToolbarItemGroup(placement: .bottomBar) {
                    let actions = toolbarActionSet.actions
                    if actions.contains(.complete) {
                        completeToolbarItem
                    }
                    if actions.contains(.dictate) {
                        dictateToolbarItem
                    }
                    if actions.contains(.skip) {
                        skipButton
                    }
                }
            }
        }

        var toolbarActionSet: ToolbarActionSet {
            ToolbarActionSet.make(
                hasResolvedEntitlement: viewModel.store.hasResolvedEntitlement,
                canMutate: viewModel.store.canMutate,
                showsActionButtons: viewModel.showsActionButtons)
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

        var dictateToolbarItem: some View {
            Button {
                Task { await viewModel.dictation.startDictation() }
            } label: {
                Label(
                    LocalizedStringResource("Dictate reminder", table: "Localizable", bundle: .main),
                    systemImage: "mic.fill")
            }
            .accessibilityLabel("Dictate reminder")
            .accessibilityIdentifier("dictateButton")
            .accessibilityAddTraits(.isButton)
        }
    }
#endif
