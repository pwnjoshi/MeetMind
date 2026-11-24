import Foundation

// Keeps what Vidur shows readable: no ISO timestamps, no internal words ("context blocks", "c1"), no doubled
// "Resolved:" prefix, no junk decisions, and no contradiction between "not approved" and "approve".

// MARK: - Natural dates

/// Rewrites ISO-8601 dates and timestamps ("2026-11-23T12:59:41Z") as natural dates.
/// A date alone becomes "23 Nov". A date with a time becomes "Mon 23 Nov at 12:59 PM" in the calendar's time zone.
public enum VidurNaturalDates {
    private static let pattern = #"\b(\d\d\d\d)-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:[.,]\d+)?)?(?:\s?(Z\b|[+-]\d\d:?\d\d))?)?(?!\d)"#

    public static func rewrite(_ text: String, calendar: Calendar = .current) -> String {
        guard text.contains("-"),
              let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let nsText = text as NSString
        let matches = expression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let natural = describe(match, in: nsText, calendar: calendar) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: natural)
        }
        return result
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: NSString) -> String? {
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : text.substring(with: range)
    }

    private static func zone(_ raw: String?) -> TimeZone? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.lowercased() == "z" { return TimeZone(secondsFromGMT: 0) }
        guard let sign = raw.first, sign == "+" || sign == "-" else { return nil }
        let digits = raw.dropFirst().filter { $0.isNumber }
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    private static func describe(_ match: NSTextCheckingResult, in text: NSString, calendar: Calendar) -> String? {
        guard let year = group(match, 1, in: text).flatMap({ Int($0) }),
              let month = group(match, 2, in: text).flatMap({ Int($0) }),
              let day = group(match, 3, in: text).flatMap({ Int($0) }),
              (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let hour = group(match, 4, in: text).flatMap { Int($0) }
        let minute = group(match, 5, in: text).flatMap { Int($0) } ?? 0
        let second = group(match, 6, in: text).flatMap { Int($0) } ?? 0
        if let hour, !(0...23).contains(hour) || !(0...59).contains(minute) || !(0...59).contains(second) { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        let dayOnly = hour == nil || (hour == 0 && minute == 0 && second == 0)
        if dayOnly {
            parts.hour = 12
            guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { return nil }
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = zone(group(match, 7, in: text)) ?? calendar.timeZone
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        guard let date = source.date(from: parts), source.component(.day, from: date) == day else { return nil }
        formatter.dateFormat = "EEE d MMM 'at' h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - "20 number"

/// Speech recognition writes "20 November" as "20 number". The spoken words are never changed in stored data.
/// When shown text says "<n> number" and the minutes of the same meeting say "<n> <month>", the minutes' wording is
/// used. Otherwise the text stays as it was spoken.
public enum VidurSpokenDates {
    private static let months = "(?:January|February|March|April|May|June|July|August|September|October|November|December|Sept|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"

    /// Minutes text of one meeting that may carry a written date.
    static func minutesTexts(of record: VidurMeetingRecord) -> [String] {
        var texts: [String] = [record.summary]
        texts += record.discussion
        texts += record.agenda
        texts += record.decisions.map(\.text)
        texts += record.openIssues.map(\.text)
        texts += record.tasks.map(\.title)
        return texts.filter { !$0.isEmpty }
    }

    static func prefer(_ text: String, record: VidurMeetingRecord) -> String {
        prefer(text, minutes: minutesTexts(of: record))
    }

    public static func prefer(_ text: String, minutes: [String]) -> String {
        guard !minutes.isEmpty, text.lowercased().contains("number"),
              let expression = VidurRx.regex(#"\b(\d\d?)\s+number\b"#) else { return text }
        let nsText = text as NSString
        let found = expression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !found.isEmpty else { return text }
        let joined = minutes.joined(separator: "\n")
        var result = text
        for match in found.reversed() {
            guard let value = Int(nsText.substring(with: match.range(at: 1))),
                  let captures = VidurRx.captures("\\b0?\(value)\\s+(\(months))\\b", in: joined), captures.count > 1 else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "\(value) \(captures[1])")
        }
        return result
    }
}

// MARK: - Decision wording

/// Cleans and screens the decisions that Vidur lists.
public enum VidurDecisionText {
    private static let prefixPattern = #"^\s*(?:(?:resolved|decided|decision|agreed)(?:\s+that)?\s*(?::|\s[\-\x{2013}\x{2014}]\s)|(?:resolved|decided)\s+that\b)\s*"#

    private static let functionWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with", "and", "or", "it", "its", "is", "are", "be",
        "this", "that", "her", "him", "them", "his", "their", "our", "my", "me", "we", "i", "you", "he", "she", "they",
        "us", "as", "so", "if", "up"
    ]

    /// "Resolved: Resolved: The app should include charts." gives "The app should include charts."
    public static func clean(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var rounds = 0
        while rounds < 4, let expression = VidurRx.regex(prefixPattern) {
            let ns = value as NSString
            guard let match = expression.firstMatch(in: value, options: [], range: NSRange(location: 0, length: ns.length)),
                  match.range.length > 0 else { break }
            let rest = ns.substring(from: match.range.location + match.range.length)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { break }
            value = rest
            rounds += 1
        }
        guard rounds > 0, let first = value.first else { return value }
        return String(first).uppercased() + String(value.dropFirst())
    }

    /// A listed decision needs at least three content words (a verb and something it acts on). "Let her come."
    /// has two and is left out of lists. The saved minutes are not changed.
    public static func isSubstantial(_ text: String) -> Bool {
        let content = VidurScript.words(text).filter { !functionWords.contains($0) }
        return content.count >= 3
    }
}

// MARK: - Internal words

/// Removes words that only make sense inside the prompt ("context blocks", "block 3", "c1", "the summary mentions").
enum VidurLeakFilter {
    private static let blockWords = #"\b(?:the\s+|these\s+|those\s+)?(?:context\s+|provided\s+|given\s+|retrieved\s+|numbered\s+)*(?:blocks?|snippets?)(?:\s+(?:c|no\.?\s*|number\s+)?\d\d?)?\b|\bc\d\d?\b|\[\d\d?\]"#

    private static let verbPairs: [(String, String)] = [
        ("does", "do"), ("says", "say"), ("shows", "show"), ("mentions", "mention"), ("states", "state"),
        ("contains", "contain"), ("covers", "cover"), ("includes", "include"), ("notes", "note"),
        ("indicates", "indicate"), ("describes", "describe"), ("is", "are"), ("has", "have")
    ]

    private static func hasBlockTerms(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("block") || lowered.contains("snippet") { return true }
        return VidurRx.matches(#"\bc\d\d?\b"#, lowered)
    }

    static func scrub(_ text: String) -> String {
        var value = text
        if hasBlockTerms(value) { value = dropBlockTalk(value) }
        value = rewrite(value)
        return value
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var pendingBreak = false
        for character in text {
            if pendingBreak, character == " " || character == "\n" {
                current.append(character)
                continue
            }
            if pendingBreak {
                result.append(current)
                current = ""
                pendingBreak = false
            }
            current.append(character)
            if ".!?\u{0964}".contains(character) { pendingBreak = true }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A sentence that has nothing left once the block words are taken out ("See c1 and c3.", "Block 2 is a decision.").
    static func isBlockTalk(_ sentence: String) -> Bool {
        guard hasBlockTerms(sentence) else { return false }
        let rest = VidurRx.replacing(blockWords, in: sentence, with: " ")
        return VidurTokenizer.tokens(rest).count < 2
    }

    private static func dropBlockTalk(_ text: String) -> String {
        let parts = sentences(text)
        let kept = parts.filter { !isBlockTalk($0) }
        guard !kept.isEmpty else { return text }
        return kept.joined()
    }

    private static func rewrite(_ text: String) -> String {
        var value = text
        let preposition = #"\b(in|from|within|across)\s+(?:the\s+|these\s+|those\s+|all\s+the\s+|all\s+)?(?:provided\s+|given\s+|retrieved\s+|numbered\s+)*(?:context\s+)?(?:blocks?|snippets?|excerpts?)\b(?!\s*(?:c|no\.?\s*|number\s+)?\d)"#
        value = VidurRx.replacing(preposition, in: value, with: "$1 your meetings")
        value = VidurRx.replacing(#"\b(in|from|within)\s+the\s+(?:provided|given)\s+context\b"#, in: value, with: "$1 your meetings")
        value = VidurRx.replacing(#"\b(according\s+to|based\s+on|per)\s+(?:the\s+)?(?:provided\s+|given\s+)*(?:context(?:\s+blocks?)?|blocks?|summary)\b"#,
                                  in: value, with: "$1 your meetings")
        value = VidurRx.replacing(#"\b(?:the\s+)?(?:provided\s+|given\s+|retrieved\s+)*context\s+blocks?\b(?!\s*(?:c|no\.?\s*|number\s+)?\d)"#,
                                  in: value, with: "your meetings")
        value = VidurRx.replacing(#"\bthe\s+blocks\b(?!\s*(?:c|no\.?\s*|number\s+)?\d)"#, in: value, with: "your meetings")
        let summaryVerbs = ["mentions", "states", "says", "notes", "indicates", "shows", "describes"]
        for verb in summaryVerbs {
            let plural = verbPairs.first { $0.0 == verb }?.1 ?? verb
            value = VidurRx.replacing("\\bthe\\s+(?:meeting\\s+)?summary\\s+" + verb + "\\b", in: value, with: "your meetings " + plural)
        }
        for (singular, plural) in verbPairs {
            value = VidurRx.replacing("\\byour meetings\\s+" + singular + "\\b", in: value, with: "your meetings " + plural)
        }
        value = VidurRx.replacing(#"\s*[\(\[]\s*c\d\d?(?:\s*[,;&]\s*c?\d\d?)*\s*[\)\]]"#, in: value, with: "")
        value = VidurRx.replacing(#"(?:\s+(?:in|from|per|see|via))?\s*\(?\b(?:context\s+)?blocks?\s+(?:c|no\.?\s*|number\s+)?\d\d?(?:\s*(?:,|and|&)\s*c?\d\d?)*\b\)?"#,
                                  in: value, with: "")
        value = VidurRx.replacing(#"(?-i:\bc\d\d?\b)"#, in: value, with: "")
        value = VidurRx.replacing(#"[ \t]{2,}"#, in: value, with: " ")
        value = VidurRx.replacing(#"\s+([.,;:!?])"#, in: value, with: "$1")
        value = VidurRx.replacing(#"(^|[.!?]\s+)your meetings\b"#, in: value, with: "$1Your meetings")
        return value
    }
}

// MARK: - Contradictions

/// A saved decision or open issue that replaces a model reply which contradicts itself.
public struct VidurContradictionFix: Sendable, Equatable {
    public let text: String
    public let chunk: VidurRagChunk
}

/// Finds replies that say "not approved / not decided" and "approve / approved" about the same subject, and rewrites
/// them from the saved decision or open issue for that subject.
public enum VidurContradictionGuard {
    private static let negation = #"(?:\b(?:not|never|wasn't|isn't|hasn't|haven't|weren't|aren't|didn't|without)\s+(?:yet\s+|been\s+|fully\s+|really\s+|formally\s+|officially\s+|actually\s+|be\s+|to\s+be\s+)*(?:approv(?:e|ed|al)|decid(?:e|ed)|resolved|finali[sz]ed|agreed|confirmed|settled|made|reached)\b|\bno\s+(?:final\s+|formal\s+|clear\s+)?(?:decision|approval|agreement|resolution|outcome)\b|\b(?:undecided|unresolved|unapproved)\b|\bstill\s+pending\b)"#
    private static let positive = #"\b(?:approv(?:e|es|ed|ing|al)|decid(?:e|es|ed|ing)|agree(?:d|s)?|finali[sz]e[ds]?|resolved)\b"#
    private static let ignored: Set<String> = [
        "meeting", "meetings", "discussion", "discussions", "issue", "issues", "team", "today", "going", "said", "mention",
        "mentioned", "decision", "decisions", "topic", "need", "needs", "work", "worked", "make", "made", "well", "still",
        "also", "talk", "talked", "discuss", "discussed"
    ]

    private static func clauses(_ text: String) -> [String] {
        let flat = text.replacingOccurrences(of: "\u{2019}", with: "'")
        let marked = VidurRx.replacing(#"[!?;:\n]|\.(?=\s|$)|,(?=\s)|\band\b|\bbut\b|\bwhile\b|\bwhereas\b"#, in: flat, with: "\u{1}")
        return marked.split(separator: "\u{1}").map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func subjectWords(_ clause: String) -> Set<String> {
        var words = Set<String>()
        for token in VidurTokenizer.tokens(clause) {
            guard token.count >= 4, token.first?.isLetter == true, !ignored.contains(token) else { continue }
            if ["approv", "decid", "resolv", "agre", "final", "confir", "settl", "reach"].contains(where: { token.hasPrefix($0) }) { continue }
            words.insert(token)
        }
        return words
    }

    /// The shared subject word when the reply both denies and affirms a decision about it. Nil otherwise.
    public static func conflictingSubject(in answer: String) -> String? {
        let parts = clauses(answer)
        guard parts.count >= 2 else { return nil }
        var denied: [(offset: Int, words: Set<String>)] = []
        var affirmed: [(offset: Int, words: Set<String>)] = []
        for (offset, clause) in parts.enumerated() {
            let words = subjectWords(clause)
            if VidurRx.matches(negation, clause) { denied.append((offset, words)) }
            let rest = VidurRx.replacing(negation, in: clause, with: " ")
            if VidurRx.matches(positive, rest) { affirmed.append((offset, words)) }
        }
        for no in denied {
            for yes in affirmed where yes.offset != no.offset {
                if let shared = no.words.intersection(yes.words).sorted().first { return shared }
            }
        }
        return nil
    }

    /// Replacement wording from the saved minutes, or nil when the reply does not contradict itself or no saved
    /// decision or open issue matches the subject.
    public static func fix(answer: String, retrieval: VidurRagRetrieval, calendar: Calendar = .current) -> VidurContradictionFix? {
        guard let subject = conflictingSubject(in: answer) else { return nil }
        let wanted = Set(VidurScript.keys(forWord: subject))
        let format = VidurRagFormat(calendar: calendar)
        for chunk in retrieval.hits where chunk.kind == .decision || chunk.kind == .openIssue {
            guard !wanted.isDisjoint(with: Set(chunk.keys)) else { continue }
            var body = chunk.minutesText
            while let last = body.last, ".!? ".contains(last) { body.removeLast() }
            guard !body.isEmpty else { continue }
            let place = "\(chunk.meetingTitle) (\(format.day(chunk.meetingDate)))"
            let text = chunk.kind == .decision
                ? "In \(place), the saved decision is: \(body)."
                : "In \(place), this is still an open issue: \(body)."
            return VidurContradictionFix(text: text, chunk: chunk)
        }
        return nil
    }
}

extension VidurRagChunk {
    /// The decision or open issue as written in the minutes, without the label and the "decided by" tail.
    public var minutesText: String {
        var value = text
        for label in ["Decision: ", "Open issue: "] where value.hasPrefix(label) {
            value = String(value.dropFirst(label.count))
        }
        for marker in [" (decided by ", " (raised by ", " Reason or words:"] {
            if let range = value.range(of: marker) { value = String(value[value.startIndex..<range.lowerBound]) }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
