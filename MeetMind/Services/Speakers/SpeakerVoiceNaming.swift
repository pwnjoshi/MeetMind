import Foundation
import SwiftData
import OfflineEngineKit

/// Names detected voices from stored voice profiles and teaches the profiles from the user's choices.
///
/// Everything runs on embeddings the diarizer already produced. The only extra model work is
/// enrolling a saved voice sample for an attendee who has no profile yet, bounded to a few short clips.
@MainActor
public enum SpeakerVoiceNaming {
    /// A voice needs this much speech before it teaches a profile. Naming itself needs less (3 s).
    public static let minimumLearningSeconds: Double = 6
    /// Voices of a re-run are the same meeting audio when every label's embedding is this close to the old one.
    private static let unchangedSimilarity: Float = 0.98
    private static let enrollmentsPerRun = 3
    private static var enrollmentAttempted = Set<UUID>()
    private static let userProfileKey = "MeetMind_UserProfile"

    /// Matches the checkpoint's voices to known people, remembers the result for the Name Speakers
    /// screen, and records automatic matches as voice assignments so the transcript uses the names.
    /// Voices the user already assigned are left alone.
    @discardableResult
    public static func apply(_ checkpoint: MeetingAnalysisCheckpoint, to meeting: Meeting, context: ModelContext,
                             store: VoiceProfileStore = .shared, records: MeetingRecordStore = .shared,
                             defaults: UserDefaults = .standard,
                             config: VoiceMatchConfig = .standard) async -> [VoiceMatch] {
        guard let embeddings = checkpoint.speakerEmbeddings, !embeddings.isEmpty,
              let revision = checkpoint.speakerEmbeddingModel else { return [] }
        if let existing = store.record(for: meeting.id), existing.modelRevision == revision,
           sameVoices(existing.centroids, embeddings) {
            return existing.matches.values.sorted { $0.label < $1.label }
        }
        let allClusters = VoiceMatcher.clusters(embeddings: embeddings, spans: checkpoint.speakers)
        guard !allClusters.isEmpty else { return [] }

        let speakers = (try? context.fetch(FetchDescriptor<Speaker>())) ?? []
        var people: [UUID: Speaker] = [:]
        for speaker in speakers where !MeetingPeopleEditor.isGenericVoice(speaker) {
            if people[speaker.id] == nil { people[speaker.id] = speaker }
        }

        let user = currentUser(defaults: defaults)
        var room = Set(meeting.namedAttendees.map(\.id))
        if let name = user.name, let me = MeetingPeopleEditor.knownSpeaker(named: name, context: context) {
            room.insert(me.id)
        }
        let attendeeIDs: Set<UUID>? = meeting.namedAttendees.isEmpty ? nil : room

        await enrollSamples(for: attendeeIDs.map { Array($0) } ?? [], people: people, revision: revision,
                            user: user, store: store)

        // Voices and people the user already settled in this meeting are not offered again.
        let assignments = records.record(for: meeting.id).voiceAssignments
        let settledLabels = Set(assignments.map(\.label))
        let settledPeople = Set(assignments.map(\.personID))
        let clusters = allClusters.filter { !settledLabels.contains($0.label) }
        let profiles = store.profiles(revision: revision).filter {
            people[$0.personID] != nil && !settledPeople.contains($0.personID)
        }
        let matches = VoiceMatcher.match(clusters: clusters, profiles: profiles, attendeeIDs: attendeeIDs, config: config)

        var seconds: [String: Double] = [:]
        for cluster in allClusters { seconds[cluster.label] = cluster.speechSeconds }
        var byLabel: [String: VoiceMatch] = [:]
        for match in matches { byLabel[match.label] = match }
        let record = MeetingVoiceRecord(modelRevision: revision, centroids: embeddings,
                                        speechSeconds: seconds, matches: byLabel)
        try? store.setRecord(record, for: meeting.id)

        let automatic = matches.filter { $0.status == .auto }
        if !automatic.isEmpty {
            try? records.update(meeting.id) { data in
                for match in automatic where !data.voiceAssignments.contains(where: { $0.label == match.label }) {
                    data.voiceAssignments.append(
                        VoiceAssignment(label: match.label, personID: match.personID, segmentIDs: []))
                }
            }
        }
        return matches.sorted { $0.label < $1.label }
    }

