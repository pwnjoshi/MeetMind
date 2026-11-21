import Foundation
import OfflineEngineKit

/// Detects discussion points that were left unresolved.
/// Pure and deterministic so the in-app Minutes tab, the exports and the tests agree.
public enum OpenIssueDetector {
    private static let phrases: [String] = [
        "not decided", "not yet decided", "yet to be decided", "undecided",
        "pending", "remains open", "remain open", "remains unresolved", "unresolved",
        "to be confirmed", "tbc", "to be determined", "tbd",
        "needs further discussion", "need further discussion", "needs more discussion",
        "open question", "open issue", "to be revisited", "will be revisited"
    ]

    private static let negations: [String] = [
        "no pending", "nothing pending", "none pending", "not pending",
        "no open", "no unresolved", "nothing unresolved"
    ]

    /// True when `text` says something is still undecided, pending or open.
    public static func isOpenIssue(_ text: String) -> Bool {
        let lowered = text.lowercased()
        for negation in negations where lowered.contains(negation) { return false }
        for phrase in phrases where containsWholePhrase(lowered, phrase: phrase) { return true }
        return false
    }

    /// Splits discussion points into resolved discussion and open issues, keeping the original order.
    public static func partition(_ points: [String]) -> (discussion: [String], openIssues: [String]) {
        var discussion: [String] = []
        var open: [String] = []
        for point in points {
            if isOpenIssue(point) { open.append(point) } else { discussion.append(point) }
        }
        return (discussion, open)
    }

    /// Reads an `openIssues` list from stored analysis JSON without depending on the analysis types.
    /// Looks at the top level and at every element of an `analysis` array. Items may be strings or objects with `text`.
    /// Returns nil when no `openIssues` key exists anywhere, so callers can fall back to `partition`.
    public static func explicitOpenIssues(from data: Data?) -> [String]? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let root = object as? [String: Any] else { return nil }
        var keyFound = false
        var found: [String] = []

        func collect(from container: [String: Any]) {
            guard let value = container["openIssues"] else { return }
            keyFound = true
            guard let items = value as? [Any] else { return }
            for item in items {
                if let text = item as? String {
                    found.append(text)
                } else if let entry = item as? [String: Any], let text = entry["text"] as? String {
                    found.append(text)
                }
            }
        }

        collect(from: root)
        if let chunks = root["analysis"] as? [Any] {
            for chunk in chunks {
                if let dictionary = chunk as? [String: Any] { collect(from: dictionary) }
            }
        }
        guard keyFound else { return nil }
        return uniqueTrimmed(found)
    }

    static func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { continue }
            if seen.insert(cleaned.lowercased()).inserted { result.append(cleaned) }
        }
        return result
    }

    /// Matches `phrase` only when it is not part of a longer word ("depending" must not match "pending").
    private static func containsWholePhrase(_ haystack: String, phrase: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: phrase, options: [], range: searchRange) {
            var startsClean = true
            if found.lowerBound > haystack.startIndex {
                startsClean = !haystack[haystack.index(before: found.lowerBound)].isLetter
            }
            var endsClean = true
            if found.upperBound < haystack.endIndex {
                endsClean = !haystack[found.upperBound].isLetter
            }
            if startsClean && endsClean { return true }
            searchRange = found.upperBound..<haystack.endIndex
        }
        return false
    }
}

