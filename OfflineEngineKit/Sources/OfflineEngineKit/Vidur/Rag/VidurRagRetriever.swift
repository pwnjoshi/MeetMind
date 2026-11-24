import Foundation

// Hybrid retrieval over a VidurRagIndex:
//   1. The question parser turns words into metadata filters: people, "last meeting", dates, meeting
//      titles, task status, and what kind of record the question is about (decisions, actions...).
//   2. BM25 ranks the chunks of the meetings in scope on words, cross-script keys and name spellings.
//   3. A metadata ranker orders the chunks by how well their kind, person and status fit the question.
//   4. Reciprocal rank fusion merges the two rankings.
//   5. The top k are picked so that no one meeting fills them all and no two transcript windows repeat
//      the same lines.
//   6. The structured facts block of the best meetings always comes along.

public struct VidurRagQuery: Sendable {
    public var question: String
    public var history: [VidurChatTurn]
    /// Names the user goes by, so "my tasks" and "what do I owe" find their own records.
    public var selfNames: [String]
    public var now: Date
    public var calendar: Calendar
    /// How many retrieved chunks to return, not counting facts blocks.
    public var limit: Int

    public init(question: String, history: [VidurChatTurn] = [], selfNames: [String] = [], now: Date = Date(),
                calendar: Calendar = .current, limit: Int = 6) {
        self.question = question
        self.history = history
        self.selfNames = selfNames
        self.now = now
        self.calendar = calendar
        self.limit = limit
    }
}

/// What the question parser asked retrieval to filter on. For diagnostics and tests.
public struct VidurRagFilters: Sendable, Equatable {
    public var people: [String] = []
    public var intents: [VidurQuickIntent] = []
    public var meetingTitles: [String] = []
    public var lastMeeting = false
    public var rangeLabel: String?
    /// True when the meeting filters matched nothing, so every meeting was searched instead.
    public var relaxed = false
}

public struct VidurRagRetrieval: Sendable, Equatable {
    /// Structured facts blocks of the best meetings (at most two).
    public let facts: [VidurRagChunk]
    /// The best chunks, best first.
    public let hits: [VidurRagChunk]
    /// Meetings that passed the filters.
    public let scopedMeetings: [VidurRagMeeting]
    public let filters: VidurRagFilters
    /// Search keys of the question, used to pick the best lines inside a transcript chunk.
    let queryKeys: [String]

    public static let empty = VidurRagRetrieval(facts: [], hits: [], scopedMeetings: [], filters: VidurRagFilters(), queryKeys: [])

    public var isEmpty: Bool { hits.isEmpty }
}

public enum VidurRagRetriever {
    public static let defaultLimit = 6
    static let rankConstant = 60.0
    static let metadataWeight = 0.8

