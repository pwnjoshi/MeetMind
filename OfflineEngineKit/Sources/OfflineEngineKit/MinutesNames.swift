import Foundation

/// Small regex helpers shared by the minutes builder.
enum MinutesRegex {
    static func replace(_ pattern: String, in text: String, with template: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), group < match.numberOfRanges,
              let found = Range(match.range(at: group), in: text) else { return nil }
        return String(text[found])
    }

    static func matches(_ pattern: String, in text: String) -> Bool {
        firstMatch(pattern, in: text) != nil
    }
}

/// A person named in the conversation.
struct NameMention {
    enum Kind { case addressed, introduced, mentioned }
    let name: String
    let turnIndex: Int
    let quote: String
    let kind: Kind
}

/// Finds names spoken in the conversation: vocatives ("Pawan, ..."), thanks ("Thank you Pawan"),
/// self-introductions ("main Pawan bol raha hoon") and reported speech ("Neha ne kaha").
enum NameMentions {
    private static let extraNotNames: Set<String> = [
        "however", "meanwhile", "moreover", "therefore", "anyway", "honestly", "firstly", "secondly", "lastly",
        "overall", "additionally", "otherwise", "indeed", "welcome", "congratulations", "namaskar", "pranam",
        "dear", "gentlemen", "ladies", "listen", "look", "see", "hold", "stop", "exactly", "absolutely",
        "definitely", "certainly", "alright", "cheers", "regards", "personally", "generally", "technically",
        "ideally", "hopefully", "unfortunately", "fortunately", "obviously", "clearly", "simply", "seriously",
        "frankly", "likewise", "besides", "still", "thankyou", "wow", "hmm", "oops", "pune", "mumbai", "delhi",
        "bengaluru", "bangalore", "chennai", "hyderabad", "kolkata", "india", "stripe"
    ]

    private static let devanagariNotNames: Set<String> = {
        let words: [String] = [
            "\u{0928}\u{092E}\u{0938}\u{094D}\u{0915}\u{093E}\u{0930}", "\u{092A}\u{094D}\u{0930}\u{0923}\u{093E}\u{092E}",
            "\u{092D}\u{0948}\u{092F}\u{093E}", "\u{0926}\u{0940}\u{0926}\u{0940}", "\u{0938}\u{0930}",
            "\u{092E}\u{0948}\u{0921}\u{092E}", "\u{0926}\u{094B}\u{0938}\u{094D}\u{0924}\u{094B}\u{0902}",
            "\u{0938}\u{093E}\u{0925}\u{093F}\u{092F}\u{094B}\u{0902}", "\u{0935}\u{093E}\u{0939}",
            "\u{0913}\u{0939}", "\u{0939}\u{092E}\u{094D}\u{092E}", "\u{0916}\u{0948}\u{0930}",
            "\u{092C}\u{0922}\u{093C}\u{093F}\u{092F}\u{093E}", "\u{092C}\u{093E}\u{0926} \u{092E}\u{0947}\u{0902}",
            "\u{0927}\u{0928}\u{094D}\u{092F}\u{0935}\u{093E}\u{0926}"
        ]
        return Set(words.map { HindiText.normalized($0) })
    }()

    private static let fillers: Set<String> = {
        var set = HindiMeetingExtractor.leadFillers
        for word in ["hey", "chalo", "dear", "hmm", "but", "now", "next", "alright", "hai", "thik", "okay", "ok"] {
            set.insert(word)
        }
        return set
    }()

    private static let addressCues: Set<String> = ["kya", "tum", "aap", "please", "plz", "can", "could", "would", "you", "ji"]
    private static let reportingWords: Set<String> = [
        "ne", "said", "mentioned", "suggested", "proposed", "asked", "agreed", "kaha", "bola", "boli", "bataya"
    ]
    private static let speakingWords: Set<String> = ["bol", "bola", "bolta", "bolti", "baat", "speaking", "here"]

