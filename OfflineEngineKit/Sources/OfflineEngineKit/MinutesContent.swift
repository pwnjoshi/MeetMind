import Foundation

// Document-grade minutes content (Minutes of Meeting). Every type is Codable with
// stable JSON keys and is stored in `MeetingAnalysisCheckpoint.minutes`. Older
// checkpoints simply have no `minutes` key and decode with `nil`.

/// Outcome of one agenda topic. JSON: {"kind":"resolved|deferred|open","text":"..."}.
/// For `resolved`, `text` is the resolution clause without the leading "That "
/// (render it under "RESOLVED THAT"). For `deferred` and `open`, `text` is a full sentence.
public struct MinutesOutcome: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case resolved, deferred, open }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
    public static func resolved(_ text: String) -> MinutesOutcome { MinutesOutcome(kind: .resolved, text: text) }
    public static func deferred(_ text: String) -> MinutesOutcome { MinutesOutcome(kind: .deferred, text: text) }
    public static func open(_ text: String) -> MinutesOutcome { MinutesOutcome(kind: .open, text: text) }
}

/// One agenda item with its rephrased English discussion and outcome.
/// JSON keys: title, discussion, outcome (optional), evidence, timestamp (seconds, optional), speaker (optional).
public struct MinutesTopic: Codable, Sendable {
    public let title: String
    public let discussion: [String]
    public let outcome: MinutesOutcome?
    public let evidence: [SourceEvidence]
    public let timestamp: Double?
    public let speaker: String?
    public init(title: String, discussion: [String], outcome: MinutesOutcome?, evidence: [SourceEvidence],
                timestamp: Double?, speaker: String?) {
        self.title = title; self.discussion = discussion; self.outcome = outcome
        self.evidence = evidence; self.timestamp = timestamp; self.speaker = speaker
    }
}

/// A decision written as a formal resolution ("That the launch be held on 20 November.").
/// `evidence` holds the original quotes. JSON keys: text, rationale, topic, evidence, timestamp, speaker.
public struct MinutesResolution: Codable, Sendable {
    public let text: String
    public let rationale: String?
    public let topic: String?
    public let evidence: [SourceEvidence]
    public let timestamp: Double?
    public let speaker: String?
    public init(text: String, rationale: String?, topic: String?, evidence: [SourceEvidence],
                timestamp: Double?, speaker: String?) {
        self.text = text; self.rationale = rationale; self.topic = topic
        self.evidence = evidence; self.timestamp = timestamp; self.speaker = speaker
    }
}

/// An action with context and a resolved owner. `deadlineText` is verbatim; `dueDate` is
/// "yyyy-MM-dd" when it could be resolved against the meeting date.
/// JSON keys: title, owner, deadlineText, dueDate, topic, evidence, timestamp, speaker.
public struct MinutesAction: Codable, Sendable {
    public let title: String
    public let owner: String?
    public let deadlineText: String?
    public let dueDate: String?
    public let topic: String?
    public let evidence: [SourceEvidence]
    public let timestamp: Double?
    public let speaker: String?
    public init(title: String, owner: String?, deadlineText: String?, dueDate: String?, topic: String?,
                evidence: [SourceEvidence], timestamp: Double?, speaker: String?) {
        self.title = title; self.owner = owner; self.deadlineText = deadlineText; self.dueDate = dueDate
        self.topic = topic; self.evidence = evidence; self.timestamp = timestamp; self.speaker = speaker
    }
}

/// A formal open issue ("Marketing budget — not yet decided; to be taken up at the next meeting.").
/// JSON keys: text, subject, topic, nextMeeting, evidence, timestamp, speaker.
public struct MinutesOpenIssue: Codable, Sendable {
    public let text: String
    public let subject: String
    public let topic: String?
    public let nextMeeting: Bool
    public let evidence: [SourceEvidence]
    public let timestamp: Double?
    public let speaker: String?
    public init(text: String, subject: String, topic: String?, nextMeeting: Bool, evidence: [SourceEvidence],
                timestamp: Double?, speaker: String?) {
        self.text = text; self.subject = subject; self.topic = topic; self.nextMeeting = nextMeeting
        self.evidence = evidence; self.timestamp = timestamp; self.speaker = speaker
    }
}