    public static func retrieve(_ query: VidurRagQuery, index: VidurRagIndex) -> VidurRagRetrieval {
        let question = query.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !index.isEmpty, !question.isEmpty, query.limit > 0 else { return .empty }

        // 1. Understand the question.
        let personIndex = VidurPersonIndex(names: index.names + query.selfNames)
        let selfPerson = query.selfNames.lazy.compactMap { personIndex.person(forRaw: $0) }.first
        var titles: [String] = []
        for meeting in index.meetings where !titles.contains(meeting.title) { titles.append(meeting.title) }
        var parsed = VidurQuestionParser.parse(question, index: personIndex, titles: titles, now: query.now,
                                               calendar: query.calendar)
        if let previous = query.history.last?.question, VidurQuickAnswerer.isFollowUp(parsed) {
            let before = VidurQuestionParser.parse(previous, index: personIndex, titles: titles, now: query.now,
                                                   calendar: query.calendar)
            parsed = VidurQuickAnswerer.merge(parsed, with: before)
        }
        if parsed.asksForSelf, parsed.people.isEmpty, let selfPerson { parsed.people = [selfPerson] }

        // 2. Metadata filter on meetings.
        let matchedTitles = parsed.matchedTitles
        var scoped = index.meetings
        if !matchedTitles.isEmpty { scoped = scoped.filter { matchedTitles.contains($0.title) } }
        if let range = parsed.meetingRange { scoped = scoped.filter { range.contains($0.date) } }
        if parsed.lastMeeting, let last = scoped.last { scoped = [last] }
        var relaxed = false
        if scoped.isEmpty {
            scoped = index.meetings
            relaxed = true
        }
        let scopedIDs = Set(scoped.map(\.id))
        var filters = VidurRagFilters()
        filters.people = parsed.people.map(\.canonical)
        filters.intents = parsed.intents
        filters.meetingTitles = matchedTitles
        filters.lastMeeting = parsed.lastMeeting
        filters.rangeLabel = parsed.rangeLabel
        filters.relaxed = relaxed

        let candidates = index.chunks.filter { scopedIDs.contains($0.meetingID) && $0.kind != .facts }
        guard !candidates.isEmpty else {
            return VidurRagRetrieval(facts: factsBlocks(for: scoped.suffix(1).map(\.id), index: index), hits: [],
                                     scopedMeetings: scoped, filters: filters, queryKeys: [])
        }

        // 3. Lexical ranking with cross-script query expansion.
        let queryText = lexicalQuery(question: question, history: query.history)
        var queryKeys = VidurScript.keys(VidurRagFormat.withRoman(queryText))
        for person in parsed.people {
            for first in person.firsts { queryKeys += VidurScript.keys(forWord: first) }
        }
        let lexical = VidurBM25.rank(queryTokens: queryKeys, documents: candidates.map(\.keys), limit: candidates.count)

        // 4. Metadata ranking.
        var wantedKinds = kinds(for: parsed.intents)
        // "Who said ...?" asks for the spoken words. A word like "decided" in the quote must not pull in
        // every decision of every meeting ahead of the transcript line that actually says it.
        if asksWhoSaid(question) {
            wantedKinds = [.transcript]
        }
        var prior = [Double](repeating: 0, count: candidates.count)
        for position in candidates.indices {
            let chunk = candidates[position]
            var score = 0.0
            if wantedKinds.contains(chunk.kind) { score += 2 }
            if !parsed.people.isEmpty {
                let about = parsed.people.contains { person in
                    chunk.people.contains { personIndex.matches($0, person) }
                }
                if about { score += 1.5 }
            }
            if chunk.kind == .action {
                score += taskBonus(chunk, filter: parsed.taskFilter, dueRange: parsed.dueRange, now: query.now)
            }
            prior[position] = score
        }
        let priorOrder = candidates.indices.filter { prior[$0] > 0 }.sorted { left, right in
            if prior[left] != prior[right] { return prior[left] > prior[right] }
            if candidates[left].meetingDate != candidates[right].meetingDate {
                return candidates[left].meetingDate > candidates[right].meetingDate
            }
            return left < right
        }

        // 5. Reciprocal rank fusion.
        var fused = [Double](repeating: 0, count: candidates.count)
        for (rank, hit) in lexical.enumerated() { fused[hit.index] += 1.0 / (rankConstant + Double(rank + 1)) }
        for (rank, position) in priorOrder.enumerated() {
            fused[position] += metadataWeight / (rankConstant + Double(rank + 1))
        }
        var order = candidates.indices.filter { fused[$0] > 0 }.sorted { fused[$0] != fused[$1] ? fused[$0] > fused[$1] : $0 < $1 }
        if order.isEmpty, parsed.residual.isEmpty, let last = scoped.last {
            // An open question with no topic words ("how did it go?") reads the latest minutes.
            let overview: Set<VidurRagKind> = [.summary, .decision, .discussion, .openIssue]
            order = candidates.indices.filter { candidates[$0].meetingID == last.id && overview.contains(candidates[$0].kind) }
        }

        // 6. Diversify by meeting and drop overlapping transcript windows.
        let cap = scoped.count <= 1 ? query.limit : max(2, (query.limit + 1) / 2)
        var chosen: [Int] = []
        var perMeeting: [UUID: Int] = [:]
        for position in order where chosen.count < query.limit {
            let chunk = candidates[position]
            if perMeeting[chunk.meetingID, default: 0] >= cap { continue }
            if chosen.contains(where: { overlaps(candidates[$0], chunk) }) { continue }
            chosen.append(position)
            perMeeting[chunk.meetingID, default: 0] += 1
        }
        if chosen.count < query.limit {
            for position in order where chosen.count < query.limit && !chosen.contains(position) {
                if chosen.contains(where: { overlaps(candidates[$0], candidates[position]) }) { continue }
                chosen.append(position)
            }
        }
        let hits = chosen.map { candidates[$0] }

        // 7. Facts blocks of the meetings the hits come from.
        var factMeetings: [UUID] = []
        for hit in hits where !factMeetings.contains(hit.meetingID) { factMeetings.append(hit.meetingID) }
        if factMeetings.isEmpty, let last = scoped.last { factMeetings = [last.id] }
        return VidurRagRetrieval(facts: factsBlocks(for: factMeetings, index: index), hits: hits, scopedMeetings: scoped,
                                 filters: filters, queryKeys: queryKeys)
    }

