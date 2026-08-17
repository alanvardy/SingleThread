import Foundation

/// Accumulates dictated speech across utterance boundaries.
///
/// The on-device speech recognizer finalizes each utterance on a pause and
/// starts a new utterance, discarding earlier text from subsequent results.
/// This type retains each finalized utterance and appends the live
/// (in-progress) text so nothing is lost across pauses.
///
/// Usage:
/// ```swift
/// var accumulator = TranscriptionAccumulator()
/// let combined = accumulator.append(.init(text: "Buy milk", isCommitted: true))
/// // combined == "Buy milk"
/// let combined2 = accumulator.append(.init(text: "and eggs", isCommitted: false))
/// // combined2 == "Buy milk and eggs"
/// ```
public struct TranscriptionAccumulator: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// A chunk of recognized text — either a committed (finalized) utterance
    /// or a live (in-progress) partial.
    public struct Chunk: Equatable, Sendable {
        // MARK: Lifecycle

        public init(text: String, isCommitted: Bool) {
            self.text = text
            self.isCommitted = isCommitted
        }

        // MARK: Public

        public let text: String
        /// `true` when the recognizer has committed this utterance (segment
        /// confidence > 0); `false` for in-progress live results that may
        /// still change.
        public let isCommitted: Bool
    }

    /// Feeds the next recognition result and returns the combined transcript.
    ///
    /// When `chunk.isCommitted`:
    /// - Appends the text to the finalized list (deduping consecutive
    ///   identical values).
    /// - Clears the live text.
    ///
    /// When `!chunk.isCommitted`:
    /// - Replaces the current live text.
    @discardableResult
    public mutating func append(_ chunk: Chunk) -> String {
        let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if chunk.isCommitted {
            if !trimmed.isEmpty, finalized.last != trimmed {
                finalized.append(trimmed)
            }
            live = ""
        } else {
            live = trimmed
        }
        return combined
    }

    /// The full transcript: all finalized utterances followed by the current
    /// live text, joined with spaces.
    public var combined: String {
        var parts = finalized
        if !live.isEmpty { parts.append(live) }
        return parts.joined(separator: " ")
    }

    /// Returns `true` when nothing has been accumulated.
    public var isEmpty: Bool {
        finalized.isEmpty && live.isEmpty
    }

    // MARK: Private

    private var finalized: [String] = []
    private var live: String = ""
}