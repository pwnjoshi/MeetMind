import Foundation

// MARK: - Snapshots

public struct SeriesActionSnapshot: Equatable, Sendable {
    public var title: String
    public var owner: String?
    public var isCompleted: Bool

    public init(title: String, owner: String? = nil, isCompleted: Bool) {
        self.title = title
        self.owner = owner
        self.isCompleted = isCompleted
    }
}

/// Plain copy of the saved data of one meeting that the series comparison needs.
public struct SeriesMeetingSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var date: Date
    public var decisions: [String]
    public var actions: [SeriesActionSnapshot]
    public var agenda: [String]
    /// Everyone on the participant list.
    public var attendees: [String]
    /// Participants marked absent for this meeting.
    public var absent: [String]

    public init(id: UUID, title: String, date: Date, decisions: [String] = [],
                actions: [SeriesActionSnapshot] = [], agenda: [String] = [],
                attendees: [String] = [], absent: [String] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.decisions = decisions
        self.actions = actions
        self.agenda = agenda
        self.attendees = attendees
        self.absent = absent
    }

    @MainActor
    public static func make(from meeting: Meeting) -> SeriesMeetingSnapshot {
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        let names = meeting.participants.map { $0.name }
        let absentNames = meeting.participants.filter { absentIDs.contains($0.id) }.map { $0.name }
        let actions = meeting.actionItems.map {
            SeriesActionSnapshot(title: $0.title, owner: $0.assignee?.name, isCompleted: $0.isCompleted)
        }
        return SeriesMeetingSnapshot(
            id: meeting.id, title: meeting.title, date: meeting.createdAt,
            decisions: meeting.summary?.keyDecisions ?? [],
            actions: actions,
            agenda: SeriesDiffEngine.agendaItems(from: meeting.agendaText),
            attendees: names, absent: absentNames)
    }
}

// MARK: - Result

/// One diff line plus the meeting it is taken from.
public struct SeriesDiffEntry: Equatable, Sendable, Identifiable {
    public let text: String
    public let detail: String?
    public let meetingID: UUID
    public let meetingTitle: String
    public let meetingDate: Date

    public var id: String { "\(meetingID.uuidString)|\(text)" }

    public init(text: String, detail: String? = nil, meetingID: UUID, meetingTitle: String, meetingDate: Date) {
        self.text = text
        self.detail = detail
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
    }
}

public struct SeriesDiff: Equatable, Sendable {
    public let earlier: SeriesMeetingSnapshot
    public let later: SeriesMeetingSnapshot

    /// In the later meeting only.
    public var decisionsNew: [SeriesDiffEntry] = []
    /// In the earlier meeting only (not repeated later).
    public var decisionsNotRepeated: [SeriesDiffEntry] = []
    public var actionsNew: [SeriesDiffEntry] = []
    /// Open earlier, completed in the later meeting.
    public var actionsClosed: [SeriesDiffEntry] = []
    /// Open in both meetings.
    public var actionsCarried: [SeriesDiffEntry] = []
    /// Open earlier and absent from the later meeting's saved items.
    public var actionsNotListed: [SeriesDiffEntry] = []
    public var agendaAdded: [SeriesDiffEntry] = []
    public var agendaRemoved: [SeriesDiffEntry] = []
    public var attendeesJoined: [SeriesDiffEntry] = []
    public var attendeesLeft: [SeriesDiffEntry] = []

    public init(earlier: SeriesMeetingSnapshot, later: SeriesMeetingSnapshot) {
        self.earlier = earlier
        self.later = later
    }

    public var decisionChangeCount: Int { decisionsNew.count + decisionsNotRepeated.count }
    public var actionChangeCount: Int { actionsNew.count + actionsClosed.count + actionsNotListed.count }
    public var agendaChangeCount: Int { agendaAdded.count + agendaRemoved.count }
    public var attendanceChangeCount: Int { attendeesJoined.count + attendeesLeft.count }

    public var changedCount: Int {
        decisionChangeCount + actionChangeCount + agendaChangeCount + attendanceChangeCount
    }
    public var stillOpenCount: Int { actionsCarried.count }
}

// MARK: - Engine

