import Foundation

/// One recognized word with a time range relative to the start of the recording.
public struct CaptionWord: Sendable, Equatable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Float

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = max(start, end)
        self.confidence = confidence
    }

    /// Lower-cased text without punctuation or symbols, used only to compare words.
    var comparisonKey: String {
        let kept = text.lowercased().unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
                && !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: kept)
        return String(view)
    }

    public func shifted(by offset: TimeInterval) -> CaptionWord {
        CaptionWord(text: text, start: start + offset, end: end + offset, confidence: confidence)
    }

    /// Splits a phrase into words and spreads `start...end` across them by character count.
    /// Used for recognizers that report a whole phrase with a single time range.
    public static func words(from phrase: String, start: TimeInterval, end: TimeInterval, confidence: Float = 1.0) -> [CaptionWord] {
        let pieces = phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !pieces.isEmpty else { return [] }
        let totalWeight = Double(pieces.reduce(0) { $0 + max(1, $1.count) })
        let span = max(0, end - start)
        var cursor = start
        var result: [CaptionWord] = []
        result.reserveCapacity(pieces.count)
        for (index, piece) in pieces.enumerated() {
            let share = span * Double(max(1, piece.count)) / totalWeight
            let wordEnd = index == pieces.count - 1 ? start + span : cursor + share
            result.append(CaptionWord(text: piece, start: cursor, end: wordEnd, confidence: confidence))
            cursor = wordEnd
        }
        return result
    }
}

/// Merges partial and final recognizer output into a clean caption stream.
///
/// The stitcher works on time-aligned words, so recognition requests that overlap
/// (for example the seamless restarts of `SFSpeechRecognizer`, which is limited to
/// about a minute per request) never print the same words twice:
/// 1. words that start before the already committed audio are dropped, and
/// 2. words that straddle the boundary and repeat the committed tail are trimmed.
public struct LiveCaptionStitcher: Sendable {
    /// Rules for turning a long running partial result into stable phrases.
    public struct AutoCommitPolicy: Sendable, Equatable {
        /// A silence of at least this long between two words ends a phrase.
        public var pauseGap: TimeInterval
        /// A phrase needs at least this many words before a pause can close it.
        public var minimumWordsBeforePause: Int
        /// A partial longer than this is split even without a pause.
        public var maximumPartialWords: Int
        /// Words kept as the open partial after a forced split.
        public var wordsKeptOpen: Int

        public init(pauseGap: TimeInterval = 0.9, minimumWordsBeforePause: Int = 3,
                    maximumPartialWords: Int = 30, wordsKeptOpen: Int = 8) {
            self.pauseGap = pauseGap
            self.minimumWordsBeforePause = minimumWordsBeforePause
            self.maximumPartialWords = maximumPartialWords
            self.wordsKeptOpen = wordsKeptOpen
        }

        public static let captions = AutoCommitPolicy()
    }

    public var autoCommit: AutoCommitPolicy?
    public let timeTolerance: TimeInterval
    public let maximumOverlapWords: Int

    /// End time of the last committed word. Nothing earlier is emitted again.
    public private(set) var committedEnd: TimeInterval = 0
    public private(set) var committedWordCount: Int = 0
    /// The last few committed words, kept to detect repeats after a restart.
    public private(set) var recentWords: [CaptionWord] = []
    public private(set) var openWords: [CaptionWord] = []

    private static let recentLimit = 16

    public init(autoCommit: AutoCommitPolicy? = nil, timeTolerance: TimeInterval = 0.15, maximumOverlapWords: Int = 8) {
        self.autoCommit = autoCommit
        self.timeTolerance = timeTolerance
        self.maximumOverlapWords = maximumOverlapWords
    }

