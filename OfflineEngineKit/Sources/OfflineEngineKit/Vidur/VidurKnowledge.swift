import Foundation

// MARK: - Input: a Sendable snapshot of one meeting's saved data

/// One transcript turn or typed note.
public struct VidurMeetingTurn: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let speaker: String?

    public init(text: String, start: TimeInterval, speaker: String? = nil) {
        self.text = text
        self.start = start
        self.speaker = speaker
    }
}

/// A decision or open issue from the saved minutes.
public struct VidurMeetingLine: Sendable, Equatable {
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

public struct VidurMeetingTask: Sendable, Equatable {
    public let title: String
    public let owner: String?
    public let dueDate: Date?
    public let dueText: String?
    public let isCompleted: Bool
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

/// Everything Vidur knows about one meeting: minutes, tasks and transcript.
public struct VidurMeetingRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let date: Date
    public let duration: TimeInterval
    public let attendees: [String]
    public let absent: [String]
    /// False when nobody confirmed attendance, so an empty `absent` list means "unknown".
    public let attendanceRecorded: Bool
    public let agenda: [String]
    public let summary: String
    public let discussion: [String]
    public let decisions: [VidurMeetingLine]
    public let openIssues: [VidurMeetingLine]
    public let tasks: [VidurMeetingTask]
    public let turns: [VidurMeetingTurn]
    /// "Next meeting" text from the minutes, when the user wrote one.
    public let nextMeetingText: String?
    /// The series this meeting belongs to (for example a weekly sync), when it has one.
    public let seriesTitle: String?

    public init(id: UUID = UUID(), title: String, date: Date, duration: TimeInterval = 0,
                attendees: [String] = [], absent: [String] = [], attendanceRecorded: Bool = false,
                agenda: [String] = [], summary: String = "", discussion: [String] = [],
                decisions: [VidurMeetingLine] = [], openIssues: [VidurMeetingLine] = [],
                tasks: [VidurMeetingTask] = [], turns: [VidurMeetingTurn] = [], nextMeetingText: String? = nil,
                seriesTitle: String? = nil) {
        self.id = id
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
        self.turns = turns
        self.nextMeetingText = nextMeetingText
        self.seriesTitle = seriesTitle
    }

    /// True when there is anything to answer from.
    var hasContent: Bool {
        !summary.isEmpty || !turns.isEmpty || !tasks.isEmpty || !decisions.isEmpty || !openIssues.isEmpty
            || !discussion.isEmpty || !attendees.isEmpty || !agenda.isEmpty
    }
}

// MARK: - Output

public enum VidurQuickIntent: String, Sendable, Equatable {
    case tasks, decisions, openIssues, attendees, absent, agenda, summary, nextMeeting, duration, date
    case meetingList, topic
}

public enum VidurQuickConfidence: Sendable, Equatable {
    /// The saved data answers the question. No model is needed.
    case complete
    /// Real evidence was found but it may not answer the whole question.
    case partial
    /// Nothing usable was found. A deeper search may still help.
    case notFound
}

/// Where a part of the answer came from: a minutes item or a transcript turn.
public struct VidurQuickSource: Sendable, Equatable {
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date
    /// "Decision", "Action", "Open issue", "Summary" and so on. Nil for a transcript turn.
    public let label: String?
    public let timestamp: TimeInterval?
    public let quote: String
    public let speaker: String?

    public init(meetingID: UUID, meetingTitle: String, meetingDate: Date, label: String?,
                timestamp: TimeInterval?, quote: String, speaker: String?) {
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.label = label
        self.timestamp = timestamp
        self.quote = quote
        self.speaker = speaker
    }
}

public struct VidurQuickTask: Sendable, Equatable {
    public let title: String
    public let owner: String?
    public let dueDate: Date?
    public let dueText: String?
    public let isCompleted: Bool
    public let meetingID: UUID
    public let meetingTitle: String
}

public struct VidurQuickAnswer: Sendable, Equatable {
    public let text: String
    public let sources: [VidurQuickSource]
    /// People the answer is about, for the avatar row.
    public let people: [String]
    /// Tasks behind the answer, for the "Related actions" list.
    public let tasks: [VidurQuickTask]
    public let confidence: VidurQuickConfidence
    public let intent: VidurQuickIntent
    /// Questions to offer when nothing was found.
    public let suggestions: [String]
    public let meetingTitles: [String]
    /// True for "why" and "how" questions that a model can explain better than a lookup.
    public let wantsReasoning: Bool
}