    /// Teaches the profiles of the people the user assigned to `labels`. Only explicit choices are
    /// passed in, so an automatic name nobody checked never reinforces itself. Voices with little speech,
    /// voices from an older diarization model and voices that do not sound like the person are skipped.
    public static func learn(labels: Set<String>, meeting: Meeting, store: VoiceProfileStore = .shared,
                             records: MeetingRecordStore = .shared) async {
        guard !labels.isEmpty, var record = store.record(for: meeting.id),
              let current = await MeetingAnalysisPipeline.shared.diarizationModelRevision(),
              current == record.modelRevision else { return }
        let assignments = records.record(for: meeting.id).voiceAssignments
        var changed = false
        for label in labels.sorted() {
            guard let assignment = assignments.first(where: { $0.label == label }),
                  let vector = record.centroids[label],
                  (record.speechSeconds[label] ?? 0) >= minimumLearningSeconds,
                  record.learned[label] != assignment.personID else { continue }
            do {
                try store.learn(vector, personID: assignment.personID, revision: record.modelRevision)
                record.learned[label] = assignment.personID
                changed = true
            } catch {
                continue
            }
        }
        if changed { try? store.setRecord(record, for: meeting.id) }
    }

    /// The remembered match for a voice label, if any.
    public static func match(forLabel label: String, meetingID: UUID, store: VoiceProfileStore = .shared) -> VoiceMatch? {
        store.record(for: meetingID)?.matches[label]
    }

    public static func person(id: UUID, context: ModelContext) -> Speaker? {
        var descriptor = FetchDescriptor<Speaker>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Helpers

    private static func sameVoices(_ old: [String: [Float]], _ new: [String: [Float]]) -> Bool {
        guard Set(old.keys) == Set(new.keys) else { return false }
        return new.allSatisfy { pair in
            (SpeakerEmbeddingMath.cosine(old[pair.key] ?? [], pair.value) ?? 0) >= unchangedSimilarity
        }
    }

    private static func currentUser(defaults: UserDefaults) -> (name: String?, voiceURL: URL?) {
        guard let data = defaults.data(forKey: userProfileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return (nil, nil) }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? nil : name, profile.voiceProfileURL)
    }

    /// Builds profiles for attendees who recorded a voice sample but have none yet.
    private static func enrollSamples(for ids: [UUID], people: [UUID: Speaker], revision: String,
                                      user: (name: String?, voiceURL: URL?), store: VoiceProfileStore) async {
        var jobs: [(UUID, URL)] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard jobs.count < enrollmentsPerRun, let person = people[id],
                  !enrollmentAttempted.contains(id),
                  store.profile(for: id, revision: revision) == nil else { continue }
            var sample = person.voiceSampleURL
            if sample == nil, let name = user.name, let voice = user.voiceURL,
               person.name.caseInsensitiveCompare(name) == .orderedSame {
                sample = voice
            }
            guard let url = sample, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { continue }
            enrollmentAttempted.insert(id)
            jobs.append((id, url))
        }
        for (id, url) in jobs {
            guard let result = try? await MeetingAnalysisPipeline.shared.embedVoiceSample(url),
                  result.modelRevision == revision else { continue }
            _ = try? store.learn(result.embedding, personID: id, revision: revision)
        }
    }
}

extension MeetingAnalysisCheckpoint {
    /// The checkpoint without voice embeddings, for the copy kept in the meeting's own data.
    public func withoutVoiceEmbeddings() -> MeetingAnalysisCheckpoint {
        var copy = self
        copy.speakerEmbeddings = nil
        copy.speakerEmbeddingModel = nil
        return copy
    }
}
