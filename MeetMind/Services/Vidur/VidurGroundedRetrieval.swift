import Foundation
import OfflineEngineKit

// MARK: - Snippet

/// One numbered piece of meeting text that Vidur may show to the model and cite as a source.
public struct VidurContextSnippet: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case summary, agenda, attendance, decision, action, openIssue, discussion, transcript, note

        public var isMinutes: Bool { self != .transcript && self != .note }

        /// Heading of a source row for minutes items.
        public var sourceLabel: String? {
            switch self {
            case .summary: return "Summary"
            case .agenda: return "Agenda"
            case .attendance: return "Attendees"
            case .decision: return "Decision"
            case .action: return "Action"
            case .openIssue: return "Open issue"
            case .discussion: return "Discussion"
            case .transcript: return nil
            case .note: return "Note"
            }
        }
    }

    public let kind: Kind
    /// Exactly what the model reads after the snippet number.
    public let text: String
    /// Text used for ranking. It leaves out timecodes so digits do not match by accident.
    public let searchText: String
    public let meetingID: UUID?
    public let meetingTitle: String
    public let timestamp: TimeInterval?
    /// The wording shown in a source row: a transcript turn or the minutes item.
    public let quote: String
    public let speaker: String?
    public let isPinned: Bool
    /// Position in `sources` for transcript turns and notes, used to add neighbouring turns.
    public let meetingIndex: Int?
    public let turnIndex: Int?

    public init(kind: Kind, text: String, searchText: String? = nil, meetingID: UUID?, meetingTitle: String,
                timestamp: TimeInterval? = nil, quote: String? = nil, speaker: String? = nil, isPinned: Bool = false,
                meetingIndex: Int? = nil, turnIndex: Int? = nil) {
        self.kind = kind
        self.text = text
        self.searchText = searchText ?? text
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.timestamp = timestamp
        self.quote = quote ?? text
        self.speaker = speaker
        self.isPinned = isPinned
        self.meetingIndex = meetingIndex
        self.turnIndex = turnIndex
    }

    func pinned(_ value: Bool) -> VidurContextSnippet {
        VidurContextSnippet(kind: kind, text: text, searchText: searchText, meetingID: meetingID,
                            meetingTitle: meetingTitle, timestamp: timestamp, quote: quote, speaker: speaker,
                            isPinned: value, meetingIndex: meetingIndex, turnIndex: turnIndex)
    }
}

// MARK: - Building snippets from minutes, transcript and notes

public enum VidurSnippetBuilder {
    static let maximumMinutesCharacters = 420

