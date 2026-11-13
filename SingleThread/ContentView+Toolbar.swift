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

    // MARK: - UndoToolbarSlot

    /// Which top bar hosts the undo item. On the Duo outer portrait the right
    /// (trailing) bar renders as a vertical stack, so undo joins it *after* the
    /// settings item to sit below the gear; every other pose keeps the
    /// pre-existing leading slot untouched.
    enum UndoToolbarSlot: Equatable {
        case leading
        case belowSettings

        // MARK: Internal

        var placement: ToolbarItemPlacement {
            switch self {
            case .leading: .topBarLeading
            case .belowSettings: .topBarTrailing
            }
        }

        nonisolated static func make(isDuoOuterPortrait: Bool) -> Self {
            isDuoOuterPortrait ? .belowSettings : .leading
        }
    }

    // MARK: - Main Toolbar

    extension ContentView {
        /// Single attach point for every iOS toolbar item. Later phases add the
        /// top-leading/top-trailing items here rather than attaching more toolbars.
        @ToolbarContentBuilder var mainToolbar: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                settingsToolbarItem
            }
            if viewModel.store.undoStore.hasUndoableReminder,
               showUndoButton,
               viewModel.store.canMutate {
                ToolbarItem(placement: undoToolbarSlot.placement) {
                    undoToolbarItem
                }
            }
            if viewModel.dictation.canDictate,
               showMicrophoneButton,
               !toolbarActionSet.actions.isEmpty {
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

        /// Undo joins the trailing bar only on the Duo outer portrait; the
        /// settings item is declared first there, so it stays above undo.
        var undoToolbarSlot: UndoToolbarSlot {
            UndoToolbarSlot.make(isDuoOuterPortrait: layoutContext.isDuoOuterPortrait)
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

        var settingsToolbarItem: some View {
            Button {
                presentSettings()
            } label: {
                Label(
                    LocalizedStringResource("Settings", table: "Localizable", bundle: .main),
                    systemImage: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
            .accessibilityAddTraits(.isButton)
        }

        var undoToolbarItem: some View {
            Button {
                Task { await viewModel.undoLastCompletion() }
            } label: {
                Label(
                    LocalizedStringResource("Undo completion", table: "Localizable", bundle: .main),
                    systemImage: "arrow.uturn.backward")
            }
            .accessibilityLabel("Undo completion")
            .accessibilityIdentifier("undoButton")
            .accessibilityAddTraits(.isButton)
        }
    }
#endif
