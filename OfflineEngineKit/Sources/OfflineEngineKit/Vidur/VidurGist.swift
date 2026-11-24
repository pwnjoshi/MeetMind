import Foundation

/// Turns a noisy transcript line into a short third-person clause, or finds who was asked to do something.
/// It only drops filler words, repeated words and a garbled start, and it only changes pronouns ("we" to
/// "they"). It never adds a word that was not said, so the result stays grounded in the transcript.
enum VidurGist {
    private static let fillers: Set<String> = ["uh", "um", "uhh", "umm", "er", "erm", "ah", "hmm", "hm", "mm", "mmm"]
    private static let connectors: Set<String> = [
        "and", "so", "but", "then", "okay", "ok", "yeah", "yes", "right", "well", "also", "like", "actually",
        "basically"
    ]
    private static let dangling: Set<String> = [
        "and", "but", "so", "to", "the", "a", "an", "of", "with", "or", "also", "on", "in", "for", "by", "at", "that",
        "is", "are", "will", "please", "if", "because", "then"
    ]
    private static let subjects: Set<String> = ["we", "i", "let's", "lets", "he", "she", "they"]
    private static let unresolved: Set<String> = ["you", "your", "yours", "you're", "you'll", "you've", "yourself", "mine"]
    private static let pronouns: [String: String] = [
        "we": "they", "we'll": "they'll", "we're": "they're", "we've": "they've", "we'd": "they'd",
        "our": "their", "ours": "theirs", "us": "them", "let's": "they should", "lets": "they should",
        "i": "they", "i'm": "they're", "i'll": "they'll", "i've": "they've", "i'd": "they'd", "my": "their",
        "me": "them", "myself": "themselves"
    ]
    private static let requestVerbs: Set<String> = [
        "send", "prepare", "share", "review", "update", "finalize", "finalise", "submit", "make", "create", "book",
        "call", "email", "check", "write", "draft", "schedule", "arrange", "organize", "organise", "fix", "deliver",
        "present", "complete", "finish", "handle", "take", "do", "set", "post", "upload", "circulate", "follow",
        "confirm", "bring", "get", "give", "collect", "design", "build", "print", "publish"
    ]
    static let maximumWords = 24