    /// "S1", "s2", "speaker_3" become "Speaker 1" etc. Real names pass through.
    public static func displayName(_ raw: String?) -> String {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return "Unknown speaker" }
        let lowered = name.lowercased()
        var digits = ""
        if lowered.hasPrefix("speaker") { digits = String(lowered.dropFirst(7)).filter(\.isNumber) }
        else if lowered.hasPrefix("s"), lowered.dropFirst().allSatisfy(\.isNumber), lowered.count > 1 { digits = String(lowered.dropFirst()) }
        return digits.isEmpty ? name : "Speaker \(digits)"
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "\u{2026}" : flat
    }

    static func dateText(_ date: Date, style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Everything the saved minutes say about one meeting, one snippet per item.
    public static func minutes(_ facts: VidurMeetingFacts, tagged: Bool) -> [VidurContextSnippet] {
        let tag = tagged ? "[\(facts.title), \(dateText(facts.date))] " : ""
        var output: [VidurContextSnippet] = []
        func add(_ kind: VidurContextSnippet.Kind, _ body: String, timestamp: TimeInterval? = nil,
                 quote: String? = nil, speaker: String? = nil, pinned: Bool = false, limit: Int = VidurSnippetBuilder.maximumMinutesCharacters) {
            let trimmed = clip(body, limit)
            guard !trimmed.isEmpty else { return }
            output.append(VidurContextSnippet(
                kind: kind, text: tag + trimmed, searchText: trimmed, meetingID: facts.meetingID,
                meetingTitle: facts.title, timestamp: timestamp, quote: quote ?? trimmed, speaker: speaker,
                isPinned: pinned))
        }

        var header = "Meeting \"\(facts.title)\" on \(dateText(facts.date, style: .long))"
        if facts.duration > 0 { header += " (\(VidurStructuredAnswerer.durationText(facts.duration)))" }
        let summary = facts.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        add(.summary, "Summary: " + header + ". " + summary, pinned: true, limit: 640)

        if !facts.agenda.isEmpty { add(.agenda, "Agenda: " + facts.agenda.joined(separator: "; ")) }
        if !facts.attendees.isEmpty || !facts.absent.isEmpty {
            var text = facts.attendanceRecorded ? "Attendees present: " : "Participants (attendance not confirmed): "
            text += facts.attendees.isEmpty ? "none" : facts.attendees.joined(separator: ", ")
            text += "."
            if !facts.absent.isEmpty { text += " Absent: " + facts.absent.joined(separator: ", ") + "." }
            add(.attendance, text)
        }
        for decision in facts.decisions {
            var text = "Decision: " + decision.text
            if let speaker = decision.speaker, !speaker.isEmpty { text += " (decided by \(displayName(speaker)))" }
            if let stamp = decision.timestamp { text += " [\(VidurTimecode.string(stamp))]" }
            add(.decision, text, timestamp: decision.timestamp, quote: decision.text, speaker: decision.speaker)
        }
        let due = DateFormatter()
        due.dateStyle = .medium
        due.timeStyle = .none
        for task in facts.tasks {
            var parts = ["Action: " + task.title]
            if let owner = task.owner, !owner.isEmpty { parts.append("owner: \(owner)") } else { parts.append("owner: not set") }
            if let date = task.dueDate { parts.append("due: \(due.string(from: date))") }
            else if let text = task.dueText, !text.isEmpty { parts.append("due: \(text)") }
            else { parts.append("due: not set") }
            parts.append(task.isCompleted ? "status: done" : "status: open")
            parts.append(task.isSuggestion ? "suggested by Vidur, not yet accepted" : "accepted")
            add(.action, parts.joined(separator: " | "), timestamp: task.timestamp, quote: task.title)
        }
        for issue in facts.openIssues {
            add(.openIssue, "Open issue: " + issue.text, timestamp: issue.timestamp, quote: issue.text, speaker: issue.speaker)
        }
        for line in facts.discussion where line != facts.summary {
            add(.discussion, "Discussion: " + line)
        }
        return output
    }

    /// Every transcript turn and typed note of one meeting, with the speaker's display name.
    public static func transcript(_ source: VidurSourceMeeting, meetingIndex: Int, tagged: Bool) -> [VidurContextSnippet] {
        let tag = tagged ? "[\(source.title), \(dateText(source.date))] " : ""
        var output: [VidurContextSnippet] = []
        output.reserveCapacity(source.turns.count)
        for (turnIndex, turn) in source.turns.enumerated() {
            let isNote = turn.speaker == "Note"
            let name = isNote ? "Note" : displayName(turn.speaker)
            let stamp = VidurTimecode.string(turn.start)
            let body = clip(turn.text, VidurGroundedRetriever.maximumTurnCharacters)
            output.append(VidurContextSnippet(
                kind: isNote ? .note : .transcript, text: "\(tag)\(name) [\(stamp)]: \(body)",
                searchText: isNote ? body : "\(name) \(body)", meetingID: source.id, meetingTitle: source.title,
                timestamp: turn.start, quote: turn.text, speaker: isNote ? nil : turn.speaker,
                meetingIndex: meetingIndex, turnIndex: turnIndex))
        }
        return output
    }

    /// Minutes first, then transcript and notes, for every meeting in scope.
    public static func corpus(sources: [VidurSourceMeeting], facts: [VidurMeetingFacts]) -> [VidurContextSnippet] {
        let tagged = max(sources.count, facts.count) > 1
        var output: [VidurContextSnippet] = []
        var seenFacts = Set<UUID>()
        for item in facts where seenFacts.insert(item.meetingID).inserted {
            output += minutes(item, tagged: tagged)
        }
        for (index, source) in sources.enumerated() {
            output += transcript(source, meetingIndex: index, tagged: tagged)
        }
        return output
    }
}

// MARK: - Cross-script keys

public enum VidurTransliteration {
    private static let devanagari: [UInt32: String] = [
        0x0901: "n", 0x0902: "n",
        0x0915: "k", 0x0916: "k", 0x0917: "g", 0x0918: "g", 0x0919: "n",
        0x091A: "C", 0x091B: "C", 0x091C: "j", 0x091D: "j", 0x091E: "n",
        0x091F: "t", 0x0920: "t", 0x0921: "d", 0x0922: "d", 0x0923: "n",
        0x0924: "t", 0x0925: "t", 0x0926: "d", 0x0927: "d", 0x0928: "n",
        0x092A: "p", 0x092B: "p", 0x092C: "b", 0x092D: "b", 0x092E: "m",
        0x092F: "", 0x0930: "r", 0x0932: "l", 0x0933: "l", 0x0935: "v",
        0x0936: "s", 0x0937: "s", 0x0938: "s", 0x0939: "",
        0x0958: "k", 0x0959: "k", 0x095A: "g", 0x095B: "j", 0x095C: "r", 0x095D: "r", 0x095E: "p", 0x095F: ""
    ]

