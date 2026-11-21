import Foundation

/// One short clip of a detected voice, used to confirm whose voice it is.
public struct MeetingVoiceSample: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String

    public var duration: TimeInterval { max(0, endTime - startTime) }

    public var timestampText: String {
        let total = max(0, Int(startTime))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// How much one voice spoke.
public struct MeetingVoiceStats: Equatable, Sendable {
    public let talkTime: TimeInterval
    public let turns: Int

    public var talkTimeText: String {
        let total = max(0, Int(talkTime.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return seconds == 0 ? "\(minutes) min" : "\(minutes)m \(seconds)s"
    }

    public var summaryText: String {
        "\(talkTimeText) \u{00B7} \(turns) \(turns == 1 ? "turn" : "turns")"
    }
}

/// Picks the clips and numbers shown under each detected voice. Pure and deterministic.
public enum MeetingVoiceSamples {
    public static let minimumDuration: TimeInterval = 2
    public static let defaultLimit = 3

    /// Up to `limit` distinct clips of the voice. Clips are at least two seconds long and spread
    /// across the meeting: the voice's time span is split into `limit` parts and the longest clip
    /// of each part wins. When the voice has no clip that long, its longest clips are used instead.
    public static func samples(for row: MeetingVoiceRow, in meeting: Meeting,
                               limit: Int = MeetingVoiceSamples.defaultLimit) -> [MeetingVoiceSample] {
        guard limit > 0 else { return [] }
        let ids = Set(row.segmentIDs)
        let own = meeting.orderedTranscriptSegments.filter { segment in
            ids.contains(segment.id)
                && !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var seenText = Set<String>()
        var candidates: [TranscriptSegment] = []
        for segment in own {
            let key = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seenText.insert(key).inserted { candidates.append(segment) }
        }
        let long = candidates.filter { $0.endTime - $0.startTime >= minimumDuration }
        let pool = long.isEmpty ? candidates : long
        guard let first = pool.first, let last = pool.last else { return [] }

        let span = max(0.001, last.startTime - first.startTime)
        var chosen: [TranscriptSegment] = []
        for part in 0..<limit {
            let lower = first.startTime + span * Double(part) / Double(limit)
            let upper = first.startTime + span * Double(part + 1) / Double(limit)
            let inPart = pool.filter { segment in
                let inRange = segment.startTime >= lower
                let beforeEnd = part == limit - 1 ? segment.startTime <= upper : segment.startTime < upper
                return inRange && beforeEnd
            }
            if let best = longest(in: inPart, excluding: chosen) { chosen.append(best) }
        }
        while chosen.count < min(limit, pool.count) {
            guard let extra = longest(in: pool, excluding: chosen) else { break }
            chosen.append(extra)
        }
        let ordered = chosen.sorted { $0.startTime < $1.startTime }
        return ordered.map { segment in
            MeetingVoiceSample(id: segment.id, startTime: segment.startTime, endTime: segment.endTime,
                               text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Total talk time and number of separate turns. A turn is a run of the voice's segments
    /// that is not directly preceded by another of its segments.
    public static func stats(for row: MeetingVoiceRow, in meeting: Meeting) -> MeetingVoiceStats {
        let ids = Set(row.segmentIDs)
        var talk: TimeInterval = 0
        var turns = 0
        var previousWasOwn = false
        for segment in meeting.orderedTranscriptSegments {
            let isOwn = ids.contains(segment.id)
            if isOwn {
                talk += max(0, segment.endTime - segment.startTime)
                if !previousWasOwn { turns += 1 }
            }
            previousWasOwn = isOwn
        }
        return MeetingVoiceStats(talkTime: talk, turns: turns)
    }

    private static func longest(in segments: [TranscriptSegment], excluding chosen: [TranscriptSegment]) -> TranscriptSegment? {
        let used = Set(chosen.map(\.id))
        var best: TranscriptSegment?
        for segment in segments where !used.contains(segment.id) {
            guard let current = best else {
                best = segment
                continue
            }
            if segment.endTime - segment.startTime > current.endTime - current.startTime { best = segment }
        }
        return best
    }
}
