#if os(iOS)
    @testable import SingleThread
    import Testing

    @MainActor
    struct DictateToolbarStateTests {
        @Test
        func idleWhenNeitherRecordingNorFeedback() {
            #expect(
                DictateToolbarState.make(isDictating: false, creationFeedback: nil) == .idle)
        }

        @Test
        func recordingWhileDictating() {
            #expect(
                DictateToolbarState.make(isDictating: true, creationFeedback: nil) == .recording)
        }

        @Test
        func successFeedbackReplacesRecordingInPlace() {
            #expect(
                DictateToolbarState.make(isDictating: true, creationFeedback: .success)
                    == .feedback(.success))
        }

        @Test
        func failureFeedbackWinsOverRecording() {
            #expect(
                DictateToolbarState.make(isDictating: false, creationFeedback: .failure)
                    == .feedback(.failure))
        }
    }
#endif