/// One categorized, read-only view of a meeting record.
/// The Minutes tab, the Actions and Decisions tabs, the exports and the Minutes Studio all build from this
/// type, and it is always derived from the live models, so it cannot drift from the data.
public struct MeetingMinutesContent: Equatable, Sendable {
    public struct Person: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let label: String
        public let colorHex: String
        public let initials: String
    }

    public struct Decision: Equatable, Identifiable, Sendable {
        /// Position in `Summary.keyDecisions`; the decided-by metadata is keyed by it.
        public let index: Int
        public let text: String
        public let decidedBy: String?
        public var id: Int { index }
    }

    public struct ActionLine: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let owner: String?
        public let due: Date?
        public let dueText: String?
        public let priorityName: String
        public let isCompleted: Bool

        public var ownerName: String { owner ?? "Unassigned" }
        public var statusText: String { isCompleted ? "Done" : "Open" }
    }

    public struct Suggestion: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let owner: String?
        public let category: String
        public let deadlineText: String?
    }

    public var summary: String
    public var agenda: [String]
    /// False until attendance was edited at least once; exports then say "Attendees" instead of "Present".
    public var hasAttendanceRecord: Bool
    public var present: [Person]
    public var absent: [Person]
    public var discussion: [String]
    public var openIssues: [String]
    public var decisions: [Decision]
    public var actions: [ActionLine]
    public var suggestions: [Suggestion]

    public var hasMinutes: Bool { !summary.isEmpty || !discussion.isEmpty || !decisions.isEmpty }

    public static func make(from meeting: Meeting, record: MeetingRecordData) -> MeetingMinutesContent {
        let summary = meeting.summary
        let points = clean(summary?.keyPoints ?? [])
        let overview = (summary?.executiveSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Older minutes stored the discussion joined into the summary; show it once.
        let overviewRepeatsPoints = !points.isEmpty && overview == points.joined(separator: "\n")
        let summaryText = overviewRepeatsPoints ? "" : overview

        var discussion = points
        var openIssues: [String] = []
        if let explicit = OpenIssueDetector.explicitOpenIssues(from: meeting.offlineAnalysisData) {
            openIssues = explicit
            let explicitKeys = Set(explicit.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) })
            discussion = points.filter {
                !explicitKeys.contains($0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
            }
        } else {
            let split = OpenIssueDetector.partition(points)
            discussion = split.discussion
            openIssues = split.openIssues
        }

        let agenda = (meeting.agendaText ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        var present: [Person] = []
        var absent: [Person] = []
        for speaker in meeting.namedAttendees {
            let person = Person(id: speaker.id, name: speaker.name, label: speaker.displayLabel,
                                colorHex: speaker.avatarColorHex, initials: speaker.initials)
            if absentIDs.contains(speaker.id) { absent.append(person) } else { present.append(person) }
        }

        var decisions: [Decision] = []
        let storedDecisions = summary?.keyDecisions ?? []
        for (index, raw) in storedDecisions.enumerated() {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            var name: String?
            if let deciderID = record.decider(at: index) {
                name = meeting.participants.first(where: { $0.id == deciderID })?.name
            }
            decisions.append(Decision(index: index, text: text, decidedBy: name))
        }

        var actions: [ActionLine] = []
        for item in meeting.actionItems {
            let line = ActionLine(
                id: item.id,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                owner: item.assignee?.name,
                due: item.dueDate,
                dueText: item.formattedDueDate,
                priorityName: item.priorityDisplayName,
                isCompleted: item.isCompleted
            )
            actions.append(line)
        }

        var suggestions: [Suggestion] = []
        for pending in meeting.pendingTaskSuggestions {
            let owner = pending.task.owner?.trimmingCharacters(in: .whitespacesAndNewlines)
            suggestions.append(Suggestion(
                id: pending.id,
                title: pending.task.title,
                owner: (owner?.isEmpty ?? true) ? nil : owner,
                category: pending.task.category,
                deadlineText: pending.task.deadlineText
            ))
        }

        return MeetingMinutesContent(
            summary: summaryText,
            agenda: agenda,
            hasAttendanceRecord: meeting.absentParticipantIDs != nil,
            present: present,
            absent: absent,
            discussion: discussion,
            openIssues: openIssues,
            decisions: decisions,
            actions: actions,
            suggestions: suggestions
        )
    }

    /// "Decision text (Decided by Name)" for exports and plain text.
    public func decisionLine(_ decision: Decision) -> String {
        guard let name = decision.decidedBy else { return decision.text }
        return "\(decision.text) (Decided by \(name))"
    }

    private static func clean(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
