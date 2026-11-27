import Foundation

/// Repairs a typed question before it is parsed: curly apostrophes, chat shorthand ("r", "u"), words glued
/// together by a stray letter ("thevpresentation"), and one-letter typos. Corrections only use words the
/// meetings and the question parser already know (index vocabulary and attendee names), so nothing new is
/// invented. A word that is already known is never touched.
public enum VidurQuestionNormalizer {
    private static let shorthand: [String: String] = [
        "r": "are", "u": "you", "ur": "your", "wat": "what", "wht": "what", "abt": "about", "pls": "please",
        "plz": "please", "wen": "when", "whos": "who's"
    ]

    /// Short words that may stand alone when a glued word is split.
    private static let smallWords: Set<String> = [
        "a", "i", "is", "of", "to", "in", "on", "an", "at", "by", "we", "my", "me", "do", "it", "he", "us", "or",
        "if", "so", "as", "and", "the", "for", "are", "who", "how", "did", "has", "was", "can", "our", "all"
    ]

    /// Word counts of everything the meetings say, plus attendee first names (boosted).
    struct Lexicon {
        var counts: [String: Int] = [:]
        var names: Set<String> = []
        var fixed: Set<String> = []

        func isKnown(_ word: String) -> Bool {
            counts[word] != nil || fixed.contains(word) || names.contains(word)
        }
    }

    static func lexicon(records: [VidurMeetingRecord], names extra: [String]) -> Lexicon {
        var lexicon = Lexicon()
        func add(_ text: String) {
            for word in VidurScript.words(text) where word.count >= 3 && isPlainLatin(word) {
                lexicon.counts[word, default: 0] += 1
            }
        }
        func addName(_ raw: String?) {
            guard let raw, !VidurPersonIndex.isGenericLabel(raw), let first = VidurPersonIndex.firstToken(raw),
                  first.count >= 3, isPlainLatin(first) else { return }
            lexicon.names.insert(first)
        }
        for record in records {
            add(record.title)
            add(record.summary)
            record.discussion.forEach(add)
            record.agenda.forEach(add)
            for line in record.decisions { add(line.text) }
            for line in record.openIssues { add(line.text) }
            for task in record.tasks {
                add(task.title)
                addName(task.owner)
            }
            for turn in record.turns {
                add(turn.text)
                addName(turn.speaker)
            }
            record.attendees.forEach { addName($0) }
            record.absent.forEach { addName($0) }
        }
        for name in extra { addName(name) }
        var fixed = VidurQuestionParser.vocabulary
        fixed.formUnion(VidurTokenizer.stopWords)
        fixed.formUnion(smallWords)
        lexicon.fixed = fixed.filter { isPlainLatin($0) }
        return lexicon
    }