    static func isNameToken(_ token: HindiToken) -> Bool {
        if token.isDevanagari {
            guard !token.isKnown, token.raw.unicodeScalars.count >= 2 else { return false }
            if devanagariNotNames.contains(HindiText.normalized(token.raw)) { return false }
            return HindiText.transliterate(token.raw).count >= 2
        }
        let raw = token.raw
        guard raw.count >= 2, raw.count <= 24, let first = raw.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else { return false }
        for scalar in raw.unicodeScalars {
            let allowed = CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "-"
            if !allowed { return false }
        }
        let lower = raw.lowercased()
        if ActionExtractor.nameStopwords.contains(lower) || extraNotNames.contains(lower) { return false }
        if HindiText.isRomanHindiWord(token.key) { return false }
        if raw.count <= 4, raw == raw.uppercased() { return false }
        return true
    }

    static func displayName(_ token: HindiToken) -> String {
        var name = HindiText.displayName(token.raw)
        if name.hasSuffix("'s") { name = String(name.dropLast(2)) }
        return name
    }

    static func scan(_ turns: [AnalysisTurn]) -> [NameMention] {
        let pieces = ActionExtractor.sentencePieces(turns)
        var mentions: [NameMention] = []
        for (turnIndex, turnPieces) in pieces.enumerated() {
            for piece in turnPieces {
                let tokens = HindiText.tokenize(piece)
                guard !tokens.isEmpty else { continue }
                var consumed = Set<Int>()
                // Leading vocative, with optional fillers and "thank you".
                var index = 0
                var sawThanks = false
                while index < tokens.count, index < 4 {
                    let key = tokens[index].key
                    if key == "thank" || key == "thanks" { sawThanks = true; index += 1; continue }
                    if sawThanks && key == "you" { index += 1; continue }
                    if fillers.contains(key) { index += 1; continue }
                    break
                }
                if index < tokens.count, isNameToken(tokens[index]) {
                    let token = tokens[index]
                    let nextKey = index + 1 < tokens.count ? tokens[index + 1].key : ""
                    let atEnd = index + 1 == tokens.count
                    if token.commaAfter || addressCues.contains(nextKey) || (atEnd && (sawThanks || index >= 1)) {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .addressed))
                        consumed.insert(index)
                    }
                }
                // Reported speech, "<Name> bol raha hoon", "my name is <Name>", "mera naam <Name>".
                for position in 0..<tokens.count where !consumed.contains(position) {
                    let token = tokens[position]
                    guard isNameToken(token) else { continue }
                    let nextKey = position + 1 < tokens.count ? tokens[position + 1].key : ""
                    let previousKey = position >= 1 ? tokens[position - 1].key : ""
                    let beforeThat = position >= 2 ? tokens[position - 2].key : ""
                    if reportingWords.contains(nextKey) {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .mentioned))
                    } else if (previousKey == "is" && beforeThat == "name") || previousKey == "naam" {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .introduced))
                    } else if (previousKey == "main" || previousKey == "mai"), speakingWords.contains(nextKey) {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .introduced))
                    } else if position == 0, nextKey == "bol" || nextKey == "speaking" {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .introduced))
                    } else if previousKey == "is" && beforeThat == "this" && (nextKey == "speaking" || nextKey == "here") {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .introduced))
                    } else if nextKey == "ko", !token.isDevanagari {
                        mentions.append(NameMention(name: displayName(token), turnIndex: turnIndex, quote: piece,
                                                    kind: .mentioned))
                    }
                }
            }
        }
        return mentions
    }
}

/// Maps anonymous voice labels ("S1", "Speaker 2") to attendees, using the conversation itself:
/// the person addressed by name speaks next, and a self-introduction names the current voice.
enum SpeakerNameInference {
    static func isGenericLabel(_ label: String) -> Bool {
        let compact = label.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        if compact.hasPrefix("speaker") || compact.hasPrefix("spk") || compact.hasPrefix("unknown") { return true }
        if compact.hasPrefix("s"), compact.count >= 2 {
            return compact.dropFirst().allSatisfy { $0.isNumber }
        }
        return false
    }

