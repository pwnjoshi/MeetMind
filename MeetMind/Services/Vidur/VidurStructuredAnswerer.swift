import Foundation
import SwiftData
import OfflineEngineKit

// MARK: - Facts (Sendable snapshot of one meeting's saved, structured data)

public struct VidurFactLine: Sendable, Equatable {
    public let text: String
    public let timestamp: TimeInterval?
    public let quote: String?
    public let speaker: String?

    public init(text: String, timestamp: TimeInterval? = nil, quote: String? = nil, speaker: String? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.quote = quote
        self.speaker = speaker
    }
}

public struct VidurTaskFact: Sendable, Equatable {
    public let title: String
    public let owner: String?
    public let dueDate: Date?
    public let dueText: String?
    public let isCompleted: Bool
    /// True for an AI-suggested task the user has not confirmed yet.
    public let isSuggestion: Bool
    public let timestamp: TimeInterval?
    public let quote: String?

    public init(title: String, owner: String? = nil, dueDate: Date? = nil, dueText: String? = nil,
                isCompleted: Bool = false, isSuggestion: Bool = false, timestamp: TimeInterval? = nil,
                quote: String? = nil) {
        self.title = title
        self.owner = owner
        self.dueDate = dueDate
        self.dueText = dueText
        self.isCompleted = isCompleted
        self.isSuggestion = isSuggestion
        self.timestamp = timestamp
        self.quote = quote
    }
}

public struct VidurMeetingFacts: Sendable, Equatable {
    public let meetingID: UUID
    public let title: String
    public let date: Date
    public let duration: TimeInterval
    public let attendees: [String]
    public let absent: [String]
    /// False when nobody has confirmed attendance, so an empty absent list means "unknown".
    public let attendanceRecorded: Bool
    public let agenda: [String]
    public let summary: String
    public let discussion: [String]
    public let decisions: [VidurFactLine]
    public let openIssues: [VidurFactLine]
    public let tasks: [VidurTaskFact]

    public init(meetingID: UUID, title: String, date: Date, duration: TimeInterval = 0,
                attendees: [String] = [], absent: [String] = [], attendanceRecorded: Bool = false,
                agenda: [String] = [], summary: String = "", discussion: [String] = [],
                decisions: [VidurFactLine] = [], openIssues: [VidurFactLine] = [], tasks: [VidurTaskFact] = []) {
        self.meetingID = meetingID
        self.title = title
        self.date = date
        self.duration = duration
        self.attendees = attendees
        self.absent = absent
        self.attendanceRecorded = attendanceRecorded
        self.agenda = agenda
        self.summary = summary
        self.discussion = discussion
        self.decisions = decisions
        self.openIssues = openIssues
        self.tasks = tasks
    }

    public var participantNames: [String] { attendees + absent }

    // MARK: Building