    /// A coarse consonant skeleton shared by Roman and Devanagari spellings: "Pawan" and its Devanagari
    /// spelling both give "pvn"; "Rahul" and its Devanagari spelling both give "rl".
    /// Vowels, h and y are dropped; w=v, f=ph=p, z=j, q=c=k, ch=C, kh/gh/th/dh/bh/sh/jh fold to one letter.
    public static func skeleton(_ word: String) -> String {
        let scalars = Array(word.lowercased().unicodeScalars)
        var output: [Character] = []
        func push(_ text: String) {
            for character in text where output.last != character { output.append(character) }
        }
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if (0x0900...0x097F).contains(scalar.value) {
                if scalar.value == 0x0915, index + 2 < scalars.count, scalars[index + 1].value == 0x094D, scalars[index + 2].value == 0x0937 {
                    push("ks")
                    index += 3
                    continue
                }
                if let mapped = devanagari[scalar.value] { push(mapped) }
                index += 1
                continue
            }
            guard scalar.isASCII, scalar.properties.isAlphabetic else { index += 1; continue }
            let character = Character(scalar)
            let next: Character? = index + 1 < scalars.count && scalars[index + 1].isASCII ? Character(scalars[index + 1]) : nil
            if next == "h" {
                switch character {
                case "c": push("C"); index += 2; continue
                case "k", "g", "t", "d", "b", "s", "j", "p": push(String(character)); index += 2; continue
                default: break
                }
            }
            switch character {
            case "a", "e", "i", "o", "u", "y", "h": break
            case "w": push("v")
            case "f": push("p")
            case "z": push("j")
            case "q": push("k")
            case "x": push("ks")
            case "c": push(next == "e" || next == "i" ? "s" : "k")
            default: push(String(character))
            }
            index += 1
        }
        return String(output)
    }

    static func isDevanagari(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }
}

// MARK: - Retrieval

public enum VidurGroundedRetriever {
    public static let maximumTurnCharacters = 420
    public static let defaultLimit = 28

    private static let devanagariStopWords: Set<String> = [
        "\u{0939}\u{0948}", "\u{0939}\u{0948}\u{0902}", "\u{0925}\u{093E}", "\u{0925}\u{0940}", "\u{0925}\u{0947}",
        "\u{0915}\u{093E}", "\u{0915}\u{0940}", "\u{0915}\u{0947}", "\u{0915}\u{094B}", "\u{092E}\u{0947}\u{0902}",
        "\u{0938}\u{0947}", "\u{092A}\u{0930}", "\u{0928}\u{0947}", "\u{0914}\u{0930}", "\u{092F}\u{093E}",
        "\u{0924}\u{094B}", "\u{092D}\u{0940}", "\u{0915}\u{094D}\u{092F}\u{093E}", "\u{0915}\u{092C}",
        "\u{0915}\u{094C}\u{0928}", "\u{0915}\u{093F}\u{0938}\u{0928}\u{0947}", "\u{092F}\u{0939}", "\u{0935}\u{0939}",
        "\u{0907}\u{0938}", "\u{0909}\u{0938}", "\u{0915}\u{093F}", "\u{0939}\u{092E}", "\u{0906}\u{092A}",
        "\u{092E}\u{0948}\u{0902}", "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0932}\u{093F}\u{090F}", "\u{0917}\u{092F}\u{093E}",
        "\u{0917}\u{0908}", "\u{0915}\u{0930}", "\u{0915}\u{0930}\u{0928}\u{093E}", "\u{0939}\u{0941}\u{0906}",
        "\u{0939}\u{0941}\u{0908}", "\u{0939}\u{094B}", "\u{0939}\u{094B}\u{0917}\u{093E}", "\u{0939}\u{094B}\u{0917}\u{0940}",
        "\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}", "\u{0915}\u{0948}\u{0938}\u{0947}", "\u{0915}\u{0939}\u{093E}\u{0901}",
        "\u{0915}\u{0939}\u{093E}\u{0902}", "\u{092C}\u{093E}\u{0930}\u{0947}", "\u{0905}\u{092D}\u{0940}"
    ]

    // MARK: Synonyms

    private struct SynonymGroup {
        let words: [String]
        let kinds: Set<VidurContextSnippet.Kind>
    }

