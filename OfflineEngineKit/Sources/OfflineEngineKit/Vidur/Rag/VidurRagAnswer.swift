import Foundation

// Reading what the model wrote: the answer text as it streams, the blocks it cited, the sources a
// reader can open, and a check that the wording stays inside the facts it was given.

public struct VidurRagRequest: Sendable {
    public let input: VidurRagPromptInput
    public let maxTokens: Int

    public init(input: VidurRagPromptInput, maxTokens: Int = VidurRagPromptBuilder.maximumOutputTokens) {
        self.input = input
        self.maxTokens = maxTokens
    }
}

public struct VidurRagModelResult: Sendable, Equatable {
    /// The reply, cleaned of stray block markers.
    public let answer: String
    /// False when the model said the blocks do not cover the question.
    public let found: Bool
    /// Block numbers the model cited that really exist in `prompt.blocks`. One based.
    public let citedBlocks: [Int]
    /// The prompt the model actually read, after it was fitted to the token budget.
    public let prompt: VidurRagPrompt
    public let usedWarmSession: Bool
    /// True when generation hit the length limit and the reply was cut at its last full sentence.
    public let truncated: Bool

    public init(answer: String, found: Bool, citedBlocks: [Int], prompt: VidurRagPrompt, usedWarmSession: Bool,
                truncated: Bool) {
        self.answer = answer
        self.found = found
        self.citedBlocks = citedBlocks
        self.prompt = prompt
        self.usedWarmSession = usedWarmSession
        self.truncated = truncated
    }
}

/// A place in a meeting that backs an answer. Maps one to one onto a source chip.
public struct VidurRagSource: Sendable, Equatable {
    public let blockNumber: Int
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date
    /// "Decision", "Action" and so on for minutes items. Nil for a transcript quote.
    public let label: String?
    public let timestamp: TimeInterval?
    public let quote: String
    public let speaker: String?
}

public struct VidurRagSources: Sendable, Equatable {
    public let items: [VidurRagSource]
    /// True when the model cited nothing usable and the sources are simply the best retrieved blocks.
    public let inferred: Bool
}