    @MainActor
    public static func make(from meeting: Meeting) -> VidurMeetingFacts {
        let source = VidurSourceMeeting.make(from: meeting)
        let checkpoint = meeting.offlineAnalysis
        let checkpointTurns: [String: AnalysisTurn] = {
            var map: [String: AnalysisTurn] = [:]
            for turn in checkpoint?.turns ?? [] where map[turn.id] == nil { map[turn.id] = turn }
            return map
        }()

        func checkpointTurn(_ id: String) -> AnalysisTurn? {
            checkpointTurns[id] ?? id.split(separator: ".").first.flatMap { checkpointTurns[String($0)] }
        }
        func line(_ point: SupportedPoint) -> VidurFactLine {
            let evidence = point.evidence.first
            let located = evidence.flatMap { locate(quote: $0.quote, in: source.turns) }
            let turn = evidence.flatMap { checkpointTurn($0.turnID) }
            return VidurFactLine(text: point.text, timestamp: located?.start ?? turn?.start,
                                 quote: evidence?.quote, speaker: located?.speaker ?? turn?.speaker)
        }
        func merged(_ points: [SupportedPoint], extra: [String]) -> [VidurFactLine] {
            var seen = Set<String>()
            var lines: [VidurFactLine] = []
            for candidate in points.map(line) + extra.map({ VidurFactLine(text: $0) }) {
                let key = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                lines.append(candidate)
            }
            return lines
        }

        let analysis = checkpoint?.analysis ?? []
        let decisions = merged(analysis.flatMap(\.decisions), extra: meeting.summary?.keyDecisions ?? [])
        let issues = merged(analysis.flatMap(\.openIssues), extra: [])

        var tasks: [VidurTaskFact] = meeting.actionItems.map { item in
            let parsed = parseEvidence(item.sourceEvidence)
            return VidurTaskFact(title: item.title, owner: item.assignee?.name, dueDate: item.dueDate,
                                 isCompleted: item.isCompleted, timestamp: parsed.timestamp, quote: parsed.quote)
        }
        for suggestion in meeting.pendingTaskSuggestions {
            let evidence = suggestion.task.evidence.first
            let located = evidence.flatMap { locate(quote: $0.quote, in: source.turns) }
            let turn = evidence.flatMap { checkpointTurn($0.turnID) }
            tasks.append(VidurTaskFact(title: suggestion.task.title, owner: suggestion.task.owner,
                                       dueText: suggestion.task.deadlineText, isSuggestion: true,
                                       timestamp: located?.start ?? turn?.start, quote: evidence?.quote))
        }

        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let people = meeting.participants
        let agenda = (meeting.agendaText ?? "").split(whereSeparator: \.isNewline)
            .map { cleanAgendaLine(String($0)) }.filter { !$0.isEmpty }

        return VidurMeetingFacts(
            meetingID: meeting.id, title: meeting.title, date: meeting.scheduledStartTime ?? meeting.createdAt,
            duration: meeting.duration,
            attendees: people.filter { !absentIDs.contains($0.id) }.map(\.name),
            absent: people.filter { absentIDs.contains($0.id) }.map(\.name),
            attendanceRecorded: meeting.absentParticipantIDs != nil,
            agenda: agenda, summary: meeting.summary?.executiveSummary ?? "",
            discussion: meeting.summary?.discussionLines ?? [],
            decisions: decisions, openIssues: issues, tasks: tasks)
    }

