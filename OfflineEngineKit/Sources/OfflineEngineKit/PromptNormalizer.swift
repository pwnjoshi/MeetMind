import Foundation

/// The 1.7B model reads Roman Hinglish far better than Devanagari, and Roman text needs about a third of
/// the tokens. Turns written in Devanagari are therefore shown to the model in Roman letters
/// (`HindiRomanizer`). Quotes the model returns are mapped back to the original sentences, so every piece of
/// evidence stays an exact substring of the stored transcript. Stored transcripts are never rewritten.
enum PromptNormalizer {
    private static let terminators: Set<Character> = Set<Character>(["\u{0964}", "\u{0965}", ".", "?", "!"])

    /// Splits text into sentence pieces whose concatenation is exactly the input. A piece ends after a
    /// terminator and the white space that follows it.
    static func pieces(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        // 0: ordinary text, 1: just after a terminator, 2: in the white space after a terminator.
        var state = 0
        for character in text {
            if state == 2, !character.isWhitespace {
                result.append(current)
                current = ""
                state = 0
            }
            current.append(character)
            if terminators.contains(character) {
                state = 1
            } else if character.isWhitespace {
                if state == 1 { state = 2 }
            } else if state == 1 {
                state = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Roman Hinglish form of a Devanagari text. Text without Devanagari is returned unchanged.
    static func romanText(_ text: String) -> String {
        guard HindiText.containsDevanagari(text) else { return text }
        return pieces(of: text).map { HindiRomanizer.romanize($0) }.joined()
    }

    /// The turns as the model should read them: same ids, times and speakers; Devanagari text in Roman letters.
    static func romanized(_ turns: [AnalysisTurn]) -> [AnalysisTurn] {
        turns.map { turn in
            guard HindiText.containsDevanagari(turn.text) else { return turn }
            return AnalysisTurn(id: turn.id, text: romanText(turn.text), start: turn.start, end: turn.end,
                                speaker: turn.speaker)
        }
    }

    private struct Entry {
        let original: String
        let pieces: [String]
        let roman: [String]
        let full: String
    }

    /// Maps quotes written against the Roman text back to the original turn text. A quote that is already an
    /// exact substring of the original is kept. Otherwise the whole original sentence(s) it overlaps are used.
    /// A quote that cannot be located is left unchanged and `sanitized(against:)` drops the item.
    static func restoringQuotes(in result: LocalAnalysisResult, original turns: [AnalysisTurn]) -> LocalAnalysisResult {
        var table: [String: Entry] = [:]
        for turn in turns where HindiText.containsDevanagari(turn.text) {
            let parts = pieces(of: turn.text)
            let roman = parts.map { HindiRomanizer.romanize($0) }
            table[turn.id] = Entry(original: turn.text, pieces: parts, roman: roman, full: roman.joined())
        }
        guard !table.isEmpty else { return result }

        func restore(_ item: SourceEvidence) -> SourceEvidence {
            guard let entry = table[item.turnID], !item.quote.isEmpty, !entry.original.contains(item.quote),
                  let range = entry.full.range(of: item.quote) else { return item }
            let located = NSRange(range, in: entry.full)
            let low = located.location
            let high = located.location + located.length
            var offset = 0
            var first: Int?
            var last: Int?
            for (index, piece) in entry.roman.enumerated() {
                let end = offset + piece.utf16.count
                if offset < high, end > low {
                    if first == nil { first = index }
                    last = index
                }
                offset = end
            }
            guard let a = first, let b = last else { return item }
            let quote = entry.pieces[a...b].joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return quote.isEmpty ? item : SourceEvidence(turnID: item.turnID, quote: quote)
        }
        func points(_ values: [SupportedPoint]) -> [SupportedPoint] {
            values.map { SupportedPoint(text: $0.text, evidence: $0.evidence.map(restore)) }
        }
        let tasks = result.tasks.map { task in
            SuggestedTask(title: task.title, category: task.category, owner: task.owner,
                          deadlineText: task.deadlineText, priority: task.priority,
                          evidence: task.evidence.map(restore))
        }
        return LocalAnalysisResult(discussion: points(result.discussion), decisions: points(result.decisions),
                                   tasks: tasks, openIssues: points(result.openIssues))
    }
}

/// A cheap check, run before the language model, for chunks that cannot contain anything worth extracting:
/// no request, promise, decision, deferral, deadline or open question, and too little speech for a
/// discussion point. Such chunks (a greeting, "thanks, bye") skip the model call. The deterministic rules
/// still run over every chunk in the reducer, so nothing the rules can find is lost.
enum ChunkCueDetector {
    /// Let short factual updates reach the model even when they have no action or decision cue.
    static let minimumDiscussionWords = 12

    private static let cueWords: Set<String> = Set<String>([
        // English requests, promises, decisions, deferrals
        "will", "shall", "can", "could", "would", "should", "please", "need", "needs", "must", "going", "gonna",
        "send", "share", "prepare", "create", "update", "review", "approve", "approved", "confirm", "confirmed",
        "schedule", "book", "call", "email", "draft", "finalize", "finalized", "finalised", "decide", "decided",
        "decision", "agree", "agreed", "let", "deadline", "by", "tomorrow", "tonight", "today", "eod", "pending",
        "defer", "deferred", "postpone", "postponed", "cancel", "cancelled", "canceled", "assign", "assigned",
        "owner", "responsible", "action", "follow", "undecided", "tbd", "approval", "handle", "fix", "check",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "week", "month",
        // Hinglish
        "karna", "karo", "kar", "karenge", "karunga", "karungi", "karega", "karegi", "karte", "dena", "do", "dunga",
        "dungi", "denge", "dega", "degi", "bhej", "bhejna", "bhejo", "bhejunga", "bhejega", "bana", "banana",
        "banao", "dekh", "dekhna", "chahiye", "tay", "final", "faisla", "nahi", "agli", "agle", "kal", "parso",
        "tak", "sakte", "sakti", "sakta", "lena", "lunga", "hoga", "rahega", "zaroor", "jayega", "dijiye", "kijiye",
        "pata", "shayad", "agar", "kya"
    ])

    static func needsModel(_ turns: [AnalysisTurn]) -> Bool {
        var words = 0
        for turn in turns {
            let text = PromptNormalizer.romanText(turn.text)
            if text.contains("?") { return true }
            for piece in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                words += 1
                if cueWords.contains(String(piece)) { return true }
                // A digit next to a month or a time is a date; any number is a cue to look closer.
                if piece.first?.isNumber == true { return true }
            }
        }
        return words >= minimumDiscussionWords
    }
}