/// A person named in the conversation who is not yet an attendee. Never added automatically.
/// `reason` is one of "addressed", "introduced", "mentioned", "assigned".
/// JSON keys: name, reason, evidence.
public struct SuggestedAttendee: Codable, Sendable {
    public let name: String
    public let reason: String
    public let evidence: [SourceEvidence]
    public init(name: String, reason: String, evidence: [SourceEvidence]) {
        self.name = name; self.reason = reason; self.evidence = evidence
    }
}

/// "agli meeting" with a date or time. JSON keys: text, dateText, timeText, isoDate, evidence.
public struct MinutesNextMeeting: Codable, Sendable {
    public let text: String
    public let dateText: String?
    public let timeText: String?
    public let isoDate: String?
    public let evidence: [SourceEvidence]
    public init(text: String, dateText: String?, timeText: String?, isoDate: String?, evidence: [SourceEvidence]) {
        self.text = text; self.dateText = dateText; self.timeText = timeText
        self.isoDate = isoDate; self.evidence = evidence
    }
}

/// The MoM content model. JSON keys: executiveSummary, topics, resolutions, actions, openIssues,
/// suggestedAttendees, nextMeeting.
public struct MinutesSummaryStatement: Codable, Sendable {
    public let text: String
    public let evidence: [SourceEvidence]

    public init(text: String, evidence: [SourceEvidence]) {
        self.text = text
        self.evidence = evidence
    }
}

public struct MinutesContent: Codable, Sendable {
    public let summaryStatements: [MinutesSummaryStatement]
    public let executiveSummary: String
    public let topics: [MinutesTopic]
    public let resolutions: [MinutesResolution]
    public let actions: [MinutesAction]
    public let openIssues: [MinutesOpenIssue]
    public let suggestedAttendees: [SuggestedAttendee]
    public let nextMeeting: MinutesNextMeeting?
    /// Says how much of the minutes came from machine-translated Hindi. Absent when nothing was translated.
    public var languageNote: String? = nil

    public init(executiveSummary: String, topics: [MinutesTopic], resolutions: [MinutesResolution],
                actions: [MinutesAction], openIssues: [MinutesOpenIssue],
                suggestedAttendees: [SuggestedAttendee], nextMeeting: MinutesNextMeeting?,
                summaryStatements: [MinutesSummaryStatement] = []) {
        self.summaryStatements = summaryStatements
        self.executiveSummary = executiveSummary; self.topics = topics; self.resolutions = resolutions
        self.actions = actions; self.openIssues = openIssues
        self.suggestedAttendees = suggestedAttendees; self.nextMeeting = nextMeeting
    }

    public static let empty = MinutesContent(executiveSummary: "", topics: [], resolutions: [], actions: [],
                                             openIssues: [], suggestedAttendees: [], nextMeeting: nil)

    private enum CodingKeys: String, CodingKey {
        case executiveSummary, topics, resolutions, actions, openIssues, suggestedAttendees, nextMeeting, summaryStatements, languageNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryStatements = try container.decodeIfPresent([MinutesSummaryStatement].self, forKey: .summaryStatements) ?? []
        executiveSummary = try container.decodeIfPresent(String.self, forKey: .executiveSummary) ?? ""
        topics = try container.decodeIfPresent([MinutesTopic].self, forKey: .topics) ?? []
        resolutions = try container.decodeIfPresent([MinutesResolution].self, forKey: .resolutions) ?? []
        actions = try container.decodeIfPresent([MinutesAction].self, forKey: .actions) ?? []
        openIssues = try container.decodeIfPresent([MinutesOpenIssue].self, forKey: .openIssues) ?? []
        suggestedAttendees = try container.decodeIfPresent([SuggestedAttendee].self, forKey: .suggestedAttendees) ?? []
        nextMeeting = try container.decodeIfPresent(MinutesNextMeeting.self, forKey: .nextMeeting)
        languageNote = try container.decodeIfPresent(String.self, forKey: .languageNote)
    }

    /// Agenda text derived from topic titles, one per line.
    public var agendaText: String { topics.map(\.title).joined(separator: "\n") }
}