    static func infer(turns: [AnalysisTurn], participants: [String], speakerNames: [String: String]) -> [String: String] {
        let people = participants.filter { !isGenericLabel($0) }
        guard !people.isEmpty else { return speakerNames }
        var result = speakerNames
        var votes: [String: [String: Int]] = [:]
        for mention in NameMentions.scan(turns) {
            guard let person = HindiText.matchParticipant(mention.name, participants: people) else { continue }
            let label = turns[mention.turnIndex].speaker
            switch mention.kind {
            case .introduced:
                if let label = label, isGenericLabel(label) {
                    var counts = votes[label] ?? [:]
                    counts[person, default: 0] += 2
                    votes[label] = counts
                }
            case .addressed:
                var next = mention.turnIndex + 1
                while next < turns.count, next <= mention.turnIndex + 2 {
                    if let other = turns[next].speaker, other != label {
                        if isGenericLabel(other) {
                            var counts = votes[other] ?? [:]
                            counts[person, default: 0] += 1
                            votes[other] = counts
                        }
                        break
                    }
                    next += 1
                }
            case .mentioned:
                break
            }
        }
        var taken = Set<String>(result.values.map { $0.lowercased() })
        var candidates: [(label: String, person: String, count: Int)] = []
        for (label, counts) in votes where result[label] == nil {
            let ranked = counts.sorted { $0.value > $1.value }
            guard let best = ranked.first else { continue }
            if ranked.count > 1, ranked[1].value == best.value { continue }
            candidates.append((label: label, person: best.key, count: best.value))
        }
        candidates.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }
        for candidate in candidates where !taken.contains(candidate.person.lowercased()) {
            result[candidate.label] = candidate.person
            taken.insert(candidate.person.lowercased())
        }
        // Two voices and two named people, one already resolved: the other voice is the other person.
        let labels = Array(Set(turns.compactMap { $0.speaker }.filter { isGenericLabel($0) })).sorted()
        if labels.count == 2, people.count == 2 {
            let unresolved = labels.filter { result[$0] == nil }
            let remaining = people.filter { !taken.contains($0.lowercased()) }
            if unresolved.count == 1, remaining.count == 1 { result[unresolved[0]] = remaining[0] }
        }
        return result
    }
}

/// People named in the meeting who are not attendees yet. Suggestions only; nothing is added automatically.
enum AttendeeSuggester {
    private struct Entry {
        var name: String
        var hasLatin: Bool
        var rank: Int
        var reason: String
        var evidence: [SourceEvidence]
    }

    private static func rank(_ reason: String) -> Int {
        switch reason {
        case "introduced": return 4
        case "addressed": return 3
        case "assigned": return 2
        default: return 1
        }
    }

    static func suggest(turns: [AnalysisTurn], tasks: [SuggestedTask], participants: [String],
                        speakerNames: [String: String]) -> [SuggestedAttendee] {
        let known = participants.filter { !SpeakerNameInference.isGenericLabel($0) } + Array(speakerNames.values)
        var entries: [Entry] = []
        func record(name rawName: String, reason: String, evidence: SourceEvidence) {
            let name = HindiText.displayName(rawName)
            guard name.count >= 2, HindiText.matchParticipant(name, participants: known) == nil else { return }
            let isLatin = !HindiText.containsDevanagari(rawName)
            if let index = entries.firstIndex(where: { HindiText.namesMatch($0.name, name) }) {
                if isLatin && !entries[index].hasLatin {
                    entries[index].name = name
                    entries[index].hasLatin = true
                }
                if rank(reason) > entries[index].rank {
                    entries[index].rank = rank(reason)
                    entries[index].reason = reason
                }
                let duplicate = entries[index].evidence.contains { $0.turnID == evidence.turnID && $0.quote == evidence.quote }
                if !duplicate, entries[index].evidence.count < 2 { entries[index].evidence.append(evidence) }
            } else {
                entries.append(Entry(name: name, hasLatin: isLatin, rank: rank(reason), reason: reason, evidence: [evidence]))
            }
        }
        for mention in NameMentions.scan(turns) {
            let reason: String
            switch mention.kind {
            case .addressed: reason = "addressed"
            case .introduced: reason = "introduced"
            case .mentioned: reason = "mentioned"
            }
            record(name: mention.name, reason: reason,
                   evidence: SourceEvidence(turnID: turns[mention.turnIndex].id, quote: mention.quote))
        }
        for task in tasks {
            guard let owner = task.owner, let evidence = task.evidence.first else { continue }
            if SpeakerNameInference.isGenericLabel(owner) || owner.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            record(name: owner, reason: "assigned", evidence: evidence)
        }
        return entries.map { SuggestedAttendee(name: $0.name, reason: $0.reason, evidence: $0.evidence) }
    }
}
