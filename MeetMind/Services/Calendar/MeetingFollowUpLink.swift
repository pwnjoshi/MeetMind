import Foundation

/// "Follows up on": links a scheduled meeting to an earlier recorded meeting.
///
/// The link is stored as a shared series (`Meeting.seriesID` / `seriesName`), so existing
/// series data, repeats and comparisons keep working. Nothing here touches the database;
/// callers save the context.
enum MeetingFollowUpLink {
    /// The series a meeting joins when it follows up on another meeting.
    struct Series: Equatable {
        let id: UUID
        let name: String
        /// True when the earlier meeting had no series yet and one was created for the pair.
        let isNew: Bool
    }

    /// Statuses that count as "recorded": the meeting has happened and has (or will have) minutes.
    static func isRecorded(_ meeting: Meeting) -> Bool {
        meeting.status == .completed || meeting.status == .processing || meeting.status == .archived
    }

    /// When a meeting took place (or is planned): scheduled start, else creation time.
    static func date(of meeting: Meeting) -> Date {
        meeting.scheduledStartTime ?? meeting.createdAt
    }

    /// Reuses the earlier meeting's series, or starts a new one named after the earlier meeting.
    static func series(joining previous: Meeting) -> Series {
        if let id = previous.seriesID {
            let existing = (previous.seriesName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Series(id: id, name: existing.isEmpty ? previous.title : existing, isNew: false)
        }
        return Series(id: UUID(), name: previous.title, isNew: true)
    }

    /// Gives the earlier meeting the series when it has none. Never overwrites an existing series.
    static func stamp(_ previous: Meeting, seriesID: UUID, name: String) {
        guard previous.seriesID == nil else { return }
        previous.seriesID = seriesID
        previous.seriesName = name
    }

    /// Writes the chosen series onto `meeting` (nil clears it) and stamps `previous` when it is new.
    static func apply(seriesID: UUID?, seriesName: String?, previous: Meeting?, to meeting: Meeting) {
        guard let seriesID else {
            meeting.seriesID = nil
            meeting.seriesName = nil
            return
        }
        let trimmed = (seriesName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? (previous?.title ?? meeting.title) : trimmed
        if let previous, previous.id != meeting.id {
            stamp(previous, seriesID: seriesID, name: name)
        }
        meeting.seriesID = seriesID
        meeting.seriesName = name
    }

    /// The latest recorded meeting of a series that took place before `cutoff`.
    static func previousRecorded(inSeries seriesID: UUID, before cutoff: Date? = nil, excluding id: UUID? = nil, in meetings: [Meeting]) -> Meeting? {
        let matches = meetings.filter { candidate in
            guard candidate.seriesID == seriesID, isRecorded(candidate), candidate.id != id else { return false }
            if let cutoff { return date(of: candidate) < cutoff }
            return true
        }
        return matches.max { date(of: $0) < date(of: $1) }
    }

    /// Recorded meetings that can be followed up on: same or similar title first, then newest.
    static func candidates(forTitle title: String, excluding id: UUID? = nil, in meetings: [Meeting], limit: Int = 40) -> [Meeting] {
        let recorded = meetings
            .filter { isRecorded($0) && $0.id != id }
            .sorted { date(of: $0) > date(of: $1) }
        let key = normalizedTitle(title)
        guard !key.isEmpty else { return Array(recorded.prefix(limit)) }
        var similar: [Meeting] = []
        var others: [Meeting] = []
        for meeting in recorded {
            if isSimilar(normalizedTitle(meeting.title), key) {
                similar.append(meeting)
            } else {
                others.append(meeting)
            }
        }
        return Array((similar + others).prefix(limit))
    }

    /// True when the meeting's title is the same as or close to `title`.
    static func isSimilarTitle(_ meetingTitle: String, to title: String) -> Bool {
        isSimilar(normalizedTitle(meetingTitle), normalizedTitle(title))
    }

    /// Lowercased words separated by single spaces ("Design-Review!" becomes "design review").
    static func normalizedTitle(_ text: String) -> String {
        let letters: [Character] = text.lowercased().map { (character: Character) -> Character in
            (character.isLetter || character.isNumber) ? character : " "
        }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    private static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        let shortKey = lhs.count <= rhs.count ? lhs : rhs
        let longKey = lhs.count <= rhs.count ? rhs : lhs
        if shortKey.count >= 4, longKey.contains(shortKey) { return true }
        let left = significantWords(lhs)
        let right = significantWords(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let shared = Double(left.intersection(right).count)
        return shared / Double(min(left.count, right.count)) >= 0.5
    }

    private static func significantWords(_ key: String) -> Set<String> {
        Set(key.split(separator: " ").filter { $0.count >= 3 }.map { String($0) })
    }

    /// "12 Nov": the day a meeting took place.
    static func shortDate(of meeting: Meeting) -> String {
        date(of: meeting).formatted(.dateTime.day().month(.abbreviated))
    }

    /// "Follows up on Design review \u{00B7} 12 Nov".
    static func pillText(for previous: Meeting) -> String {
        "Follows up on \(previous.title) \u{00B7} \(shortDate(of: previous))"
    }
}