    static func isPlainLatin(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }
    }

    /// The question with typos and glued words repaired. Returns it unchanged when nothing needs fixing.
    public static func normalize(_ question: String, records: [VidurMeetingRecord], names: [String] = []) -> String {
        let built = lexicon(records: records, names: names)
        return normalize(question, lexicon: built)
    }

    static func normalize(_ question: String, lexicon: Lexicon) -> String {
        let text = question
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        var pieces: [String] = []
        for piece in text.split(separator: " ", omittingEmptySubsequences: true) {
            pieces.append(fix(String(piece), lexicon: lexicon))
        }
        return pieces.joined(separator: " ")
    }

    /// One whitespace separated piece: punctuation stays where it is, the word in the middle is repaired.
    private static func fix(_ piece: String, lexicon: Lexicon) -> String {
        let scalars = Array(piece.unicodeScalars)
        var from = 0
        var upTo = scalars.count
        while from < upTo, !isWordScalar(scalars[from]) { from += 1 }
        while upTo > from, !isWordScalar(scalars[upTo - 1]) { upTo -= 1 }
        guard from < upTo else { return piece }
        var head = ""
        var tail = ""
        var core = ""
        for scalar in scalars[0..<from] { head.unicodeScalars.append(scalar) }
        for scalar in scalars[from..<upTo] { core.unicodeScalars.append(scalar) }
        for scalar in scalars[upTo..<scalars.count] { tail.unicodeScalars.append(scalar) }
        guard let replaced = repair(core, lexicon: lexicon) else { return piece }
        return head + replaced + tail
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || (scalar.value >= 0x30 && scalar.value <= 0x39) || scalar == "'"
    }

    /// The repaired word, or nil to keep it as typed.
    private static func repair(_ core: String, lexicon: Lexicon) -> String? {
        var lowered = core.lowercased()
        var possessive = ""
        if lowered.hasSuffix("'s") {
            possessive = "'s"
            lowered = String(lowered.dropLast(2))
        }
        guard isPlainLatin(lowered) else { return nil }
        if let expanded = shorthand[lowered], core.count <= 3 { return expanded + possessive }
        if lexicon.isKnown(lowered) { return nil }
        if lowered.count >= 6, let parts = split(lowered, lexicon: lexicon) {
            return parts + possessive
        }
        let isName = lowered.count >= 4
        guard lowered.count >= 6 || isName else { return nil }
        guard let candidate = closest(to: lowered, lexicon: lexicon, namesOnly: lowered.count < 6) else { return nil }
        var cased = candidate
        if core.first?.isUppercase == true {
            cased = String(candidate.prefix(1)).uppercased() + String(candidate.dropFirst())
        }
        return cased + possessive
    }

    private static func isStandalone(_ word: String, lexicon: Lexicon) -> Bool {
        guard lexicon.isKnown(word) else { return false }
        if word.count >= 4 { return true }
        return smallWords.contains(word) || VidurTokenizer.stopWords.contains(word) || VidurQuestionParser.vocabulary.contains(word)
    }

    /// "thevpresentation" gives "the presentation": a known word, at most one stray letter, a known word.
    private static func split(_ word: String, lexicon: Lexicon) -> String? {
        let letters = Array(word)
        guard letters.count >= 6 else { return nil }
        var best: String?
        var bestCovered = 0
        for cut in 1..<(letters.count - 2) {
            let left = String(letters[0..<cut])
            guard isStandalone(left, lexicon: lexicon) else { continue }
            for gap in 0...1 {
                let rightStart = cut + gap
                guard letters.count - rightStart >= 3 else { continue }
                let right = String(letters[rightStart...])
                guard isStandalone(right, lexicon: lexicon) else { continue }
                let covered = left.count + right.count
                if covered > bestCovered {
                    bestCovered = covered
                    best = left + " " + right
                }
            }
        }
        return best
    }

    /// The known word one edit away. Nil when there is none or when two equally common words compete.
    private static func closest(to word: String, lexicon: Lexicon, namesOnly: Bool) -> String? {
        var best: String?
        var bestScore = 0
        var tied = false
        func consider(_ candidate: String, score: Int) {
            guard withinOneEdit(word, candidate) else { return }
            if score > bestScore {
                best = candidate
                bestScore = score
                tied = false
            } else if score == bestScore, best != candidate {
                tied = true
            }
        }
        for name in lexicon.names { consider(name, score: 1_000) }
        if !namesOnly {
            for (candidate, count) in lexicon.counts where candidate.count >= 5 { consider(candidate, score: count) }
            for candidate in lexicon.fixed where candidate.count >= 5 { consider(candidate, score: 2) }
        }
        return tied ? nil : best
    }

    /// True when `a` becomes `b` by one insertion, deletion, substitution or swap of neighbouring letters.
    static func withinOneEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs)
        let b = Array(rhs)
        if a == b { return false }
        let difference = a.count - b.count
        guard abs(difference) <= 1 else { return false }
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        if a.count == b.count {
            if Array(a[(start + 1)...]) == Array(b[(start + 1)...]) { return true }
            if start + 1 < a.count, a[start] == b[start + 1], a[start + 1] == b[start],
               Array(a[(start + 2)...]) == Array(b[(start + 2)...]) { return true }
            return false
        }
        let longer = a.count > b.count ? a : b
        let shorter = a.count > b.count ? b : a
        return Array(longer[(start + 1)...]) == Array(shorter[start...])
    }
}