public enum VidurRagAnswerParser {
    /// The text of the "answer" string so far, with escapes decoded. Works on a half written JSON object, so
    /// the app can show words as the model produces them.
    public static func partialAnswer(from partial: String) -> String {
        guard let marker = partial.range(of: "\"answer\":") else { return "" }
        var rest = Substring(partial[marker.upperBound...])
        rest = rest.drop { $0 == " " || $0 == "\n" || $0 == "\t" }
        guard rest.first == "\"" else { return "" }
        rest = rest.dropFirst()
        var output = ""
        var iterator = rest.makeIterator()
        while let character = iterator.next() {
            if character == "\"" { break }
            if character != "\\" {
                output.append(character)
                continue
            }
            guard let escaped = iterator.next() else { break }
            switch escaped {
            case "n": output.append("\n")
            case "t": output.append(" ")
            case "r", "b", "f": break
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    guard let digit = iterator.next() else { return trimmed(output) }
                    hex.append(digit)
                }
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    output.unicodeScalars.append(scalar)
                }
            default: output.append(escaped)
            }
        }
        return trimmed(output)
    }

    /// Removes a half decoded character at the end (from a token that splits a UTF-8 sequence).
    private static func trimmed(_ text: String) -> String {
        var value = text
        while value.last == "\u{FFFD}" { value.removeLast() }
        return value
    }

    /// Takes out block markers such as "[2]" or "[1, 3]" and markdown stars. With `streaming` it also cuts a
    /// marker that is still being written, so no "[" flashes on screen.
    public static func clean(_ text: String, streaming: Bool = false) -> String {
        var value = VidurRx.replacing(#"\s*\[\s*\d{1,2}(?:\s*[,;]\s*\d{1,2})*\s*\]"#, in: text, with: "")
        if streaming { value = VidurRx.replacing(#"\s*\[[\d\s,;]*$"#, in: value, with: "") }
        value = value.replacingOccurrences(of: "**", with: "")
        value = VidurRx.replacing(#"[ \t]{2,}"#, in: value, with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "c3" gives 3. Labels outside 1...blockCount, duplicates and malformed labels are dropped.
    public static func citedBlocks(_ labels: [String], blockCount: Int) -> [Int] {
        VidurGroundedParser.citedIndices(labels, snippetCount: blockCount).map { $0 + 1 }
    }
}

public enum VidurRagCitations {
    /// The sources behind an answer. Cited blocks come first. Facts blocks count only when nothing else is
    /// cited. When the model cited nothing, the best retrieved blocks stand in and `inferred` is true.
    public static func sources(for result: VidurRagModelResult, maximum: Int = 3) -> VidurRagSources {
        let blocks = result.prompt.blocks
        func source(_ block: VidurRagBlock) -> VidurRagSource {
            VidurRagSource(blockNumber: block.number, meetingID: block.chunk.meetingID,
                           meetingTitle: block.chunk.meetingTitle, meetingDate: block.chunk.meetingDate,
                           label: block.chunk.kind.sourceLabel, timestamp: block.timestamp, quote: block.quote,
                           speaker: block.speaker)
        }
        func unique(_ chosen: [VidurRagBlock]) -> [VidurRagSource] {
            var seen = Set<String>()
            var items: [VidurRagSource] = []
            for block in chosen where items.count < maximum {
                let item = source(block)
                let key = "\(item.meetingID.uuidString)|\(item.label ?? "")|\(item.timestamp ?? -1)|\(item.quote)"
                if seen.insert(key).inserted { items.append(item) }
            }
            return items
        }
        let cited = result.citedBlocks.compactMap { number in blocks.first { $0.number == number } }
        let detailed = cited.filter { $0.chunk.kind != .facts }
        if !detailed.isEmpty { return VidurRagSources(items: unique(detailed), inferred: false) }
        if !cited.isEmpty { return VidurRagSources(items: unique(cited), inferred: false) }
        guard result.found else { return VidurRagSources(items: [], inferred: false) }
        let fallback = blocks.filter { $0.chunk.kind != .facts }.prefix(2)
        let items = unique(Array(fallback))
        return VidurRagSources(items: items, inferred: !items.isEmpty)
    }
}

/// Checks that a reply stays inside the facts it was given. Numbers above ten and capitalised names in the
/// reply must also appear in the evidence (blocks, verified answer, question), in any script.
public enum VidurRagGuard {
    private static let allowedWords: Set<String> = [
        "vidur", "manent", "iphone", "english", "hindi", "hinglish", "devanagari", "okay"
    ]

    public static func isFaithful(answer: String, evidence: [String]) -> Bool {
        unsupportedTerms(in: answer, evidence: evidence).isEmpty
    }

    /// The numbers and names of `answer` that the evidence does not contain.
    public static func unsupportedTerms(in answer: String, evidence: [String]) -> [String] {
        let evidenceText = evidence.joined(separator: " ").lowercased()
        var missing: [String] = []

        var knownNumbers = Set<Int>()
        var knownRaw = Set<String>()
        for token in evidenceText.split(whereSeparator: { !($0.isASCII && $0.isNumber) }) {
            knownRaw.insert(String(token))
            if let value = Int(token) { knownNumbers.insert(value) }
        }
        for token in answer.split(whereSeparator: { !($0.isASCII && $0.isNumber) }) {
            if let value = Int(token) {
                if value <= 10 || knownNumbers.contains(value) { continue }
            } else if knownRaw.contains(String(token)) {
                continue
            }
            missing.append(String(token))
        }

        var knownWords = Set<String>()
        var knownSkeletons = Set<String>()
        for word in evidenceText.split(whereSeparator: { !$0.isLetter }) {
            let value = String(word)
            if knownWords.insert(value).inserted {
                let skeleton = VidurScript.skeleton(value)
                if skeleton.count >= 2 { knownSkeletons.insert(skeleton) }
            }
        }
        for (word, startsSentence) in words(of: answer) where !startsSentence {
            guard let first = word.first, first.isUppercase else { continue }
            var base = word.lowercased()
            for apostrophe in ["'", "\u{2019}"] {
                if let cut = base.range(of: apostrophe) { base = String(base[base.startIndex..<cut.lowerBound]) }
            }
            guard base.count >= 3, !allowedWords.contains(base), !isCalendarWord(base),
                  !knownWords.contains(base) else { continue }
            let skeleton = VidurScript.skeleton(base)
            if skeleton.count >= 2, knownSkeletons.contains(skeleton) { continue }
            missing.append(word)
        }
        return missing
    }

    /// "friday", "fri", "november" and "nov".
    private static func isCalendarWord(_ base: String) -> Bool {
        if HindiText.weekdays.contains(base) || HindiText.months.contains(base) { return true }
        guard base.count == 3 || base.count == 4 else { return false }
        return HindiText.weekdays.contains { $0.hasPrefix(base) } || HindiText.months.contains { $0.hasPrefix(base) }
    }

    /// Words of a text, each with whether it opens a sentence or line.
    static func words(of text: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []
        var word = ""
        var opensSentence = true
        for character in text {
            if character.isLetter || character == "'" || character == "\u{2019}" {
                word.append(character)
                continue
            }
            if !word.isEmpty {
                result.append((word, opensSentence))
                word = ""
                opensSentence = false
            }
            if ".!?:\u{0964}\n".contains(character) { opensSentence = true }
        }
        if !word.isEmpty { result.append((word, opensSentence)) }
        return result
    }
}