public enum SeriesDiffEngine {
    /// Lowercased, punctuation-free, single-spaced key used to match the same item across meetings.
    public static func normalize(_ text: String) -> String {
        let mapped = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Splits agenda text into items, removing list markers such as "-", bullets and "1.".
    public static func agendaItems(from text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { line -> String? in
            var value = line.trimmingCharacters(in: .whitespaces)
            while let first = value.first, "-\u{2022}*\u{2013}\u{2014}".contains(first) {
                value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            var digits = 0
            for character in value {
                if character.isNumber { digits += 1 } else { break }
            }
            if digits > 0, digits < value.count {
                let marker = value[value.index(value.startIndex, offsetBy: digits)]
                if marker == "." || marker == ")" {
                    value = String(value.dropFirst(digits + 1)).trimmingCharacters(in: .whitespaces)
                }
            }
            return value.isEmpty ? nil : value
        }
    }

    /// Meetings of one series ordered oldest first, then compared. Order of arguments does not matter.
    public static func compare(_ first: SeriesMeetingSnapshot, _ second: SeriesMeetingSnapshot) -> SeriesDiff {
        let earlier = first.date <= second.date ? first : second
        let later = first.date <= second.date ? second : first
        var diff = SeriesDiff(earlier: earlier, later: later)

        func entry(_ text: String, _ detail: String? = nil, from meeting: SeriesMeetingSnapshot) -> SeriesDiffEntry {
            SeriesDiffEntry(text: text, detail: detail, meetingID: meeting.id,
                            meetingTitle: meeting.title, meetingDate: meeting.date)
        }

        // Decisions
        let earlierDecisions = unique(earlier.decisions)
        let laterDecisions = unique(later.decisions)
        let earlierDecisionKeys = Set(earlierDecisions.map { $0.key })
        let laterDecisionKeys = Set(laterDecisions.map { $0.key })
        diff.decisionsNew = laterDecisions.filter { !earlierDecisionKeys.contains($0.key) }
            .map { entry($0.text, from: later) }
        diff.decisionsNotRepeated = earlierDecisions.filter { !laterDecisionKeys.contains($0.key) }
            .map { entry($0.text, from: earlier) }

        // Action items
        let earlierActions = uniqueActions(earlier.actions)
        let laterActions = uniqueActions(later.actions)
        var earlierByKey: [String: SeriesActionSnapshot] = [:]
        for item in earlierActions { earlierByKey[item.key] = item.action }
        var laterByKey: [String: SeriesActionSnapshot] = [:]
        for item in laterActions { laterByKey[item.key] = item.action }

        for item in laterActions {
            let detail = item.action.owner.map { "Owner: \($0)" }
            if let before = earlierByKey[item.key] {
                if !before.isCompleted && item.action.isCompleted {
                    diff.actionsClosed.append(entry(item.action.title, detail, from: later))
                } else if !before.isCompleted && !item.action.isCompleted {
                    diff.actionsCarried.append(entry(item.action.title, detail, from: later))
                }
            } else {
                diff.actionsNew.append(entry(item.action.title, detail, from: later))
            }
        }
        for item in earlierActions where !item.action.isCompleted && laterByKey[item.key] == nil {
            let detail = item.action.owner.map { "Owner: \($0)" }
            diff.actionsNotListed.append(entry(item.action.title, detail, from: earlier))
        }

        // Agenda
        let earlierAgenda = unique(earlier.agenda)
        let laterAgenda = unique(later.agenda)
        let earlierAgendaKeys = Set(earlierAgenda.map { $0.key })
        let laterAgendaKeys = Set(laterAgenda.map { $0.key })
        diff.agendaAdded = laterAgenda.filter { !earlierAgendaKeys.contains($0.key) }.map { entry($0.text, from: later) }
        diff.agendaRemoved = earlierAgenda.filter { !laterAgendaKeys.contains($0.key) }.map { entry($0.text, from: earlier) }

        // Attendance: present = participants who were not marked absent
        let earlierPresent = present(earlier)
        let laterPresent = present(later)
        let earlierPresentKeys = Set(earlierPresent.map { $0.key })
        let laterPresentKeys = Set(laterPresent.map { $0.key })
        diff.attendeesJoined = laterPresent.filter { !earlierPresentKeys.contains($0.key) }
            .map { entry($0.text, from: later) }
        diff.attendeesLeft = earlierPresent.filter { !laterPresentKeys.contains($0.key) }
            .map { entry($0.text, from: earlier) }
        return diff
    }

    private static func present(_ meeting: SeriesMeetingSnapshot) -> [(key: String, text: String)] {
        let absentKeys = Set(meeting.absent.map { normalize($0) })
        return unique(meeting.attendees).filter { !absentKeys.contains($0.key) }
    }

    private static func unique(_ items: [String]) -> [(key: String, text: String)] {
        var seen = Set<String>()
        var result: [(key: String, text: String)] = []
        for item in items {
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append((key: key, text: text))
        }
        return result
    }

    private static func uniqueActions(_ items: [SeriesActionSnapshot]) -> [(key: String, action: SeriesActionSnapshot)] {
        var seen = Set<String>()
        var result: [(key: String, action: SeriesActionSnapshot)] = []
        for item in items {
            let key = normalize(item.title)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            var action = item
            action.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append((key: key, action: action))
        }
        return result
    }
}
