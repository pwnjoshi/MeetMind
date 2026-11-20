import Foundation
import SwiftData

/// One unnamed or assigned voice in the People sheet.
public struct MeetingVoiceRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let sampleText: String
    public let startTime: TimeInterval
    public let segmentIDs: [UUID]
    public let assignedPersonID: UUID?
}

public enum MeetingPeopleError: LocalizedError, Equatable {
    case emptyName
    case missingTarget

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name."
        case .missingTarget: return "That voice is no longer in this meeting."
        }
    }
}

/// Persistent edits behind the People sheet: naming voices, assigning them to people, merging voices and marking absence.
@MainActor
public enum MeetingPeopleEditor {
    private static let palette = ["#30B0C7", "#FF9500", "#FF2D55", "#AF52DE", "#34C759"]

    /// Unnamed voices still in the transcript plus voices that were assigned to a person, ordered by first appearance.
    public static func voices(in meeting: Meeting, record: MeetingRecordData) -> [MeetingVoiceRow] {
        let segments = meeting.orderedTranscriptSegments
        var rows: [MeetingVoiceRow] = []
        var seen = Set<String>()
        for segment in segments {
            guard let speaker = segment.speaker,
                  let label = speaker.recordingVoiceLabel,
                  speaker.name == label,
                  !seen.contains(label) else { continue }
            seen.insert(label)
            let own = segments.filter { $0.speaker?.id == speaker.id }
            rows.append(MeetingVoiceRow(id: label, label: label, sampleText: own.first?.text ?? "",
                                        startTime: own.first?.startTime ?? 0,
                                        segmentIDs: own.map(\.id), assignedPersonID: nil))
        }
        for assignment in record.voiceAssignments where !seen.contains(assignment.label) {
            let own = segments.filter { assignment.segmentIDs.contains($0.id) }
            guard !own.isEmpty else { continue }
            seen.insert(assignment.label)
            rows.append(MeetingVoiceRow(id: assignment.label, label: assignment.label,
                                        sampleText: own.first?.text ?? "", startTime: own.first?.startTime ?? 0,
                                        segmentIDs: own.map(\.id), assignedPersonID: assignment.personID))
        }
        return rows.sorted { $0.startTime < $1.startTime }
    }

    /// Moves every segment of `row` to `person` and remembers the assignment.
    public static func assign(_ row: MeetingVoiceRow, to person: Speaker, meeting: Meeting,
                              context: ModelContext, store: MeetingRecordStore) throws {
        let before = store.record(for: meeting.id)
        try store.update(meeting.id) { record in
            record.voiceAssignments.removeAll { $0.label == row.label }
            record.voiceAssignments.append(VoiceAssignment(label: row.label, personID: person.id, segmentIDs: row.segmentIDs))
        }
        do {
            let previous = moveSegments(row.segmentIDs, in: meeting, to: person)
            meeting.addParticipant(person)
            for old in previous { retireIfUnused(old, meeting: meeting, context: context) }
            try context.save()
        } catch {
            context.rollback()
            try? store.update(meeting.id) { $0 = before }
            throw error
        }
    }

    /// Creates (or reuses) a named person for the voice, then assigns the voice to them.
    public static func rename(_ row: MeetingVoiceRow, to name: String, meeting: Meeting,
                              context: ModelContext, store: MeetingRecordStore) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingPeopleError.emptyName }
        let person: Speaker
        if let existing = meeting.namedAttendees.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            person = existing
        } else {
            person = Speaker(name: trimmed, avatarColorHex: palette[meeting.participants.count % palette.count])
            context.insert(person)
        }
        try assign(row, to: person, meeting: meeting, context: context, store: store)
    }

    /// Turns an assigned voice back into an unnamed voice.
    public static func keepUnknown(_ row: MeetingVoiceRow, meeting: Meeting,
                                   context: ModelContext, store: MeetingRecordStore) throws {
        guard row.assignedPersonID != nil else { return }
        let before = store.record(for: meeting.id)
        try store.update(meeting.id) { record in
            record.voiceAssignments.removeAll { $0.label == row.label }
        }
        do {
            let voice = Speaker(name: row.label, avatarColorHex: "#8E8E93")
            voice.recordingVoiceLabel = row.label
            context.insert(voice)
            _ = moveSegments(row.segmentIDs, in: meeting, to: voice)
            meeting.addParticipant(voice)
            try context.save()
        } catch {
            context.rollback()
            try? store.update(meeting.id) { $0 = before }
            throw error
        }
    }

    /// Moves all segments of `row` onto the speaker behind `target`.
    public static func merge(_ row: MeetingVoiceRow, into target: MeetingVoiceRow, meeting: Meeting,
                             context: ModelContext, store: MeetingRecordStore) throws {
        guard row.id != target.id else { return }
        guard let targetSpeaker = meeting.transcriptSegments.first(where: { target.segmentIDs.contains($0.id) })?.speaker else {
            throw MeetingPeopleError.missingTarget
        }
        let before = store.record(for: meeting.id)
        try store.update(meeting.id) { record in
            record.voiceAssignments.removeAll { $0.label == row.label }
            if let index = record.voiceAssignments.firstIndex(where: { $0.label == target.label }) {
                record.voiceAssignments[index].segmentIDs += row.segmentIDs
            }
        }
        do {
            let previous = moveSegments(row.segmentIDs, in: meeting, to: targetSpeaker)
            for old in previous { retireIfUnused(old, meeting: meeting, context: context) }
            try context.save()
        } catch {
            context.rollback()
            try? store.update(meeting.id) { $0 = before }
            throw error
        }
    }

    public static func isAbsent(_ person: Speaker, in meeting: Meeting) -> Bool {
        meeting.absentParticipantIDs?.contains(person.id) == true
    }

    public static func setAbsent(_ absent: Bool, person: Speaker, meeting: Meeting, context: ModelContext) throws {
        let previous = meeting.absentParticipantIDs
        var ids = Set(previous ?? [])
        if absent { ids.insert(person.id) } else { ids.remove(person.id) }
        meeting.absentParticipantIDs = ids.sorted { $0.uuidString < $1.uuidString }
        do {
            try context.save()
        } catch {
            meeting.absentParticipantIDs = previous
            throw error
        }
    }

    private static func moveSegments(_ ids: [UUID], in meeting: Meeting, to speaker: Speaker) -> [Speaker] {
        var previous: [Speaker] = []
        for segment in meeting.transcriptSegments where ids.contains(segment.id) {
            if let old = segment.speaker, old.id != speaker.id, !previous.contains(where: { $0.id == old.id }) {
                previous.append(old)
            }
            segment.speaker = speaker
        }
        return previous
    }

    /// Removes an unnamed voice that no longer owns any segment of this meeting.
    private static func retireIfUnused(_ speaker: Speaker, meeting: Meeting, context: ModelContext) {
        guard let label = speaker.recordingVoiceLabel, speaker.name == label else { return }
        guard !meeting.transcriptSegments.contains(where: { $0.speaker?.id == speaker.id }) else { return }
        meeting.removeParticipant(speaker)
        let usedElsewhere = speaker.meetings.contains { $0.id != meeting.id }
        if !usedElsewhere && speaker.assignedActionItems.isEmpty {
            context.delete(speaker)
        }
    }
}
