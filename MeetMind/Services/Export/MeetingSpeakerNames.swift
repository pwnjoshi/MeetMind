import Foundation

/// Resolves a raw diarization label ("Speaker 1") to the name the user gave that voice.
/// Analysis turns, Vidur sources and task evidence keep the raw label from the engine,
/// so every screen that shows a turn's speaker goes through this one lookup.
public struct MeetingSpeakerNames {
    private let namesByLabel: [String: String]

    public init(meeting: Meeting, record: MeetingRecordData) {
        var map: [String: String] = [:]
        for speaker in meeting.participants {
            guard let label = speaker.recordingVoiceLabel, !speaker.isUnnamedVoice else { continue }
            map[label] = speaker.displayName
        }
        for assignment in record.voiceAssignments {
            if let person = meeting.participants.first(where: { $0.id == assignment.personID }) {
                map[assignment.label] = person.displayName
            }
        }
        namesByLabel = map
    }

    /// Every diarization label the user has tied to a named person.
    public var assignedLabels: [String: String] { namesByLabel }

    /// Reads the shared record store.
    @MainActor
    public init(meeting: Meeting, store: MeetingRecordStore) {
        self.init(meeting: meeting, record: store.record(for: meeting.id))
    }

    /// The assigned person's name, the label itself for a voice nobody named, and
    /// "Unknown Speaker" only when the turn has no speaker label at all.
    public func name(forLabel label: String?) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return Speaker.unknownDisplayName }
        return namesByLabel[trimmed] ?? trimmed
    }

    public func name(for segment: TranscriptSegment) -> String {
        segment.speakerDisplayName
    }
}