    private static let synonymGroups: [SynonymGroup] = [
        SynonymGroup(words: ["task", "action", "todo", "kaam", "\u{0915}\u{093E}\u{092E}", "\u{0915}\u{093E}\u{0930}\u{094D}\u{092F}",
                             "assign", "owner", "responsible", "deliverable", "zimmedari", "\u{091C}\u{093F}\u{092E}\u{094D}\u{092E}\u{0947}\u{0926}\u{093E}\u{0930}\u{0940}",
                             "followup", "commit", "karega", "karegi"], kinds: [.action]),
        SynonymGroup(words: ["decision", "decide", "decided", "faisla", "faisle", "\u{092B}\u{0948}\u{0938}\u{0932}\u{093E}",
                             "\u{092B}\u{0948}\u{0938}\u{0932}\u{0947}", "\u{0928}\u{093F}\u{0930}\u{094D}\u{0923}\u{092F}", "nirnay",
                             "tay", "\u{0924}\u{092F}", "final", "finalize", "finalized", "approved", "approve", "agreed"], kinds: [.decision]),
        SynonymGroup(words: ["deadline", "due", "tak", "\u{0924}\u{0915}", "tarikh", "\u{0924}\u{093E}\u{0930}\u{0940}\u{0916}",
                             "samay", "samaysima", "\u{0938}\u{092E}\u{092F}\u{0938}\u{0940}\u{092E}\u{093E}"], kinds: [.action, .decision]),
        SynonymGroup(words: ["attendee", "attended", "present", "absent", "participant", "hazir", "haazir",
                             "\u{0909}\u{092A}\u{0938}\u{094D}\u{0925}\u{093F}\u{0924}", "\u{0905}\u{0928}\u{0941}\u{092A}\u{0938}\u{094D}\u{0925}\u{093F}\u{0924}"], kinds: [.attendance]),
        SynonymGroup(words: ["issue", "unresolved", "open", "pending", "problem", "risk", "concern", "blocker", "samasya",
                             "\u{0938}\u{092E}\u{0938}\u{094D}\u{092F}\u{093E}", "baaki", "\u{092C}\u{093E}\u{0915}\u{0940}"], kinds: [.openIssue]),
        SynonymGroup(words: ["summary", "discussed", "discussion", "agenda", "topic", "saransh", "\u{0938}\u{093E}\u{0930}\u{093E}\u{0902}\u{0936}",
                             "\u{091A}\u{0930}\u{094D}\u{091A}\u{093E}", "charcha", "overview", "recap"], kinds: [.summary, .discussion, .agenda])
    ]

    private static let synonymTokenSets: [(tokens: Set<String>, group: SynonymGroup)] = synonymGroups.map { group in
        (Set(group.words.flatMap { VidurGroundedRetriever.terms($0) }), group)
    }

    // MARK: Tokens and keys

    /// Latin and Devanagari content words (stop words removed, Latin stemmed).
    static func terms(_ text: String) -> [String] {
        VidurTokenizer.tokens(text).filter { !devanagariStopWords.contains($0) }
    }

    struct NameIndex {
        let skeletons: Set<String>
        let exact: Set<String>

        init(names: [String]) {
            var skeletons = Set<String>()
            var exact = Set<String>()
            for name in names {
                for token in name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                where token.count >= 2 {
                    exact.insert(token)
                    let skeleton = VidurTransliteration.skeleton(token)
                    if !skeleton.isEmpty { skeletons.insert(skeleton) }
                }
            }
            self.skeletons = skeletons
            self.exact = exact
        }

        func key(for token: String, skeleton: String) -> String? {
            guard skeletons.contains(skeleton) else { return nil }
            if skeleton.count >= 2 || exact.contains(token) { return "nm:" + skeleton }
            if VidurTransliteration.isDevanagari(token), token.unicodeScalars.count >= 3 { return "nm:" + skeleton }
            return nil
        }
    }

    static func keys(_ text: String, names: NameIndex) -> [String] {
        var output: [String] = []
        for token in terms(text) {
            output.append(token)
            let skeleton = VidurTransliteration.skeleton(token)
            guard !skeleton.isEmpty else { continue }
            if skeleton.count >= 3 { output.append("sk:" + skeleton) }
            if let name = names.key(for: token, skeleton: skeleton) { output.append(name) }
        }
        return output
    }

    /// Short follow-ups ("aur Neha ne?") borrow the previous question's words.
    public static func retrievalQuery(question: String, history: [VidurChatTurn]) -> String {
        guard let previous = history.last?.question else { return question }
        return terms(question).count <= 3 ? previous + " " + question : question
    }

    // MARK: Selection

