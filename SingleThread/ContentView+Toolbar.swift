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

    // MARK: - DictateToolbarState

    /// The dictate toolbar item's visual state, extracted so the in-place morph
    /// (mic → red mic → green checkmark / red cross) is unit-testable.
    /// Feedback wins over recording: `DictationViewModel` sets it after the
    /// transcriber stops, then clears both flags.
    enum DictateToolbarState: Equatable {
        case idle
        case recording
        case feedback(CreationFeedback)

        // MARK: Internal

        nonisolated static func make(
            isDictating: Bool,
            creationFeedback: CreationFeedback?) -> Self {
            if let creationFeedback {
                return .feedback(creationFeedback)
            }
            return isDictating ? .recording : .idle
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
                completeToolbarLabel
            }
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)
        }

        /// Green while the completion confirmation is active; otherwise the
        /// default toolbar tint (kept untouched rather than re-specified).
        @ViewBuilder private var completeToolbarLabel: some View {
            if viewModel.completionFlash.isActive {
                // A bare `Image`, not a `Label`: a toolbar `Button` supplies the
                // tint, so a nested `Label`'s `.foregroundStyle(.green)` is
                // dropped and the icon never turns green. Mirrors
                // ``dictateToolbarLabel``'s coloured states.
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
            }
        }

        var dictateToolbarItem: some View {
            Button {
                Task { await viewModel.dictation.startDictation() }
            } label: {
                dictateToolbarLabel
            }
            .accessibilityLabel(dictateAccessibilityLabel)
            .accessibilityIdentifier("dictateButton")
            .accessibilityAddTraits(.isButton)
        }

        /// Mirrors ``DictateToolbarState``: the single mic button becomes a red
        /// mic while recording, then a green checkmark (red cross on failure) —
        /// same size as the idle mic, only a colour/symbol change, so nothing
        /// extra is drawn in the bottom bar on iOS.
        @ViewBuilder private var dictateToolbarLabel: some View {
            switch dictateToolbarState {
            case .idle:
                Label(
                    LocalizedStringResource("Dictate reminder", table: "Localizable", bundle: .main),
                    systemImage: "mic.fill")
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            case let .feedback(feedback):
                Image(systemName: feedback.systemImage)
                    .foregroundStyle(feedback.backgroundColor)
            }
        }

        private var dictateAccessibilityLabel: String {
            switch dictateToolbarState {
            case .idle: "Dictate reminder"
            case .recording: "Recording"
            case let .feedback(feedback): feedback.accessibilityLabel
            }
        }

        private var dictateToolbarState: DictateToolbarState {
            DictateToolbarState.make(
                isDictating: viewModel.dictation.isDictating,
                creationFeedback: viewModel.dictation.creationFeedback)
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