    /// Applies a partial hypothesis. Returns final chunks for any phrases that became
    /// stable (see `AutoCommitPolicy`) followed by one non-final chunk for the open tail.
    public mutating func updateOpen(_ words: [CaptionWord]) -> [LiveTranscriptChunk] {
        var fresh = trimmed(words)
        var output: [LiveTranscriptChunk] = []
        if let policy = autoCommit {
            while let split = splitIndex(in: fresh, policy: policy) {
                let head = Array(fresh[..<split])
                fresh = Array(fresh[split...])
                record(head)
                output.append(Self.chunk(head, isFinal: true))
            }
        }
        openWords = fresh
        if !fresh.isEmpty {
            output.append(Self.chunk(fresh, isFinal: false))
        }
        return output
    }

    /// Commits a final result. Returns nil when everything in it was already committed.
    public mutating func commit(_ words: [CaptionWord]) -> LiveTranscriptChunk? {
        let fresh = trimmed(words)
        openWords = []
        guard !fresh.isEmpty else { return nil }
        record(fresh)
        return Self.chunk(fresh, isFinal: true)
    }

    // MARK: - Internals

    private mutating func record(_ words: [CaptionWord]) {
        guard let last = words.last else { return }
        committedWordCount += words.count
        committedEnd = max(committedEnd, last.end)
        recentWords.append(contentsOf: words)
        if recentWords.count > Self.recentLimit {
            recentWords.removeFirst(recentWords.count - Self.recentLimit)
        }
    }

    /// Removes the part of `words` that was already committed.
    func trimmed(_ words: [CaptionWord]) -> [CaptionWord] {
        var list = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // 1. Anything that starts clearly before the committed audio is a repeat.
        var dropCount = 0
        while dropCount < list.count, list[dropCount].start < committedEnd - timeTolerance {
            dropCount += 1
        }
        if dropCount > 0 { list.removeFirst(dropCount) }

        // 2. Words that straddle the boundary and repeat the committed tail.
        guard !list.isEmpty, !recentWords.isEmpty else { return list }
        let upper = min(maximumOverlapWords, list.count, recentWords.count)
        guard upper >= 1 else { return list }
        for length in stride(from: upper, through: 1, by: -1) {
            let tailKeys = recentWords.suffix(length).map(\.comparisonKey)
            let headKeys = list.prefix(length).map(\.comparisonKey)
            guard tailKeys == headKeys, !headKeys.contains("") else { continue }
            let lastStart = list[length - 1].start
            let overlapsCommittedAudio: Bool
            switch length {
            case 1: overlapsCommittedAudio = lastStart < committedEnd
            case 2: overlapsCommittedAudio = lastStart < committedEnd + 0.5
            default: overlapsCommittedAudio = list[0].start < committedEnd + 1.5
            }
            if overlapsCommittedAudio {
                list.removeFirst(length)
                break
            }
        }
        return list
    }

    /// Number of leading words to commit now, or nil if the partial should stay open.
    private func splitIndex(in words: [CaptionWord], policy: AutoCommitPolicy) -> Int? {
        guard words.count >= 2 else { return nil }
        // Last pause that still leaves at least one word open.
        var pauseSplit: Int?
        for index in 1..<words.count where words[index].start - words[index - 1].end >= policy.pauseGap {
            if index >= policy.minimumWordsBeforePause { pauseSplit = index }
        }
        if let pauseSplit { return pauseSplit }

        guard words.count > policy.maximumPartialWords else { return nil }
        let limit = max(1, words.count - policy.wordsKeptOpen)
        // Prefer ending on sentence punctuation, otherwise cut at the limit.
        if let sentenceEnd = words[..<limit].lastIndex(where: { Self.endsSentence($0.text) }) {
            return sentenceEnd + 1
        }
        return limit
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last == "." || last == "?" || last == "!" || last == "\u{0964}"
    }

    static func chunk(_ words: [CaptionWord], isFinal: Bool) -> LiveTranscriptChunk {
        let text = words.map(\.text).joined(separator: " ")
        let segments = words.map {
            LiveTranscriptSegment(text: $0.text, startTime: $0.start, duration: max(0, $0.end - $0.start), confidence: $0.confidence)
        }
        return LiveTranscriptChunk(text: text, isFinal: isFinal, segments: segments)
    }
}