    /// Picks the snippets to show the model, best first: the minutes summary, minutes items that name
    /// someone from the question, then hybrid-ranked snippets (BM25 over words, synonyms and
    /// cross-script keys), their neighbouring transcript turns, and finally minutes items that match the
    /// kind of question asked.
    public static func select(question: String, history: [VidurChatTurn] = [], corpus: [VidurContextSnippet],
                              names: [String] = [], limit: Int = defaultLimit) -> [VidurContextSnippet] {
        guard !corpus.isEmpty, limit > 0 else { return [] }
        let speakers = corpus.compactMap { $0.kind == .transcript ? $0.speaker : nil }
        let index = NameIndex(names: names + speakers)
        let query = retrievalQuery(question: question, history: history)
        let queryKeys = keys(query, names: index)
        let queryTerms = Set(terms(query))
        let documents = corpus.map { keys($0.searchText, names: index) }

        var expandedTokens = Set<String>()
        var boostedKinds = Set<VidurContextSnippet.Kind>()
        for entry in synonymTokenSets where !entry.tokens.isDisjoint(with: queryTerms) {
            expandedTokens.formUnion(entry.tokens)
            boostedKinds.formUnion(entry.group.kinds)
        }
        expandedTokens.subtract(queryTerms)

        var scores = [Double](repeating: 0, count: corpus.count)
        for hit in VidurBM25.rank(queryTokens: queryKeys, documents: documents, limit: corpus.count) {
            scores[hit.index] += hit.score
        }
        if !expandedTokens.isEmpty {
            for hit in VidurBM25.rank(queryTokens: Array(expandedTokens), documents: documents, limit: corpus.count) {
                scores[hit.index] += hit.score * 0.4
            }
        }
        for position in corpus.indices where scores[position] > 0 && boostedKinds.contains(corpus[position].kind) {
            scores[position] *= 1.5
        }

        let nameKeys = Set(queryKeys.filter { $0.hasPrefix("nm:") })
        var chosen: [Int] = []
        var used = Set<Int>()
        func take(_ position: Int) {
            guard chosen.count < limit, used.insert(position).inserted else { return }
            chosen.append(position)
        }

        let ranked = corpus.indices.filter { scores[$0] > 0 }.sorted {
            scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1
        }

        // 1. Minutes summaries of the meetings the best hits come from (all of them for one meeting).
        let hitMeetings = Set(ranked.prefix(6).compactMap { corpus[$0].meetingID })
        var summaries = corpus.indices.filter { corpus[$0].kind == .summary }
        if summaries.count > 1 {
            let relevant = summaries.filter { corpus[$0].meetingID.map(hitMeetings.contains) ?? false }
            summaries = Array((relevant.isEmpty ? [summaries[summaries.count - 1]] : relevant).prefix(3))
        }
        summaries.forEach(take)

        // 2. Minutes items that mention a person named in the question.
        if !nameKeys.isEmpty {
            var named = 0
            for position in corpus.indices where corpus[position].kind.isMinutes && !nameKeys.isDisjoint(with: documents[position]) {
                guard named < 6 else { break }
                named += 1
                take(position)
            }
        }
        let pinnedCount = chosen.count

        // 3. Best ranked snippets, then neighbouring turns of the top transcript hits.
        ranked.prefix(14).forEach(take)
        var lookup: [String: Int] = [:]
        for position in corpus.indices {
            if let meeting = corpus[position].meetingIndex, let turn = corpus[position].turnIndex {
                lookup["\(meeting)|\(turn)"] = position
            }
        }
        var neighboursAdded = 0
        for position in ranked where neighboursAdded < 3 {
            guard let meeting = corpus[position].meetingIndex, let turn = corpus[position].turnIndex,
                  corpus[position].kind == .transcript else { continue }
            neighboursAdded += 1
            for step in [-1, 1] {
                if let neighbour = lookup["\(meeting)|\(turn + step)"], corpus[neighbour].kind == .transcript { take(neighbour) }
            }
        }

        // 4. Minutes items of the kind the question asks about, then the rest of the ranking.
        if !boostedKinds.isEmpty {
            var added = 0
            for position in corpus.indices where boostedKinds.contains(corpus[position].kind) && added < 8 {
                if used.contains(position) { continue }
                added += 1
                take(position)
            }
        }
        ranked.dropFirst(14).forEach(take)

        // 5. A generic question still gets the saved minutes.
        let baseline: [VidurContextSnippet.Kind] = [.decision, .action, .openIssue, .discussion, .attendance, .agenda]
        for kind in baseline {
            for position in corpus.indices where corpus[position].kind == kind { take(position) }
        }

        return chosen.enumerated().map { offset, position in
            corpus[position].pinned(offset < pinnedCount && corpus[position].kind.isMinutes)
        }
    }
}
