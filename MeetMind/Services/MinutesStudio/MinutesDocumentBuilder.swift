import Foundation

// MARK: - Input snapshot

struct MinutesParticipant: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let role: String?
}

struct MinutesActionLine: Equatable, Sendable {
    let title: String
    let owner: String?
    let due: Date?
    var isCompleted: Bool = false
}

/// Plain-value copy of the meeting content used to build the document.
struct MinutesMeetingSnapshot: Equatable, Sendable {
    var meetingID: UUID
    var title: String
    var date: Date
    var agenda: String?
    var participants: [MinutesParticipant]
    var defaultAbsentIDs: [UUID]
    var discussion: [String]
    var decisions: [String]
    var actionItems: [MinutesActionLine]
    var isFinalized: Bool
    /// Executive summary text; empty when the minutes have none (or repeat the discussion).
    var summary: String = ""
    /// Unresolved discussion points, derived by `MeetingMinutesContent`.
    var openIssues: [String] = []
    /// Decided-by names, parallel to `decisions`.
    var decisionDeciders: [String?] = []

    @MainActor
    static func make(from meeting: Meeting) -> MinutesMeetingSnapshot {
        let participants = meeting.participants.map {
            MinutesParticipant(
                id: $0.id,
                name: $0.name,
                role: $0.role?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? $0.role : nil
            )
        }
        let content = MeetingMinutesContent.make(from: meeting, record: MeetingRecordStore.shared.record(for: meeting.id))
        let actions = content.actions.map {
            MinutesActionLine(title: $0.title, owner: $0.owner, due: $0.due, isCompleted: $0.isCompleted)
        }
        let summary = meeting.summary
        return MinutesMeetingSnapshot(
            meetingID: meeting.id,
            title: meeting.title,
            date: meeting.scheduledStartTime ?? meeting.createdAt,
            agenda: meeting.agendaText,
            participants: participants,
            defaultAbsentIDs: meeting.absentParticipantIDs ?? [],
            discussion: content.discussion,
            decisions: content.decisions.map(\.text),
            actionItems: actions,
            isFinalized: summary != nil && meeting.minutesNeedFinalization != true,
            summary: content.summary,
            openIssues: content.openIssues,
            decisionDeciders: content.decisions.map(\.decidedBy)
        )
    }
}

// MARK: - Output document

struct MinutesDocument: Equatable, Sendable {
    enum BlockStyle: Sendable {
        case heading
        case caption
    }

    struct Block: Equatable, Identifiable, Sendable {
        let id: String
        var heading: String
        var lines: [String]
        var style: BlockStyle
    }

    var headerLines: [String]
    var headerCentered: Bool
    var statusLabel: String
    var setupLine: String
    var heading: String
    var title: String
    var dateLine: String
    var typeLine: String
    var blocks: [Block]
}

// MARK: - Builder

enum MinutesDocumentBuilder {
    static func status(for participantID: UUID, config: MinutesStudioConfig, defaultAbsentIDs: [UUID]) -> MinutesAttendanceStatus {
        if let stored = config.attendance[participantID.uuidString] { return stored }
        return defaultAbsentIDs.contains(participantID) ? .absent : .unconfirmed
    }

    static func confirmedCount(snapshot: MinutesMeetingSnapshot, config: MinutesStudioConfig) -> Int {
        snapshot.participants.filter {
            status(for: $0.id, config: config, defaultAbsentIDs: snapshot.defaultAbsentIDs).isConfirmed
        }.count
    }

    /// IDs that should be written to `Meeting.absentParticipantIDs` for the given config.
    static func absentIDs(snapshot: MinutesMeetingSnapshot, config: MinutesStudioConfig) -> [UUID] {
        snapshot.participants.compactMap {
            status(for: $0.id, config: config, defaultAbsentIDs: snapshot.defaultAbsentIDs).isAbsence ? $0.id : nil
        }
    }

    static func headerLines(config: MinutesStudioConfig) -> [String] {
        guard let builtIn = MinutesBuiltInLetterhead(rawValue: config.letterheadID), builtIn != .plain else { return [] }
        let name = config.organisationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = config.organisationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !name.isEmpty { lines.append(name) }
        if builtIn == .company, !address.isEmpty { lines.append(address) }
        return lines
    }