    // MARK: Helpers

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value == 0x27 { return false }
        return !(scalar.properties.isAlphabetic || (value >= 0x30 && value <= 0x39))
    }

    /// Lower-cased token without punctuation at either end. Apostrophes inside a word stay.
    static func bare(_ token: String) -> String {
        var scalars = Array(token.lowercased().unicodeScalars)
        while let first = scalars.first, isPunctuation(first) || first.value == 0x27 { scalars.removeFirst() }
        while let last = scalars.last, isPunctuation(last) || last.value == 0x27 { scalars.removeLast() }
        var output = ""
        for scalar in scalars { output.unicodeScalars.append(scalar) }
        return output
    }

    /// Words of a transcript line without fillers and stutters.
    private static func cleanWords(_ text: String) -> [String] {
        var words: [String] = []
        let pieces = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        for piece in pieces {
            let token = String(piece)
            let key = bare(token)
            if key.isEmpty || fillers.contains(key) { continue }
            if let last = words.last, bare(last) == key, key.count > 1 { continue }
            words.append(token)
        }
        return words
    }

    private static func firstHit(in words: [String], topicKeys: Set<String>) -> Int? {
        guard !topicKeys.isEmpty else { return nil }
        for (offset, token) in words.enumerated() {
            let keys = VidurScript.keys(forWord: bare(token))
            if keys.contains(where: { topicKeys.contains($0) }) { return offset }
        }
        return nil
    }

    private static func capitalized(_ word: String) -> String {
        String(word.prefix(1)).uppercased() + String(word.dropFirst())
    }

    // MARK: Clause

    /// "kalta and we will launch this website on 20 number and also make sure to go with the pune vendor and"
    /// gives "they will launch this website on 20 number and also make sure to go with the pune vendor".
    /// Nil when the line is not plain English or cannot be reported safely.
    static func clause(from text: String, topicKeys: Set<String>, names: Set<String>) -> String? {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let words = cleanWords(text)
        guard words.count >= 4 else { return nil }

        var start = 0
        if let hit = firstHit(in: words, topicKeys: topicKeys), hit > 0 {
            var cursor = hit - 1
            let lowest = max(0, hit - 5)
            while cursor >= lowest {
                if subjects.contains(bare(words[cursor])) {
                    start = cursor
                    break
                }
                cursor -= 1
            }
        }
        while start < words.count - 4, connectors.contains(bare(words[start])) { start += 1 }

        var picked: [String] = []
        var index = start
        while index < words.count, picked.count < maximumWords {
            let token = words[index]
            picked.append(token)
            index += 1
            if let last = token.last, ".?!".contains(last), picked.count >= 3 { break }
        }
        if let last = picked.last, last.hasSuffix("?") { return nil }
        while picked.count > 3, let last = picked.last, dangling.contains(bare(last)) { picked.removeLast() }
        guard picked.count >= 4 else { return nil }

        var shifted: [String] = []
        var previousWasSubject = false
        for token in picked {
            let key = bare(token)
            if unresolved.contains(key) { return nil }
            var word = token
            var isSubject = false
            if let replacement = pronouns[key] {
                word = replaceCore(of: token, with: replacement)
                isSubject = key == "we" || key == "i"
            } else if previousWasSubject, key == "am" {
                word = replaceCore(of: token, with: "are")
            } else if previousWasSubject, key == "was" {
                word = replaceCore(of: token, with: "were")
            } else if names.contains(key) {
                word = replaceCore(of: token, with: capitalized(key))
            } else if HindiText.weekdays.contains(key) || HindiText.months.contains(key) {
                word = replaceCore(of: token, with: capitalized(key))
            }
            previousWasSubject = isSubject
            shifted.append(word)
        }
        if let first = shifted.first {
            let key = bare(first)
            if !names.contains(key), !HindiText.weekdays.contains(key), !HindiText.months.contains(key) {
                shifted[0] = String(first.prefix(1)).lowercased() + String(first.dropFirst())
            }
        }
        var joined = shifted.joined(separator: " ")
        while let last = joined.last, ",;:.!".contains(last) { joined.removeLast() }
        return joined
    }

    /// Replaces the letters of a token and keeps the punctuation around it.
    private static func replaceCore(of token: String, with replacement: String) -> String {
        let scalars = Array(token.unicodeScalars)
        var from = 0
        var upTo = scalars.count
        while from < upTo, isPunctuation(scalars[from]) || scalars[from].value == 0x27 { from += 1 }
        while upTo > from, isPunctuation(scalars[upTo - 1]) || scalars[upTo - 1].value == 0x27 { upTo -= 1 }
        var head = ""
        var tail = ""
        for scalar in scalars[0..<from] { head.unicodeScalars.append(scalar) }
        for scalar in scalars[upTo..<scalars.count] { tail.unicodeScalars.append(scalar) }
        var core = replacement
        if let original = scalars[from..<upTo].first, original.properties.isUppercase, let first = replacement.first {
            core = String(first).uppercased() + String(replacement.dropFirst())
        }
        return head + core + tail
    }

    // MARK: Requests

    /// "send the neha you send the presentation please" said by Pawan gives (Neha, "send the presentation").
    static func request(in text: String, topicKeys: Set<String>, speaker: String?,
                        index: VidurPersonIndex) -> (person: VidurPerson, phrase: String)? {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let words = cleanWords(text)
        guard let hit = firstHit(in: words, topicKeys: topicKeys), hit > 0 else { return nil }

        var verb: Int?
        var cursor = hit - 1
        let lowest = max(0, hit - 5)
        while cursor >= lowest {
            if requestVerbs.contains(bare(words[cursor])) {
                verb = cursor
                break
            }
            cursor -= 1
        }
        guard let verbIndex = verb else { return nil }

        var person: VidurPerson?
        var personWord = ""
        for token in words {
            let key = bare(token)
            guard key.count >= 3, !VidurTokenizer.stopWords.contains(key),
                  !VidurQuestionParser.vocabulary.contains(key), !requestVerbs.contains(key),
                  let found = index.person(forWord: key) else { continue }
            if let speaker, index.matches(speaker, found) { continue }
            person = found
            personWord = key
            break
        }
        guard let addressee = person else { return nil }

        var phrase: [String] = []
        for position in verbIndex...hit {
            let key = bare(words[position])
            if key.isEmpty || key == personWord || key == "you" { continue }
            phrase.append(key)
        }
        guard phrase.count >= 2 else { return nil }
        return (addressee, phrase.joined(separator: " "))
    }
}

/// Cleans model replies: speaker labels become "someone", and an undecided matter is an "open issue", never a
/// "task", unless a saved action was among the sources.
public enum VidurAnswerPolish {
    public static func polish(_ text: String, allowTask: Bool) -> String {
        var value = text
        value = VidurRx.replacing(#"\bspeaker[ _-]?\d+\b"#, in: value, with: "someone")
        if !allowTask {
            let adjectives = "(?:pending|open|unresolved|outstanding)"
            value = VidurRx.replacing("\\b" + adjectives + "\\s+tasks\\b", in: value, with: "open issues")
            value = VidurRx.replacing("\\b(?:a|an)\\s+" + adjectives + "\\s+task\\b", in: value, with: "an open issue")
            value = VidurRx.replacing("\\b" + adjectives + "\\s+task\\b", in: value, with: "open issue")
            value = VidurRx.replacing("\\btasks\\b", in: value, with: "issues")
            value = VidurRx.replacing("\\btask\\b", in: value, with: "issue")
            value = VidurRx.replacing("\\ba\\s+(open\\s+)?issue\\b", in: value, with: "an $1issue")
        }
        value = VidurRx.replacing(#"(^|[.!?]\s+)someone\b"#, in: value, with: "$1Someone")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A speaker name that is fit for a source chip. Nil for "Speaker 1", "S1", notes and empty labels.
    public static func chipSpeaker(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || VidurPersonIndex.isGenericLabel(trimmed) || trimmed.lowercased() == "someone" { return nil }
        return trimmed
    }
}
