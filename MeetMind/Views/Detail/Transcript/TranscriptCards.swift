import Foundation
import OfflineEngineKit

/// One transcript segment inside a card. Plain values, so the list never touches SwiftData while scrolling.
struct TranscriptCardLine: Identifiable, Hashable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let isEdited: Bool
}

/// One card on the Transcript page: consecutive segments of one speaker with a gap under two seconds.
struct TranscriptCard: Identifiable {
    let id: UUID
    let speakerID: UUID?
    let speakerName: String
    let colorHex: String
    let initials: String
    let start: TimeInterval
    let end: TimeInterval
    let lines: [TranscriptCardLine]
    let isUsedInMinutes: Bool

    var text: String { lines.map(\.text).joined(separator: " ") }
    var timeText: String { TranscriptClock.text(start) }

    var accessibilityText: String {
        var label = "\(speakerName), \(TranscriptClock.spoken(start)), \(text)"
        if isUsedInMinutes { label += ", used in minutes" }
        return label
    }
}

enum TranscriptClock {
    /// "mm:ss", or "h:mm:ss" past an hour.
    static func text(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.isFinite ? time : 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Spoken form for VoiceOver.
    static func spoken(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.isFinite ? time : 0))
        let minutes = total / 60
        let seconds = total % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondText = seconds == 1 ? "1 second" : "\(seconds) seconds"
        return "\(minuteText) \(secondText)"
    }
}

enum TranscriptCardBuilder {
    static let neutralColorHex = "#8E8E93"
    /// Segments of one speaker closer together than this share a card.
    static let mergeGap: TimeInterval = 2

    /// Builds cards from segments that are already in playback order.
    static func build(segments: [TranscriptSegment], used: Set<UUID>) -> [TranscriptCard] {
        var cards: [TranscriptCard] = []
        var lines: [TranscriptCardLine] = []
        var speaker: Speaker?
        var hasSpeaker = false

        func flush() {
            guard let first = lines.first, let last = lines.last else { return }
            let isUsed = lines.contains { used.contains($0.id) }
            cards.append(TranscriptCard(
                id: first.id,
                speakerID: speaker?.id,
                speakerName: Speaker.displayName(of: speaker),
                colorHex: speaker?.avatarColorHex ?? neutralColorHex,
                initials: speaker?.initials ?? "?",
                start: first.start,
                end: max(last.end, last.start),
                lines: lines,
                isUsedInMinutes: isUsed))
            lines = []
        }

        for segment in segments {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let line = TranscriptCardLine(id: segment.id, text: trimmed, start: segment.startTime,
                                          end: segment.endTime, isEdited: segment.isEdited)
            if let previous = lines.last, hasSpeaker,
               segment.speaker?.id == speaker?.id,
               line.start - previous.end < mergeGap {
                lines.append(line)
            } else {
                flush()
                speaker = segment.speaker
                hasSpeaker = true
                lines = [line]
            }
        }
        flush()
        return cards
    }

    /// The card being spoken at `time`: the last card that started, unless the playhead is
    /// more than four seconds past its end.
    static func activeCardID(at time: TimeInterval, in cards: [TranscriptCard]) -> UUID? {
        var candidate: TranscriptCard?
        for card in cards {
            if card.start <= time + 0.05 { candidate = card } else { break }
        }
        guard let candidate else { return nil }
        return time - candidate.end <= 4 ? candidate.id : nil
    }
}

struct TranscriptSegmentRef {
    let id: UUID
    let sequenceIndex: Int?
    let start: TimeInterval
}

/// Decides which transcript segments the minutes cite.
///
/// The analysis checkpoint (`Meeting.offlineAnalysisData`) holds the transcript as `AnalysisTurn`s
/// and every minutes item carries `SourceEvidence(turnID:quote:)`. `replaceTranscript` writes one
/// segment per turn with `sequenceIndex` equal to the turn's index, so a segment maps to its turn by
/// index (confirmed by start time), or by start time alone. After the person edits the transcript,
/// the analysis is rerun with turn ids equal to the segment id strings, so those match directly.
/// Evidence ids with a suffix ("t3.1") count toward their root ("t3").
enum TranscriptUsage {
    static func usedSegmentIDs(checkpointData: Data?, segments: [TranscriptSegmentRef]) -> Set<UUID> {
        guard let checkpointData,
              let checkpoint = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: checkpointData)
        else { return [] }
        let evidence = evidenceTurnIDs(in: checkpoint)
        guard !evidence.isEmpty else { return [] }
        let evidenceRoots = Set(evidence.map(root))

        func isCited(_ turnID: String) -> Bool {
            evidence.contains(turnID) || evidenceRoots.contains(turnID) || evidence.contains(root(turnID))
        }

        let turns = checkpoint.turns
        var used = Set<UUID>()
        for segment in segments {
            if isCited(segment.id.uuidString) {
                used.insert(segment.id)
                continue
            }
            var turn: AnalysisTurn?
            if let index = segment.sequenceIndex, turns.indices.contains(index),
               abs(turns[index].start - segment.start) < 0.05 {
                turn = turns[index]
            } else {
                turn = turns.first { abs($0.start - segment.start) < 0.05 }
            }
            if let turn, isCited(turn.id) { used.insert(segment.id) }
        }
        return used
    }

    static func evidenceTurnIDs(in checkpoint: MeetingAnalysisCheckpoint) -> Set<String> {
        var ids = Set<String>()
        func add(_ items: [SourceEvidence]) { for item in items { ids.insert(item.turnID) } }
        for result in checkpoint.analysis {
            for point in result.discussion { add(point.evidence) }
            for point in result.decisions { add(point.evidence) }
            for point in result.openIssues { add(point.evidence) }
            for task in result.tasks { add(task.evidence) }
        }
        if let minutes = checkpoint.minutes {
            for topic in minutes.topics { add(topic.evidence) }
            for resolution in minutes.resolutions { add(resolution.evidence) }
            for action in minutes.actions { add(action.evidence) }
            for issue in minutes.openIssues { add(issue.evidence) }
            if let next = minutes.nextMeeting { add(next.evidence) }
        }
        return ids
    }

    private static func root(_ id: String) -> String {
        id.split(separator: ".").first.map(String.init) ?? id
    }
}
