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
    /// Name of the series this meeting belongs to, when it has one.
    public let seriesName: String?

    public init(meetingID: UUID, title: String, date: Date, duration: TimeInterval = 0,
                attendees: [String] = [], absent: [String] = [], attendanceRecorded: Bool = false,
                agenda: [String] = [], summary: String = "", discussion: [String] = [],
                decisions: [VidurFactLine] = [], openIssues: [VidurFactLine] = [], tasks: [VidurTaskFact] = [],
                seriesName: String? = nil) {
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
        self.seriesName = seriesName
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
            decisions: decisions, openIssues: issues, tasks: tasks,
            seriesName: meeting.seriesName)
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

// MARK: - Duration wording

public enum VidurStructuredAnswerer {
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return secs > 0 && hours == 0 ? "\(minutes) min \(secs) s" : "\(minutes) min" }
        return "\(secs) s"
    }
}