    static func dateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy · h:mm a"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func build(
        snapshot: MinutesMeetingSnapshot,
        config: MinutesStudioConfig,
        templateName: String,
        documentHeading: String
    ) -> MinutesDocument {
        var blocks: [MinutesDocument.Block] = []

        let overview = snapshot.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overview.isEmpty {
            blocks.append(.init(id: "summary", heading: "Summary", lines: [overview], style: .heading))
        }

        let agenda = (snapshot.agenda ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !agenda.isEmpty {
            let agendaLines = agenda.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            blocks.append(.init(id: "agenda", heading: "Agenda", lines: agendaLines, style: .heading))
        }

        for section in config.orderedEnabledSections where section != .participantNames {
            if let block = block(for: section, snapshot: snapshot, config: config) {
                blocks.append(block)
            }
            if section == .discussion {
                let issues = snapshot.openIssues.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !issues.isEmpty {
                    blocks.append(.init(id: "openIssues", heading: "Open issues", lines: issues, style: .heading))
                }
            }
        }

        return MinutesDocument(
            headerLines: headerLines(config: config),
            headerCentered: MinutesBuiltInLetterhead(rawValue: config.letterheadID)?.isCentered ?? false,
            statusLabel: snapshot.isFinalized ? "Finalized" : "Draft",
            setupLine: "\(templateName) · \(config.format.title)",
            heading: documentHeading,
            title: snapshot.title,
            dateLine: dateLine(snapshot.date),
            typeLine: config.meetingType.title,
            blocks: blocks
        )
    }

    private static func block(
        for section: MinutesSection,
        snapshot: MinutesMeetingSnapshot,
        config: MinutesStudioConfig
    ) -> MinutesDocument.Block? {
        let showNames = config.isEnabled(.participantNames)
        let brief = config.format == .briefNote
        let numbered = config.format == .officeActionRecord

        func statusFor(_ person: MinutesParticipant) -> MinutesAttendanceStatus {
            status(for: person.id, config: config, defaultAbsentIDs: snapshot.defaultAbsentIDs)
        }

        switch section {
        case .attendance:
            let present = snapshot.participants.filter { statusFor($0).isPresent }
            let lines: [String]
            if present.isEmpty {
                lines = ["No attendance confirmed."]
            } else if !showNames {
                lines = ["\(present.count) present"]
            } else if brief {
                lines = [present.map(\.name).joined(separator: ", ")]
            } else {
                lines = present.map { "\($0.name) · \(statusFor($0).documentLabel)" }
            }
            return .init(id: "attendance", heading: "Present", lines: lines, style: .caption)

        case .absences:
            let absent = snapshot.participants.filter { statusFor($0).isAbsence }
            let lines: [String]
            if absent.isEmpty {
                lines = ["No confirmed absences or leave recorded."]
            } else if !showNames {
                lines = ["\(absent.count) absent or on leave"]
            } else {
                lines = absent.map { "\($0.name) · \(statusFor($0).documentLabel)" }
            }
            return .init(id: "absences", heading: "Absences and leave", lines: lines, style: .caption)

        case .previousMinutes:
            return .init(
                id: "previousMinutes",
                heading: "Previous minutes",
                lines: ["Minutes of the previous meeting were taken up for confirmation."],
                style: .heading
            )

        case .discussion:
            var lines = snapshot.discussion.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if lines.isEmpty {
                // The Summary block already carries the text when only a summary exists.
                if !snapshot.summary.isEmpty { return nil }
                lines = ["No discussion summary recorded."]
            }
            if brief { lines = Array(lines.prefix(3)) }
            return .init(id: "discussion", heading: "Discussion summary", lines: lines, style: .heading)

        case .decisions:
            var lines: [String] = []
            for (index, text) in snapshot.decisions.enumerated() {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                var line = "\(lines.count + 1). \(text)"
                if snapshot.decisionDeciders.indices.contains(index), let name = snapshot.decisionDeciders[index] {
                    line += " (Decided by \(name))"
                }
                lines.append(line)
            }
            if lines.isEmpty { lines = ["No decisions recorded."] }
            return .init(id: "decisions", heading: "Decisions", lines: lines, style: .heading)

        case .actionItems:
            var lines: [String] = []
            for (index, item) in snapshot.actionItems.enumerated() {
                if numbered {
                    lines.append("\(index + 1). \(item.title)")
                    let owner = item.owner ?? "Unassigned"
                    let due = item.due.map(shortDate) ?? "No deadline"
                    let status = item.isCompleted ? " · Done" : ""
                    lines.append("Owner: \(owner) · Deadline: \(due)\(status)")
                } else {
                    var parts = [item.title]
                    if let owner = item.owner { parts.append(owner) }
                    if let due = item.due { parts.append("Due \(shortDate(due))") }
                    if item.isCompleted { parts.append("Done") }
                    lines.append(parts.joined(separator: " · "))
                }
            }
            if lines.isEmpty { lines = ["No action items recorded."] }
            return .init(
                id: "actionItems",
                heading: numbered ? "Directions" : "Action items",
                lines: lines,
                style: .heading
            )

        case .nextMeeting:
            return .init(id: "nextMeeting", heading: "Next meeting", lines: ["Date and venue to be confirmed."], style: .heading)

        case .signature:
            return .init(
                id: "signature",
                heading: "Signature",
                lines: ["Chairperson: ______________________", "Date: ______________________"],
                style: .heading
            )

        case .participantNames:
            return nil
        }
    }
}
