import Foundation
import SwiftData
import OfflineEngineKit

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
    case duplicate(String)
    case spokeInMeeting(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name."
        case .missingTarget: return "That voice is no longer in this meeting."
        case .duplicate(let name): return "\(name) is already in this meeting."
        case .spokeInMeeting(let name):
            return "\(name) spoke in this meeting. Mark them absent, or move their voice to someone else first."
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
            repointActions(from: previous, to: person, meeting: meeting)
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
        let person = existingOrNewSpeaker(named: trimmed, meeting: meeting, context: context)
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
            repointActions(from: previous, to: targetSpeaker, meeting: meeting)
            for old in previous { retireIfUnused(old, meeting: meeting, context: context) }
            try context.save()
        } catch {
            context.rollback()
            try? store.update(meeting.id) { $0 = before }
            throw error
        }
    }

    // MARK: - Attendees

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sameName(_ left: String, _ right: String) -> Bool {
        normalizedName(left) == normalizedName(right)
    }

    private static func optionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "Speaker 1" style placeholders are voices, not people.
    public static func isGenericVoice(_ speaker: Speaker) -> Bool {
        if let label = speaker.recordingVoiceLabel, speaker.name == label { return true }
        let parts = speaker.name.split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "speaker" else { return false }
        return Int(parts[1]) != nil
    }

    private static func richness(_ speaker: Speaker) -> Int {
        let emailScore = (speaker.email ?? "").isEmpty ? 0 : 1000
        return emailScore + speaker.meetings.count
    }

    /// Local people who can still be added to `meeting`, one per name (case-insensitive), filtered by `query`.
    /// `speakers` is every Speaker record the app knows, so people from other meetings are offered too.
    public static func candidates(from speakers: [Speaker], for meeting: Meeting, query: String = "") -> [Speaker] {
        let attendeeNames = Set(meeting.namedAttendees.map { normalizedName($0.name) })
        let attendeeIDs = Set(meeting.participants.map(\.id))
        let needle = normalizedName(query)
        var chosen: [String: Speaker] = [:]
        for speaker in speakers {
            let key = normalizedName(speaker.name)
            if key.isEmpty || isGenericVoice(speaker) { continue }
            if attendeeIDs.contains(speaker.id) || attendeeNames.contains(key) { continue }
            if !needle.isEmpty {
                let email = (speaker.email ?? "").lowercased()
                if !key.contains(needle) && !email.contains(needle) { continue }
            }
            if let current = chosen[key] {
                if richness(speaker) > richness(current) { chosen[key] = speaker }
            } else {
                chosen[key] = speaker
            }
        }
        return chosen.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The local person called `name`, preferring the record that has an email and the most meetings.
    public static func knownSpeaker(named name: String, context: ModelContext) -> Speaker? {
        let all = (try? context.fetch(FetchDescriptor<Speaker>())) ?? []
        let matches = all.filter { !isGenericVoice($0) && sameName($0.name, name) }
        return matches.max(by: { richness($0) < richness($1) })
    }

    private static func existingOrNewSpeaker(named name: String, meeting: Meeting, context: ModelContext) -> Speaker {
        if let attendee = meeting.namedAttendees.first(where: { sameName($0.name, name) }) { return attendee }
        if let known = knownSpeaker(named: name, context: context) { return known }
        let created = Speaker(name: name, avatarColorHex: palette[meeting.participants.count % palette.count])
        context.insert(created)
        return created
    }

    /// People who can own an action or decide a decision: everyone named in the meeting, plus `current` if it is someone else.
    public static func ownerChoices(for meeting: Meeting, including current: Speaker? = nil) -> [Speaker] {
        var result = meeting.namedAttendees
        if let current, !result.contains(where: { $0.id == current.id }) { result.append(current) }
        return result
    }

    /// Adds an existing local person to the meeting as present. Throws `duplicate` when the name is already an attendee.
    @discardableResult
    public static func addAttendee(_ person: Speaker, to meeting: Meeting, context: ModelContext) throws -> Speaker {
        if let existing = meeting.namedAttendees.first(where: { sameName($0.name, person.name) }) {
            throw MeetingPeopleError.duplicate(existing.name)
        }
        let previousParticipants = meeting.participants
        let previousAbsent = meeting.absentParticipantIDs
        meeting.addParticipant(person)
        if let ids = meeting.absentParticipantIDs {
            meeting.absentParticipantIDs = ids.filter { $0 != person.id }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            meeting.participants = previousParticipants
            meeting.absentParticipantIDs = previousAbsent
            throw error
        }
        return person
    }

    /// Creates a person (or reuses the local one with the same name) and adds them to the meeting as present.
    @discardableResult
    public static func addNewAttendee(name: String, email: String?, role: String?,
                                      meeting: Meeting, context: ModelContext) throws -> Speaker {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingPeopleError.emptyName }
        if let existing = meeting.namedAttendees.first(where: { sameName($0.name, trimmed) }) {
            throw MeetingPeopleError.duplicate(existing.name)
        }
        let cleanEmail = optionalText(email)
        let cleanRole = optionalText(role)
        let person: Speaker
        if let known = knownSpeaker(named: trimmed, context: context) {
            person = known
            if (person.email ?? "").isEmpty, let cleanEmail { person.email = cleanEmail }
            if (person.role ?? "").isEmpty, let cleanRole { person.role = cleanRole }
        } else {
            let color = palette[meeting.participants.count % palette.count]
            person = Speaker(name: trimmed, email: cleanEmail, role: cleanRole, avatarColorHex: color)
            context.insert(person)
        }
        return try addAttendee(person, to: meeting, context: context)
    }

    /// True when the person has no transcript lines in this meeting, so removing them cannot orphan a voice.
    public static func canRemove(_ person: Speaker, from meeting: Meeting) -> Bool {
        !meeting.transcriptSegments.contains { $0.speaker?.id == person.id }
    }

    /// Removes the person from this meeting only. The Speaker record and their actions stay.
    public static func removeAttendee(_ person: Speaker, from meeting: Meeting, context: ModelContext) throws {
        guard canRemove(person, from: meeting) else { throw MeetingPeopleError.spokeInMeeting(person.name) }
        let previousParticipants = meeting.participants
        let previousAbsent = meeting.absentParticipantIDs
        meeting.removeParticipant(person)
        if let ids = meeting.absentParticipantIDs {
            meeting.absentParticipantIDs = ids.filter { $0 != person.id }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            meeting.participants = previousParticipants
            meeting.absentParticipantIDs = previousAbsent
            throw error
        }
    }

    /// Renames a person and updates their email and role. The Speaker record is shared, so other meetings see the change.
    public static func updatePerson(_ person: Speaker, name: String, email: String?, role: String?,
                                    meeting: Meeting, context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingPeopleError.emptyName }
        if let clash = meeting.namedAttendees.first(where: { $0.id != person.id && sameName($0.name, trimmed) }) {
            throw MeetingPeopleError.duplicate(clash.name)
        }
        let previous = (person.name, person.email, person.role)
        person.name = trimmed
        person.email = optionalText(email)
        person.role = optionalText(role)
        do {
            try context.save()
        } catch {
            context.rollback()
            (person.name, person.email, person.role) = previous
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

    /// Actions owned by a detected voice ("Speaker 1") move to the person the voice now belongs to.
    /// Named people keep their actions; only unnamed voices are re-pointed.
    private static func repointActions(from previous: [Speaker], to person: Speaker, meeting: Meeting) {
        for old in previous where old.isUnnamedVoice && old.id != person.id {
            for item in meeting.actionItems where item.assignee?.id == old.id {
                item.assignee = person
            }
        }
    }

    // MARK: - Durable naming across re-analysis

    /// Replaces the transcript with freshly analysed `turns` and keeps the user's voice naming.
    /// A diarization label that was assigned to a person ("Speaker 1" -> Maya) points at that
    /// person again, and the stored assignment is updated to the new segment ids.
    public static func replaceTranscript(of meeting: Meeting, with turns: [AnalysisTurn],
                                         context: ModelContext, store: MeetingRecordStore) {
        let assignments = store.record(for: meeting.id).voiceAssignments
        let previousSegments = meeting.transcriptSegments
        meeting.transcriptSegments.removeAll()
        for segment in previousSegments { context.delete(segment) }

        var speakersByLabel: [String: Speaker] = [:]
        var segmentIDsByLabel: [String: [UUID]] = [:]
        for (index, turn) in turns.enumerated() {
            var speaker: Speaker?
            if let label = turn.speaker {
                if let known = speakersByLabel[label] {
                    speaker = known
                } else {
                    let resolved = speakerForLabel(label, assignments: assignments, meeting: meeting, context: context)
                    speakersByLabel[label] = resolved
                    speaker = resolved
                }
            }
            let segment = TranscriptSegment(text: turn.text, startTime: turn.start, endTime: turn.end,
                                            confidence: 0, speaker: speaker, meeting: meeting, sequenceIndex: index)
            meeting.addTranscriptSegment(segment)
            if let label = turn.speaker { segmentIDsByLabel[label, default: []].append(segment.id) }
        }

        guard !assignments.isEmpty else { return }
        try? store.update(meeting.id) { record in
            for index in record.voiceAssignments.indices {
                let label = record.voiceAssignments[index].label
                record.voiceAssignments[index].segmentIDs = segmentIDsByLabel[label] ?? []
            }
        }
    }

    /// The speaker a diarization label belongs to: the assigned person, a speaker already holding the label, or a new voice.
    private static func speakerForLabel(_ label: String, assignments: [VoiceAssignment],
                                        meeting: Meeting, context: ModelContext) -> Speaker {
        if let assignment = assignments.first(where: { $0.label == label }),
           let person = findPerson(withID: assignment.personID, meeting: meeting, context: context) {
            meeting.addParticipant(person)
            return person
        }
        let holder = meeting.participants.first {
            $0.recordingVoiceLabel == label || ($0.recordingVoiceLabel == nil && $0.name == label)
        }
        if let holder {
            holder.recordingVoiceLabel = label
            return holder
        }
        let created = Speaker(name: label)
        created.recordingVoiceLabel = label
        context.insert(created)
        meeting.addParticipant(created)
        return created
    }

    private static func findPerson(withID id: UUID, meeting: Meeting, context: ModelContext) -> Speaker? {
        if let attendee = meeting.participants.first(where: { $0.id == id }) { return attendee }
        var descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