    /// Strips list markers such as "- ", a bullet, "1." or "2)" but keeps text like "2026 budget".
    public static func cleanAgendaLine(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        while let first = value.first, "-\u{2022}*\u{00B7}".contains(first) { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        let digits = value.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2 {
            let rest = value.dropFirst(digits.count)
            if let marker = rest.first, marker == "." || marker == ")" {
                value = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    /// First transcript turn that contains `quote`.
    public static func locate(quote: String, in turns: [VidurSourceTurn]) -> VidurSourceTurn? {
        guard !quote.isEmpty else { return nil }
        return turns.first { $0.text.contains(quote) }
    }

    /// Parses "[mm:ss] quote" or "[h:mm:ss] quote", the format `Meeting.reviewTask` stores.
    public static func parseEvidence(_ raw: String?) -> (timestamp: TimeInterval?, quote: String?) {
        guard let raw, let firstLine = raw.split(whereSeparator: \.isNewline).first else { return (nil, nil) }
        let first = String(firstLine).trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty else { return (nil, nil) }
        guard first.hasPrefix("["), let close = first.firstIndex(of: "]") else { return (nil, first) }
        let stamp = first[first.index(after: first.startIndex)..<close].split(separator: ":").compactMap { Double($0) }
        let quote = first[first.index(after: close)...].trimmingCharacters(in: .whitespaces)
        var seconds: TimeInterval?
        if stamp.count == 2 { seconds = stamp[0] * 60 + stamp[1] }
        else if stamp.count == 3 { seconds = stamp[0] * 3600 + stamp[1] * 60 + stamp[2] }
        return (seconds, quote.isEmpty ? nil : quote)
    }
}

// MARK: - Intent routing

public enum VidurIntent: String, Sendable, Equatable, CaseIterable {
    case tasks, decisions, openIssues, attendees, absent, agenda, summary, duration, date
}

public enum VidurTaskFilter: Sendable, Equatable { case all, open, done, due, overdue }

public struct VidurRoute: Sendable, Equatable {
    public var intents: [VidurIntent]
    public var people: [String]
    public var taskFilter: VidurTaskFilter
    /// Content words the intent keywords do not explain (for example "pricing" in
    /// "which actions are open for pricing"). Rows must match them to count as an answer.
    public var residual: [String]
}

/// English + Hinglish keyword routing. No model, runs in microseconds.
public enum VidurIntentRouter {
    static let taskWords: Set<String> = [
        "task", "tasks", "action", "actions", "todo", "todos", "assigned", "assign", "assignee", "owner", "owners",
        "responsible", "deliverable", "deliverables", "followup", "followups", "kaam", "kaams", "zimmedari",
        "jimmedari", "zimmedaari", "commit", "committed", "commitment", "commitments", "promise", "promised",
        "owns", "handle", "handling", "karega", "karegi", "karenge", "lega", "legi", "dega", "degi",
        "\u{0915}\u{093E}\u{092E}", "\u{0915}\u{093E}\u{0930}\u{094D}\u{092F}"
    ]
    static let dueWords: Set<String> = ["due", "deadline", "deadlines", "overdue", "samay", "tarikh"]
    static let agreeWords: Set<String> = ["agree", "agreed", "agreement", "agreements", "sahmat", "manzoor"]
    static let decisionWords: Set<String> = [
        "decide", "decided", "decision", "decisions", "finalize", "finalized", "finalised", "finalise", "conclude",
        "concluded", "resolution", "resolutions", "approved", "approve", "faisla", "faisle", "nirnay", "tay", "tai",
        "\u{092B}\u{0948}\u{0938}\u{0932}\u{093E}", "\u{092B}\u{0948}\u{0938}\u{0932}\u{0947}",
        "\u{0928}\u{093F}\u{0930}\u{094D}\u{0923}\u{092F}", "\u{0924}\u{092F}"
    ]
    static let issueWords: Set<String> = [
        "unresolved", "issue", "issues", "undecided", "unclear", "unanswered", "concern", "concerns", "risk",
        "risks", "blocker", "blockers", "blocked", "problem", "problems", "samasya", "dikkat",
        "\u{0938}\u{092E}\u{0938}\u{094D}\u{092F}\u{093E}"
    ]
    static let attendeeWords: Set<String> = [
        "attendees", "attendee", "attended", "attendance", "participants", "participant", "present", "joined",
        "hazir", "haazir", "upasthit", "aaya", "aaye", "aayi", "\u{0909}\u{092A}\u{0938}\u{094D}\u{0925}\u{093F}\u{0924}"
    ]
    static let absentWords: Set<String> = ["absent", "absentee", "absentees", "anupasthit", "missing", "\u{0905}\u{0928}\u{0941}\u{092A}\u{0938}\u{094D}\u{0925}\u{093F}\u{0924}"]
    static let agendaWords: Set<String> = ["agenda", "agendas", "\u{090F}\u{091C}\u{0947}\u{0902}\u{0921}\u{093E}"]
    static let summaryWords: Set<String> = [
        "summary", "summarize", "summarise", "recap", "overview", "tldr", "gist", "saransh", "highlights",
        "\u{0938}\u{093E}\u{0930}\u{093E}\u{0902}\u{0936}"
    ]
    static let durationWords: Set<String> = ["duration"]
    static let dateWords: Set<String> = ["date", "tarikh", "when"]
    static let openWords: Set<String> = ["open", "pending", "remaining", "incomplete", "outstanding", "unfinished", "baaki", "left"]
    static let doneWords: Set<String> = ["done", "completed", "finished", "closed", "complete"]
    static let personTaskVerbs: Set<String> = [
        "agree", "agreed", "commit", "committed", "promise", "promised", "handle", "own", "owns", "doing",
        "responsible", "deliver", "karega", "karegi", "karenge", "lega", "legi", "dega", "degi", "assigned"
    ]
    static let genericWords: Set<String> = [
        "meeting", "meetings", "call", "session", "discussed", "discuss", "talk", "talked", "everyone", "anyone",
        "people", "please", "tell", "show", "list", "give", "still", "next", "steps", "step", "everything",
        "item", "items", "point", "points", "whats", "mujhe", "batao", "bataiye", "dikhao", "sab", "sabhi",
        "was", "were", "who", "whom", "all", "kaun", "kaunsa", "kaunse", "last", "first", "today", "total",
        "long", "kitni", "der", "kitna", "kitne", "time", "lamba", "happened", "hua", "hui", "baat", "key", "main", "sum",
        "there", "came", "joined", "attend", "join", "missed", "going", "working", "taking", "follow", "gair", "nahi", "aaye",
        "hazir", "gaya", "chuka", "karna", "date", "day", "din", "was"
    ]

    public static func route(question rawQuestion: String, participantNames: [String]) -> VidurRoute {
        let question = (rawQuestion.lowercased() + " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'s ", with: " ")
            .replacingOccurrences(of: "'", with: "")
        let words = question.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let wordSet = Set(words)
        let padded = " " + words.joined(separator: " ") + " "
        func has(_ set: Set<String>) -> Bool { !wordSet.isDisjoint(with: set) }
        func phrase(_ list: [String]) -> Bool { list.contains { padded.contains(" \($0) ") } }

        // People named in the question (full name, or a first name of at least two letters).
        var people: [String] = []
        var nameTokens = Set<String>()
        for name in participantNames {
            let tokens = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            guard let first = tokens.first, !people.contains(name) else { continue }
            let fullMatch = tokens.count > 1 && padded.contains(" \(tokens.joined(separator: " ")) ")
            if fullMatch || (first.count >= 2 && wordSet.contains(first)) {
                people.append(name)
                nameTokens.formUnion(tokens)
            }
        }

        var isTask = has(taskWords) || has(dueWords)
            || phrase(["follow up", "to do", "kya karna", "kya karna hai", "kab tak", "by when", "who will", "who is going to", "who should", "kisko kya"])
        let personVerb = !people.isEmpty && (has(personTaskVerbs) || phrase(["working on", "taking on", "karna hai", "kya karega", "kya karegi"]))
        if personVerb { isTask = true }
        let agreeOnly = has(agreeWords) && !isTask

        let notPresent = phrase(["not present", "gair hazir"])
        let absentAsked = has(absentWords) || notPresent
            || phrase(["didnt attend", "did not attend", "didnt join", "did not join", "nahi aaya", "nahi aaye", "nahi aayi", "who missed"])
        let attendeesAsked = has(attendeeWords.subtracting(["present"])) || (wordSet.contains("present") && !notPresent)
            || phrase(["who was there", "who all", "who came", "who joined", "kaun kaun", "kaun aaya", "kaun tha", "kaun the", "who were", "who was in", "who is in"])
        let openIssuePhrase = (has(openWords) && has(["question", "questions", "issue", "issues", "points", "topics"]) && !isTask)
        let summaryAsked = has(summaryWords)
            || phrase(["what happened", "kya hua", "what was discussed", "what did we discuss", "what we discussed", "kya discuss hua", "key points", "main points", "kya baat hui", "sum up"])
        let durationAsked = has(durationWords) || phrase(["how long", "kitni der", "kitna time", "kitne der", "kitna lamba"])
        let dateAsked = phrase(["what date", "which date", "when was", "when did the meeting", "kab hui", "kab hua", "what day", "kis din", "kis date"])
            || (has(dateWords) && !isTask && wordSet.contains("meeting"))

        var intents: [VidurIntent] = []
        if isTask { intents.append(.tasks) }
        if has(decisionWords) || (agreeOnly && people.isEmpty) { intents.append(.decisions) }
        if has(issueWords) || openIssuePhrase { intents.append(.openIssues) }
        if absentAsked { intents.append(.absent) }
        if attendeesAsked { intents.append(.attendees) }
        if has(agendaWords) { intents.append(.agenda) }
        if summaryAsked { intents.append(.summary) }
        if durationAsked { intents.append(.duration) }
        if dateAsked { intents.append(.date) }

        var filter = VidurTaskFilter.all
        if wordSet.contains("overdue") { filter = .overdue }
        else if phrase(["not completed", "not done", "not finished", "not complete", "nahi hua", "nahi hui"]) { filter = .open }
        else if has(doneWords) || phrase(["ho gaya", "ho chuka", "complete ho"]) { filter = .done }
        else if has(openWords) { filter = .open }
        else if has(dueWords) || phrase(["kab tak", "by when"]) { filter = .due }

        var vocabulary = Set<String>()
        for set in [taskWords, dueWords, agreeWords, decisionWords, issueWords, attendeeWords, absentWords, agendaWords,
                    summaryWords, durationWords, dateWords, openWords, doneWords, personTaskVerbs, genericWords] {
            vocabulary.formUnion(set)
        }
        let residual = words.filter {
            $0.count > 2 && !VidurTokenizer.stopWords.contains($0) && !vocabulary.contains($0)
                && !nameTokens.contains($0) && !$0.allSatisfy(\.isNumber)
        }
        return VidurRoute(intents: intents, people: people, taskFilter: filter, residual: residual)
    }
}

// MARK: - Tier 0 answerer

public struct VidurStructuredResult: Sendable, Equatable {
    public let answer: VidurAnswer
    /// True when the saved data fully answers the question, so no model or search is needed.
    public let isComplete: Bool
    public let route: VidurRoute
}

public enum VidurStructuredAnswerer {
    private struct Section {
        var text: String
        var citations: [VidurCitation]
        var isComplete: Bool
    }

    private static let maximumRows = 8

    public static func answer(question: String, facts: VidurMeetingFacts, extraNames: [String] = [],
                              now: Date = Date(), calendar: Calendar = .current) -> VidurStructuredResult? {
        let names = Array(Set(facts.participantNames + facts.tasks.compactMap(\.owner) + extraNames))
            .sorted { $0.count > $1.count }
        let route = VidurIntentRouter.route(question: question, participantNames: names)
        guard !route.intents.isEmpty else { return nil }

        var sections: [Section] = []
        var allComplete = true
        for intent in route.intents {
            guard let section = render(intent, route: route, facts: facts, now: now, calendar: calendar) else {
                allComplete = false
                continue
            }
            sections.append(section)
            if !section.isComplete { allComplete = false }
        }
        guard !sections.isEmpty else { return nil }
        var citations: [VidurCitation] = []
        for citation in sections.flatMap(\.citations) where citations.count < 5 { citations.append(citation) }
        let answer = VidurAnswer(text: sections.map(\.text).joined(separator: "\n\n"), citations: citations,
                                 kind: .extractive, notice: nil)
        return VidurStructuredResult(answer: answer, isComplete: allComplete, route: route)
    }

    // MARK: Rendering

    private static func render(_ intent: VidurIntent, route: VidurRoute, facts: VidurMeetingFacts,
                               now: Date, calendar: Calendar) -> Section? {
        switch intent {
        case .tasks: return tasksSection(route: route, facts: facts, now: now)
        case .decisions: return linesSection(label: "decision", lines: facts.decisions, route: route, facts: facts)
        case .openIssues: return linesSection(label: "open issue", lines: facts.openIssues, route: route, facts: facts)
        case .attendees:
            guard !facts.attendees.isEmpty || !facts.absent.isEmpty else {
                return Section(text: "No attendees are saved for this meeting.", citations: [], isComplete: false)
            }
            guard route.residual.isEmpty else { return nil }
            var text = facts.attendees.isEmpty ? "No one is marked present."
                : "Present (\(facts.attendees.count)): \(facts.attendees.joined(separator: ", "))."
            if !facts.absent.isEmpty { text += "\nAbsent: \(facts.absent.joined(separator: ", "))." }
            return Section(text: text, citations: [], isComplete: true)
        case .absent:
            guard route.residual.isEmpty else { return nil }
            if !facts.absent.isEmpty {
                return Section(text: "Absent (\(facts.absent.count)): \(facts.absent.joined(separator: ", ")).",
                               citations: [], isComplete: true)
            }
            return facts.attendanceRecorded
                ? Section(text: "No one is marked absent.", citations: [], isComplete: true)
                : Section(text: "Attendance has not been confirmed for this meeting.", citations: [], isComplete: false)
        case .agenda:
            guard route.residual.isEmpty else { return nil }
            guard !facts.agenda.isEmpty else {
                return Section(text: "No agenda is saved for this meeting.", citations: [], isComplete: false)
            }
            return Section(text: "Agenda:\n" + facts.agenda.map { "\u{2022} \($0)" }.joined(separator: "\n"),
                           citations: [], isComplete: true)
        case .summary:
            guard route.residual.isEmpty else { return nil }
            let points = facts.discussion.filter { $0 != facts.summary }.prefix(4)
            var parts: [String] = []
            if !facts.summary.isEmpty { parts.append(facts.summary) }
            if !points.isEmpty { parts.append(points.map { "\u{2022} \($0)" }.joined(separator: "\n")) }
            guard !parts.isEmpty else {
                return Section(text: "No summary is saved for this meeting yet.", citations: [], isComplete: false)
            }
            return Section(text: parts.joined(separator: "\n"), citations: [], isComplete: true)
        case .duration:
            guard route.residual.isEmpty else { return nil }
            guard facts.duration > 0 else {
                return Section(text: "No recording length is saved for this meeting.", citations: [], isComplete: false)
            }
            return Section(text: "The recording ran \(durationText(facts.duration)).", citations: [], isComplete: true)
        case .date:
            guard route.residual.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            formatter.calendar = calendar
            return Section(text: "\(facts.title) was on \(formatter.string(from: facts.date)).", citations: [], isComplete: true)
        }
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return secs > 0 && hours == 0 ? "\(minutes) min \(secs) s" : "\(minutes) min" }
        return "\(secs) s"
    }

    private static func matches(_ text: String, residual: [String]) -> Bool {
        guard !residual.isEmpty else { return true }
        let wanted = Set(VidurTokenizer.tokens(residual.joined(separator: " ")))
        guard !wanted.isEmpty else { return true }
        return !wanted.isDisjoint(with: Set(VidurTokenizer.tokens(text)))
    }

    private static func ownerMatches(_ owner: String?, _ people: [String]) -> Bool {
        guard let owner = owner?.lowercased(), !owner.isEmpty else { return false }
        return people.contains { person in
            let lowered = person.lowercased()
            if owner.contains(lowered) || lowered.contains(owner) { return true }
            let first = lowered.split(separator: " ").first.map(String.init) ?? lowered
            return owner.split(separator: " ").contains { String($0) == first }
        }
    }

    private static func citation(facts: VidurMeetingFacts, timestamp: TimeInterval?, quote: String?,
                                 speaker: String?) -> VidurCitation? {
        guard let timestamp, let quote, !quote.isEmpty else { return nil }
        return VidurCitation(meetingID: facts.meetingID, meetingTitle: facts.title, timestamp: timestamp,
                             quote: quote, speaker: speaker)
    }

    private static func linesSection(label: String, lines: [VidurFactLine], route: VidurRoute,
                                     facts: VidurMeetingFacts) -> Section? {
        guard !lines.isEmpty else {
            return Section(text: "No \(label)s are saved in this meeting's minutes yet.", citations: [], isComplete: false)
        }
        var rows = lines
        if !route.people.isEmpty {
            let filtered = rows.filter { line in
                ownerMatches(line.speaker, route.people)
                    || route.people.contains { line.text.localizedCaseInsensitiveContains($0.split(separator: " ").first.map(String.init) ?? $0) }
            }
            rows = filtered
        }
        rows = rows.filter { matches($0.text + " " + ($0.quote ?? ""), residual: route.residual) }
        guard !rows.isEmpty else { return nil }
        let shown = rows.prefix(maximumRows)
        var text = rows.count == 1 ? "1 \(label) recorded:" : "\(rows.count) \(label)s recorded:"
        text += "\n" + shown.map { "\u{2022} \($0.text)" }.joined(separator: "\n")
        if rows.count > shown.count { text += "\n\u{2026}and \(rows.count - shown.count) more." }
        let citations = shown.compactMap {
            citation(facts: facts, timestamp: $0.timestamp, quote: $0.quote, speaker: $0.speaker)
        }
        return Section(text: text, citations: citations, isComplete: true)
    }

    private static func tasksSection(route: VidurRoute, facts: VidurMeetingFacts, now: Date) -> Section? {
        guard !facts.tasks.isEmpty else {
            return Section(text: "No tasks are saved for this meeting yet.", citations: [], isComplete: false)
        }
        var rows = facts.tasks
        if !route.people.isEmpty {
            rows = rows.filter { ownerMatches($0.owner, route.people) }
            guard !rows.isEmpty else {
                return Section(text: "No tasks assigned to \(route.people.joined(separator: " or ")) are saved for this meeting.",
                               citations: [], isComplete: false)
            }
        }
        switch route.taskFilter {
        case .all: break
        case .open: rows = rows.filter { !$0.isCompleted }
        case .done: rows = rows.filter { $0.isCompleted }
        case .due: rows = rows.filter { $0.dueDate != nil || $0.dueText != nil }
        case .overdue: rows = rows.filter { !$0.isCompleted && ($0.dueDate.map { $0 < now } ?? false) }
        }
        rows = rows.filter { matches($0.title + " " + ($0.owner ?? "") + " " + ($0.quote ?? ""), residual: route.residual) }
        guard !rows.isEmpty else {
            if route.residual.isEmpty {
                let word = route.taskFilter == .done ? "completed " : (route.taskFilter == .all ? "" : "matching ")
                return Section(text: "No \(word)tasks match in this meeting.", citations: [], isComplete: true)
            }
            return nil
        }
        if route.taskFilter == .due || route.taskFilter == .overdue {
            rows.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let shown = rows.prefix(maximumRows)
        let lines = shown.map { task -> String in
            var details: [String] = []
            if let owner = task.owner, !owner.isEmpty, route.people.isEmpty { details.append(owner) }
            else if task.owner == nil || task.owner?.isEmpty == true { details.append("no owner set") }
            if let due = task.dueDate { details.append("due \(formatter.string(from: due))") }
            else if let text = task.dueText, !text.isEmpty { details.append("due \(text)") }
            if task.isSuggestion { details.append("suggested, not confirmed yet") }
            let mark = task.isCompleted ? "\u{2713} " : "\u{2022} "
            return mark + task.title + (details.isEmpty ? "" : " (\(details.joined(separator: ", ")))")
        }
        let who = route.people.isEmpty ? "" : " for \(route.people.joined(separator: " and "))"
        let kind: String
        switch route.taskFilter {
        case .open: kind = "open task"
        case .done: kind = "completed task"
        case .due, .overdue: kind = route.taskFilter == .overdue ? "overdue task" : "task with a due date"
        case .all: kind = "task"
        }
        var text = "\(rows.count) \(kind)\(rows.count == 1 ? "" : "s")\(who):\n" + lines.joined(separator: "\n")
        if rows.count > shown.count { text += "\n\u{2026}and \(rows.count - shown.count) more." }
        let citations = shown.compactMap { citation(facts: facts, timestamp: $0.timestamp, quote: $0.quote, speaker: nil) }
        return Section(text: text, citations: citations, isComplete: true)
    }
}
