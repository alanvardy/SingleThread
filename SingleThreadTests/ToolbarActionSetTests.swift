#if os(iOS)
    @testable import SingleThread
    import Testing

    @MainActor
    struct ToolbarActionSetTests {
        @Test
        func hiddenWithoutResolvedEntitlement() {
            let set = ToolbarActionSet.make(
                hasResolvedEntitlement: false, canMutate: true, showsActionButtons: true)
            #expect(set.actions.isEmpty)
            #expect(!set.showsUpgradePrompt)
        }

        @Test
        func freeTierShowsUpgradePromptOnly() {
            let set = ToolbarActionSet.make(
                hasResolvedEntitlement: true, canMutate: false, showsActionButtons: true)
            #expect(set.actions.isEmpty)
            #expect(set.showsUpgradePrompt)
        }

        @Test
        func entitledShowsAllThreeActions() {
            let set = ToolbarActionSet.make(
                hasResolvedEntitlement: true, canMutate: true, showsActionButtons: true)
            #expect(set.actions == [.complete, .dictate, .skip])
            #expect(!set.showsUpgradePrompt)
        }

        @Test
        func entitledWithoutActionButtonsShowsMicOnly() {
            let set = ToolbarActionSet.make(
                hasResolvedEntitlement: true, canMutate: true, showsActionButtons: false)
            #expect(set.actions == [.dictate])
            #expect(!set.showsUpgradePrompt)
        }

        @Test
        func freeTierWithoutActionButtonsStillPrompts() {
            let set = ToolbarActionSet.make(
                hasResolvedEntitlement: true, canMutate: false, showsActionButtons: false)
            #expect(set.actions.isEmpty)
            #expect(set.showsUpgradePrompt)
        }
    }
#endif