    // MARK: Helpers

    /// English and Hinglish "who said / who mentioned" questions.
    static func asksWhoSaid(_ question: String) -> Bool {
        let lower = question.lowercased()
        let cues = ["who said", "who mentioned", "who told", "who raised", "who talked about", "who spoke about",
                    "kisne kaha", "kisne bola", "kaun bola", "\u{0915}\u{093F}\u{0938}\u{0928}\u{0947} \u{0915}\u{0939}\u{093E}"]
        return cues.contains { lower.contains($0) }
    }

    private static func factsBlocks(for meetingIDs: [UUID], index: VidurRagIndex) -> [VidurRagChunk] {
        Array(meetingIDs.prefix(2).compactMap { index.facts(for: $0) })
    }

    /// A short follow-up ("and Neha?") borrows the words of the question before it.
    static func lexicalQuery(question: String, history: [VidurChatTurn]) -> String {
        guard let previous = history.last?.question else { return question }
        return VidurTokenizer.tokens(question).count <= 3 ? previous + " " + question : question
    }

    static func kinds(for intents: [VidurQuickIntent]) -> Set<VidurRagKind> {
        var kinds = Set<VidurRagKind>()
        for intent in intents {
            switch intent {
            case .tasks: kinds.insert(.action)
            case .decisions: kinds.insert(.decision)
            case .openIssues: kinds.insert(.openIssue)
            case .attendees, .absent: kinds.insert(.attendance)
            case .agenda: kinds.insert(.agenda)
            case .summary: kinds.formUnion([.summary, .discussion])
            case .nextMeeting: kinds.insert(.nextMeeting)
            case .duration, .date, .meetingList, .topic: break
            }
        }
        return kinds
    }

    private static func taskBonus(_ chunk: VidurRagChunk, filter: VidurQuickTaskFilter, dueRange: DateInterval?,
                                  now: Date) -> Double {
        let done = chunk.isCompleted ?? false
        var bonus = 0.0
        switch filter {
        case .all: break
        case .open: if !done { bonus += 1 }
        case .done: if done { bonus += 1 }
        case .overdue:
            if !done, let due = chunk.dueDate, due < now { bonus += 1.5 }
        case .due:
            if !done, let due = chunk.dueDate, let range = dueRange, range.contains(due) { bonus += 1.5 }
        }
        if let range = dueRange, !done, let due = chunk.dueDate, range.contains(due) { bonus += 0.5 }
        return bonus
    }

    /// Two transcript windows overlap when at least half of the shorter one repeats the other.
    static func overlaps(_ left: VidurRagChunk, _ right: VidurRagChunk) -> Bool {
        guard left.kind == .transcript, right.kind == .transcript, left.meetingID == right.meetingID else { return false }
        func keys(_ chunk: VidurRagChunk) -> Set<String> {
            Set(chunk.passages.map { "\($0.start)|\($0.text.prefix(24))" })
        }
        let shared = keys(left).intersection(keys(right)).count
        let shorter = min(left.passages.count, right.passages.count)
        return shared > 0 && shared * 2 >= shorter
    }
}
