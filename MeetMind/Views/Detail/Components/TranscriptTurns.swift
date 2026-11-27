import SwiftUI

/// A run of consecutive transcript segments spoken by the same person.
struct TranscriptTurn: Identifiable {
    let id: UUID
    let speaker: Speaker?
    let speakerName: String
    let colorHex: String
    let initials: String
    let startTime: TimeInterval
    let segments: [TranscriptSegment]

    var timestampText: String {
        let total = max(0, Int(startTime))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Pure transcript logic used by the Transcript and audio page: turn grouping, search and the active line.
enum TranscriptTurnGrouper {
    static let neutralColorHex = "#8E8E93"

    /// Groups ordered segments into speaker turns. A new turn starts whenever the speaker changes.
    static func turns(from segments: [TranscriptSegment]) -> [TranscriptTurn] {
        var result: [TranscriptTurn] = []
        var currentSegments: [TranscriptSegment] = []
        var currentSpeaker: Speaker?
        for segment in segments {
            if currentSegments.isEmpty {
                currentSegments = [segment]
                currentSpeaker = segment.speaker
            } else if segment.speaker?.id == currentSpeaker?.id {
                currentSegments.append(segment)
            } else {
                result.append(makeTurn(speaker: currentSpeaker, segments: currentSegments))
                currentSegments = [segment]
                currentSpeaker = segment.speaker
            }
        }
        if !currentSegments.isEmpty {
            result.append(makeTurn(speaker: currentSpeaker, segments: currentSegments))
        }
        return result
    }

    /// Turns that contain a line matching `query`. Each turn keeps only its matching lines.
    /// An empty query returns every turn unchanged.
    static func turns(from segments: [TranscriptSegment], matching query: String) -> [TranscriptTurn] {
        let all = turns(from: segments)
        guard TranscriptSearch.isActive(query) else { return all }
        var filtered: [TranscriptTurn] = []
        for turn in all {
            let lines = turn.segments.filter { TranscriptSearch.matches($0.text, query: query) }
            if !lines.isEmpty {
                filtered.append(makeTurn(speaker: turn.speaker, segments: lines))
            }
        }
        return filtered
    }

    /// The line to highlight at `time`: the segment being spoken, or the last one that started
    /// when the playhead sits in a short pause. `nil` before the first line or after a long silence.
    static func activeSegmentID(at time: TimeInterval, in segments: [TranscriptSegment],
                                pauseTolerance: TimeInterval = 4) -> UUID? {
        var candidate: TranscriptSegment?
        for segment in segments where segment.startTime <= time {
            if let current = candidate, current.startTime > segment.startTime { continue }
            candidate = segment
        }
        guard let candidate else { return nil }
        if time < candidate.endTime { return candidate.id }
        return time - candidate.endTime <= pauseTolerance ? candidate.id : nil
    }

    private static func makeTurn(speaker: Speaker?, segments: [TranscriptSegment]) -> TranscriptTurn {
        TranscriptTurn(
            id: segments[0].id,
            speaker: speaker,
            speakerName: Speaker.displayName(of: speaker),
            colorHex: speaker?.colorHex ?? neutralColorHex,
            initials: speaker?.initials ?? "?",
            startTime: segments[0].startTime,
            segments: segments
        )
    }
}

/// Case-insensitive transcript search with match highlighting.
enum TranscriptSearch {
    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func matches(_ text: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Number of lines that contain the query.
    static func matchingLineCount(in segments: [TranscriptSegment], query: String) -> Int {
        guard isActive(query) else { return segments.count }
        return segments.filter { matches($0.text, query: query) }.count
    }

    /// The text with every occurrence of the query marked with a purple background.
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return result }
        var ranges: [Range<AttributedString.Index>] = []
        var cursor = result.startIndex
        while cursor < result.endIndex,
              let found = result[cursor...].range(of: needle, options: .caseInsensitive) {
            ranges.append(found)
            cursor = found.upperBound
        }
        for range in ranges {
            result[range].backgroundColor = Theme.Colors.manentAccent.opacity(0.28)
        }
        return result
    }
}
