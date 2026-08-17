import SingleThreadCore
import Testing

// MARK: - TranscriptionAccumulator

@MainActor
struct TranscriptionAccumulatorTests {
    // MARK: Empty

    @Test
    func emptyAccumulatorIsEmpty() {
        let accumulator = TranscriptionAccumulator()
        #expect(accumulator.isEmpty)
        #expect(accumulator.combined.isEmpty)
    }

    // MARK: Single chunk

    @Test
    func liveChunkReturnsItself() {
        var accumulator = TranscriptionAccumulator()
        let result = accumulator.append(.init(text: "Buy milk", isCommitted: false))
        #expect(result == "Buy milk")
        #expect(accumulator.combined == "Buy milk")
        #expect(!accumulator.isEmpty)
    }

    @Test
    func committedChunkReturnsItself() {
        var accumulator = TranscriptionAccumulator()
        let result = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        #expect(result == "Buy milk")
        #expect(accumulator.combined == "Buy milk")
    }

    // MARK: Committed + live

    @Test
    func committedThenLiveJoinsThem() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        let result = accumulator.append(.init(text: "and eggs", isCommitted: false))
        #expect(result == "Buy milk and eggs")
    }

    // MARK: Two committed chunks

    @Test
    func twoCommittedChunksJoin() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        let result = accumulator.append(.init(text: "and eggs", isCommitted: true))
        #expect(result == "Buy milk and eggs")
    }

    // MARK: Live refinement

    @Test
    func liveChunkReplacesPreviousLive() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "Buy", isCommitted: false))
        let result = accumulator.append(.init(text: "Buy milk", isCommitted: false))
        #expect(result == "Buy milk")
    }

    // MARK: Committed clears live

    @Test
    func committedChunkClearsLive() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "Buy milk", isCommitted: false))
        let result = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        #expect(result == "Buy milk")
        // Live should be cleared; no duplication.
    }

    // MARK: Dedup consecutive identical committed

    @Test
    func consecutiveIdenticalCommittedChunksDeduped() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        let result = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        #expect(result == "Buy milk")
    }

    // MARK: Empty committed chunk ignored

    @Test
    func emptyCommittedChunkDoesNotAppend() {
        var accumulator = TranscriptionAccumulator()
        _ = accumulator.append(.init(text: "   ", isCommitted: true))
        #expect(accumulator.isEmpty)
        #expect(accumulator.combined.isEmpty)
    }

    // MARK: Whitespace trimming

    @Test
    func chunksAreWhitespaceTrimmed() {
        var accumulator = TranscriptionAccumulator()
        let result = accumulator.append(.init(text: "  Hello  ", isCommitted: true))
        #expect(result == "Hello")
    }

    // MARK: Full dictation scenario

    @Test
    func fullDictationAcrossPauses() {
        var accumulator = TranscriptionAccumulator()
        // Utterance 1 — live then committed
        _ = accumulator.append(.init(text: "Buy", isCommitted: false))
        _ = accumulator.append(.init(text: "Buy milk", isCommitted: false))
        let first = accumulator.append(.init(text: "Buy milk", isCommitted: true))
        #expect(first == "Buy milk")

        // Utterance 2 — live only
        let second = accumulator.append(.init(text: "and eggs", isCommitted: false))
        #expect(second == "Buy milk and eggs")

        // Utterance 2 committed
        let third = accumulator.append(.init(text: "and eggs today", isCommitted: true))
        #expect(third == "Buy milk and eggs today")
    }
}
