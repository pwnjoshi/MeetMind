import Foundation
import NaturalLanguage

/// The language a caption phrase is shown in.
public enum CaptionSpeechLanguage: String, Sendable, CaseIterable, Hashable {
    case english
    case hindi
}

/// Chooses, per phrase, whether the English or the Hindi recognizer heard the speaker correctly.
///
/// Both recognizers hear the same audio. A Hindi recognizer turns English speech into
/// Devanagari spellings ("मीटिंग"), and an English recognizer turns Hindi speech into
/// English-looking nonsense, so neither output can be trusted alone. The arbiter scores both:
/// - English score: the recognizer's confidence, and how English the text looks (`NLLanguageRecognizer`).
/// - Hindi score: the recognizer's confidence, the share of real Hindi words (Devanagari words
///   that are not English loanwords), and Hindi grammar words (है, का, में ...).
/// A Hindi result made only of Devanagari-spelled English words scores near zero.
///
/// A small hysteresis keeps the language from flipping on every phrase: switching away from the
/// current language needs a clear margin, or a long phrase with a smaller one.
///
/// Pure value type, no I/O, safe to unit test.
public struct LiveCaptionLanguageArbiter: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// Score gap that always allows a switch.
        public var switchMargin: Double = 0.30
        /// Smaller gap that allows a switch when the phrase is long.
        public var longPhraseMargin: Double = 0.12
        public var longPhraseWords: Int = 6
        /// English text this certain, with this confidence, gets a bonus.
        public var strongEnglishProbability: Double = 0.9
        public var strongEnglishConfidence: Double = 0.75
        /// Used when a recognizer reports no confidence (partial results often report 0).
        public var unknownConfidence: Double = 0.5
        /// Texts shorter than this many words pull the English probability toward 0.5.
        public var reliableWordCount: Int = 4

        public init() {}
    }

    public struct Evidence: Sendable, Equatable {
        public var englishScore: Double
        public var hindiScore: Double
        public var englishWordCount: Int
        public var hindiWordCount: Int
        public var englishProbability: Double
        public var englishConfidence: Double?
        public var hindiConfidence: Double?
        /// Share of Hindi-candidate words that are Hindi grammar words.
        public var hindiFunctionWordRatio: Double
        /// Share of Hindi-candidate words that are Devanagari-spelled English.
        public var transliteratedRatio: Double
        /// Share of Hindi-candidate words that are real Hindi (Devanagari, not a loanword).
        public var realHindiRatio: Double

        /// Positive favors English, negative favors Hindi.
        public var margin: Double { englishScore - hindiScore }
    }

    public struct Decision: Sendable, Equatable {
        public var language: CaptionSpeechLanguage
        public var evidence: Evidence
        /// True when the language differs from the previous decision.
        public var switched: Bool
    }

    public var configuration: Configuration
    /// Language of the last decision. Nil before the first one.
    public private(set) var current: CaptionSpeechLanguage?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        current = nil
    }

    /// Decides the language of a finished phrase and remembers it for hysteresis.
    public mutating func decide(english: [CaptionWord], hindi: [CaptionWord]) -> Decision {
        let evidence = Self.evidence(english: english, hindi: hindi, configuration: configuration)
        let language = Self.resolve(evidence: evidence, current: current, configuration: configuration)
        let switched = current != nil && current != language
        if !(evidence.englishWordCount == 0 && evidence.hindiWordCount == 0) {
            current = language
        }
        return Decision(language: language, evidence: evidence, switched: switched)
    }

    /// The language a partial would be shown in. Applies hysteresis but does not remember it.
    public func preview(english: [CaptionWord], hindi: [CaptionWord]) -> CaptionSpeechLanguage {
        let evidence = Self.evidence(english: english, hindi: hindi, configuration: configuration)
        return Self.resolve(evidence: evidence, current: current, configuration: configuration)
    }

    // MARK: Decision rule

    /// Picks the language from the evidence, keeping `current` unless the other side wins clearly.
    public static func resolve(evidence: Evidence, current: CaptionSpeechLanguage?,
                               configuration: Configuration = Configuration()) -> CaptionSpeechLanguage {
        let hasEnglish = evidence.englishWordCount > 0
        let hasHindi = evidence.hindiWordCount > 0
        if !hasEnglish && !hasHindi { return current ?? .english }
        if !hasEnglish { return .hindi }
        if !hasHindi { return .english }
        return resolve(margin: evidence.margin,
                       phraseWords: max(evidence.englishWordCount, evidence.hindiWordCount),
                       current: current,
                       configuration: configuration)
    }

    /// Hysteresis alone. `margin` is the English score minus the Hindi score.
    public static func resolve(margin: Double, phraseWords: Int, current: CaptionSpeechLanguage?,
                               configuration: Configuration = Configuration()) -> CaptionSpeechLanguage {
        let natural: CaptionSpeechLanguage = margin >= 0 ? .english : .hindi
        guard let current else { return natural }
        if natural == current { return current }
        let gap = abs(margin)
        if gap >= configuration.switchMargin { return natural }
        if phraseWords >= configuration.longPhraseWords, gap >= configuration.longPhraseMargin { return natural }
        return current
    }

    // MARK: Scoring

    public static func evidence(english: [CaptionWord], hindi: [CaptionWord],
                                configuration: Configuration = Configuration()) -> Evidence {
        let englishTokens = tokens(in: english)
        let hindiTokens = tokens(in: hindi)
        let englishConfidence = averageConfidence(english)
        let hindiConfidence = averageConfidence(hindi)
        let probability = englishProbability(of: englishTokens, configuration: configuration)

        // Classify the Hindi candidate's words.
        var functionHits = 0
        var loanHits = 0
        var realHits = 0
        let latinEnglish = englishTokens.filter { LiveCaptionLexicon.containsLatinLetter($0) }
        for token in hindiTokens {
            guard LiveCaptionLexicon.containsDevanagari(token) else { continue }
            if LiveCaptionLexicon.hindiFunctionWords.contains(token) {
                functionHits += 1
                realHits += 1
            } else if LiveCaptionLexicon.isTransliteratedEnglish(token, englishTokens: latinEnglish) {
                loanHits += 1
            } else {
                realHits += 1
            }
        }
        let hindiCount = Double(max(1, hindiTokens.count))
        let functionRatio = Double(functionHits) / hindiCount
        let loanRatio = Double(loanHits) / hindiCount
        let realRatio = Double(realHits) / hindiCount

        var englishScore = 0.0
        if !englishTokens.isEmpty {
            let confidence = englishConfidence ?? configuration.unknownConfidence
            englishScore = 0.6 * confidence + 0.4 * probability
            if let known = englishConfidence,
               probability >= configuration.strongEnglishProbability,
               known >= configuration.strongEnglishConfidence,
               englishTokens.count >= 3 {
                englishScore += 0.15
            }
        }

        var hindiScore = 0.0
        if !hindiTokens.isEmpty {
            let confidence = hindiConfidence ?? configuration.unknownConfidence
            hindiScore = 0.6 * confidence + 0.4 * realRatio
            hindiScore += 0.25 * min(1.0, functionRatio * 4.0)
            // English speech spelled in Devanagari: no Hindi grammar, mostly loanwords.
            if functionHits == 0, loanRatio >= 0.6, !englishTokens.isEmpty {
                hindiScore = min(hindiScore, 0.2)
            }
        }

        return Evidence(englishScore: min(1, englishScore),
                        hindiScore: min(1, hindiScore),
                        englishWordCount: englishTokens.count,
                        hindiWordCount: hindiTokens.count,
                        englishProbability: probability,
                        englishConfidence: englishConfidence,
                        hindiConfidence: hindiConfidence,
                        hindiFunctionWordRatio: functionRatio,
                        transliteratedRatio: loanRatio,
                        realHindiRatio: realRatio)
    }

    // MARK: Helpers

    /// Lower-cased words without surrounding punctuation. Tokens without letters are dropped.
    static func tokens(in words: [CaptionWord]) -> [String] {
        var result: [String] = []
        let trimSet = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        for word in words {
            for piece in word.text.split(whereSeparator: { $0.isWhitespace }) {
                let token = String(piece).trimmingCharacters(in: trimSet).lowercased()
                if LiveCaptionLexicon.containsDevanagari(token) || LiveCaptionLexicon.containsLatinLetter(token) {
                    result.append(token)
                }
            }
        }
        return result
    }

    /// Mean of the confidences the recognizer reported. A confidence of 0 means "not reported".
    static func averageConfidence(_ words: [CaptionWord]) -> Double? {
        var total = 0.0
        var count = 0
        for word in words where word.confidence > 0 {
            total += Double(min(1, word.confidence))
            count += 1
        }
        return count == 0 ? nil : total / Double(count)
    }

    /// Probability (0...1) that the Latin text is English. Short texts are pulled toward 0.5.
    static func englishProbability(of tokens: [String], configuration: Configuration) -> Double {
        let latin = tokens.filter { LiveCaptionLexicon.containsLatinLetter($0) }
        guard !latin.isEmpty else { return 0 }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(latin.joined(separator: " "))
        let raw = recognizer.languageHypotheses(withMaximum: 5)[.english] ?? 0
        let reliability = min(1.0, Double(latin.count) / Double(max(1, configuration.reliableWordCount)))
        // Tokens that are not Latin make the text less English by their share.
        let latinShare = Double(latin.count) / Double(max(1, tokens.count))
        return (0.5 + (raw - 0.5) * reliability) * latinShare
    }
}
