import Foundation
import CryptoKit

/// Domain lifecycle derived from the existing Meeting graph and review sidecar.
public enum MeetingLifecycleState: String, Codable, CaseIterable, Sendable {
    case scheduled
    case readyToRecord
    case recording
    case saved
    case needsModels
    case queued
    case processing
    case failed
    case speakerReview
    case draftReview
    case finalized
}

/// Canonical screen for a meeting UUID. Several processing states intentionally
/// share one screen, which renders the exact persisted sub-state.
public enum MeetingDestination: String, Codable, Sendable, Equatable {
    case plan
    case captureSetup
    case recording
    case processing
    case reviewChecklist
    case finalMinutes
}

public struct MeetingLifecycleInput: Sendable, Equatable {
    public var status: MeetingStatus
    public var scheduledStartTime: Date?
    public var hasAudio: Bool
    public var hasTranscript: Bool
    public var hasSummary: Bool
    public var hasTypedNotesSource: Bool
    public var analysisState: String?
    public var minutesNeedFinalization: Bool?
    public var currentFingerprint: String?
    public var finalizedFingerprint: String?
    public var now: Date

    public init(status: MeetingStatus, scheduledStartTime: Date? = nil, hasAudio: Bool = false,
                hasTranscript: Bool = false, hasSummary: Bool = false, hasTypedNotesSource: Bool = false,
                analysisState: String? = nil, minutesNeedFinalization: Bool? = nil,
                currentFingerprint: String? = nil, finalizedFingerprint: String? = nil, now: Date = Date()) {
        self.status = status
        self.scheduledStartTime = scheduledStartTime
        self.hasAudio = hasAudio
        self.hasTranscript = hasTranscript
        self.hasSummary = hasSummary
        self.hasTypedNotesSource = hasTypedNotesSource
        self.analysisState = analysisState
        self.minutesNeedFinalization = minutesNeedFinalization
        self.currentFingerprint = currentFingerprint
        self.finalizedFingerprint = finalizedFingerprint
        self.now = now
    }
}

public struct MeetingLifecycleResolution: Sendable, Equatable {
    public let state: MeetingLifecycleState
    public let destination: MeetingDestination
    public let isLegacyFinalized: Bool

    public init(state: MeetingLifecycleState, destination: MeetingDestination, isLegacyFinalized: Bool = false) {
        self.state = state
        self.destination = destination
        self.isLegacyFinalized = isLegacyFinalized
    }
}

public enum MeetingLifecycleResolver {
    /// Pure resolver. It performs no persistence, navigation, or service lookup.
    public static func resolve(_ input: MeetingLifecycleInput) -> MeetingLifecycleResolution {
        if input.status == .scheduled {
            if let start = input.scheduledStartTime, start > input.now {
                return MeetingLifecycleResolution(state: .scheduled, destination: .plan)
            }
            return MeetingLifecycleResolution(state: .readyToRecord, destination: .captureSetup)
        }
        if input.status == .recording {
            return MeetingLifecycleResolution(state: .recording, destination: .recording)
        }

        switch input.analysisState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "needsmodels", "modelsrequired", "downloading", "verifying":
            return MeetingLifecycleResolution(state: .needsModels, destination: .processing)
        case "queued", "ready":
            return MeetingLifecycleResolution(state: .queued, destination: .processing)
        case "failed", "paused":
            return MeetingLifecycleResolution(state: .failed, destination: .processing)
        case "speakerreview":
            return MeetingLifecycleResolution(state: .speakerReview, destination: .processing)
        case "preparing", "transcription", "speakers", "analysis", "saving", "processing":
            return MeetingLifecycleResolution(state: .processing, destination: .processing)
        default:
            break
        }

        let hasReviewableDocument = input.hasSummary && (input.hasTranscript || input.hasTypedNotesSource)
        if hasReviewableDocument {
            if let finalized = input.finalizedFingerprint {
                let isCurrent = input.currentFingerprint == finalized
                return MeetingLifecycleResolution(
                    state: isCurrent ? .finalized : .draftReview,
                    destination: isCurrent ? .finalMinutes : .reviewChecklist
                )
            }
            if input.minutesNeedFinalization == true {
                return MeetingLifecycleResolution(state: .draftReview, destination: .reviewChecklist)
            }
            // Completed records from versions before ReviewStateStore were final.
            return MeetingLifecycleResolution(state: .finalized, destination: .finalMinutes, isLegacyFinalized: true)
        }

        if input.status == .processing || input.hasAudio || input.hasTranscript {
            return MeetingLifecycleResolution(state: .saved, destination: .processing)
        }
        return MeetingLifecycleResolution(state: .draftReview, destination: .reviewChecklist)
    }

    @MainActor
    public static func resolve(meeting: Meeting, reviewState: ReviewStateRecord?, now: Date = Date()) -> MeetingLifecycleResolution {
        let content = MinutesReviewContentSnapshot.make(from: meeting)
        return resolve(MeetingLifecycleInput(
            status: meeting.status,
            scheduledStartTime: meeting.scheduledStartTime,
            hasAudio: meeting.resolvedAudioFileURL != nil,
            hasTranscript: !meeting.transcriptSegments.isEmpty,
            hasSummary: meeting.summary != nil,
            hasTypedNotesSource: content.source == .typedNotes,
            analysisState: meeting.analysisState,
            minutesNeedFinalization: meeting.minutesNeedFinalization,
            currentFingerprint: content.fingerprint,
            finalizedFingerprint: reviewState?.finalizationFingerprint,
            now: now
        ))
    }

    @MainActor
    public static func reviewDisplayStatus(meeting: Meeting, reviewState: ReviewStateRecord?) -> String? {
        let resolution = resolve(meeting: meeting, reviewState: reviewState)
        guard resolution.state == .draftReview || resolution.state == .finalized else { return nil }
        if resolution.state == .finalized { return "Finalized" }
        let content = MinutesReviewContentSnapshot.make(from: meeting)
        let acknowledgements = reviewState?.acknowledgements(validFor: content.fingerprint) ?? []
        let checklist = MinutesReviewChecklist.evaluate(
            content: content,
            acknowledgements: acknowledgements
        )
        return checklist.canFinalize ? "Ready to finalize" : "Draft"
    }
}

public enum MinutesSourceKind: String, Codable, Sendable {
    case transcript
    case typedNotes
    case missing
}

public enum ReviewAcknowledgement: String, Codable, CaseIterable, Sendable {
    case acceptUnknownVoices
    case reviewedAgenda
    case acceptNoAgenda
    case reviewedAttendance
    case acceptNoAttendance
    case reviewedDecisions
    case acceptNoDecisions
}

public enum MinutesReviewItem: String, Codable, CaseIterable, Identifiable, Sendable {
    case source
    case speakers
    case suggestedTasks
    case agenda
    case attendance
    case decisions

    public var id: String { rawValue }
}

public struct MinutesReviewCheck: Identifiable, Sendable, Equatable {
    public var id: MinutesReviewItem { item }
    public let item: MinutesReviewItem
    public let title: String
    public let detail: String
    public let isComplete: Bool
}

public struct MinutesReviewChecklist: Sendable, Equatable {
    public let checks: [MinutesReviewCheck]
    public var canFinalize: Bool { checks.allSatisfy(\.isComplete) }
    public var outstanding: [MinutesReviewCheck] { checks.filter { !$0.isComplete } }

    public static func evaluate(content: MinutesReviewContentSnapshot,
                                acknowledgements: Set<ReviewAcknowledgement>) -> MinutesReviewChecklist {
        let hasSource = content.source != .missing
        let speakersComplete = content.source == .typedNotes || content.unknownVoiceCount == 0
            || acknowledgements.contains(.acceptUnknownVoices)
        let agendaPresent = !content.agenda.isEmpty
        let attendancePresent = !content.attendance.isEmpty
        let decisionsPresent = !content.decisions.isEmpty
        return MinutesReviewChecklist(checks: [
            MinutesReviewCheck(item: .source, title: content.source == .typedNotes ? "Typed notes source" : "Transcript",
                               detail: hasSource ? "Source content is available." : "A transcript or typed notes source is required.",
                               isComplete: hasSource),
            MinutesReviewCheck(item: .speakers, title: "Speakers",
                               detail: speakersComplete ? "Speaker identities reviewed." : "Name voices or accept unknown voices.",
                               isComplete: speakersComplete),
            MinutesReviewCheck(item: .suggestedTasks, title: "Suggested tasks",
                               detail: content.pendingTaskSuggestionCount == 0 ? "All suggestions reviewed." : "Review \(content.pendingTaskSuggestionCount) remaining suggestion\(content.pendingTaskSuggestionCount == 1 ? "" : "s").",
                               isComplete: content.pendingTaskSuggestionCount == 0),
            MinutesReviewCheck(item: .agenda, title: "Agenda",
                               detail: agendaPresent ? "Confirm the saved agenda." : "No agenda is saved; confirm that this is intentional.",
                               isComplete: acknowledgements.contains(agendaPresent ? .reviewedAgenda : .acceptNoAgenda)),
            MinutesReviewCheck(item: .attendance, title: "Attendance",
                               detail: attendancePresent ? "Confirm who was present and absent." : "No attendance is saved; confirm that this is intentional.",
                               isComplete: acknowledgements.contains(attendancePresent ? .reviewedAttendance : .acceptNoAttendance)),
            MinutesReviewCheck(item: .decisions, title: "Decisions",
                               detail: decisionsPresent ? "Confirm the recorded decisions." : "No decisions are saved; confirm that none were made.",
                               isComplete: acknowledgements.contains(decisionsPresent ? .reviewedDecisions : .acceptNoDecisions))
        ])
    }
}

/// Immutable, Sendable content used by checklist evaluation and finalization.
/// The fingerprint excludes model IDs and timestamps that do not change the reviewed document.
public struct MinutesReviewContentSnapshot: Codable, Sendable, Equatable {
    public static let typedNotesModelVersion = "Typed-Notes-v1"

    public struct TranscriptLine: Codable, Sendable, Equatable {
        public let startMilliseconds: Int64
        public let speaker: String
        public let text: String

        public init(startMilliseconds: Int64, speaker: String, text: String) {
            self.startMilliseconds = startMilliseconds
            self.speaker = speaker
            self.text = text
        }
    }
    public struct NoteLine: Codable, Sendable, Equatable {
        public let timestampMilliseconds: Int64
        public let text: String

        public init(timestampMilliseconds: Int64, text: String) {
            self.timestampMilliseconds = timestampMilliseconds
            self.text = text
        }
    }
    public struct ActionLine: Codable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let owner: String
        public let dueMilliseconds: Int64?
        public let completed: Bool

        public init(id: String, title: String, owner: String, dueMilliseconds: Int64?, completed: Bool) {
            self.id = id
            self.title = title
            self.owner = owner
            self.dueMilliseconds = dueMilliseconds
            self.completed = completed
        }
    }

    public let source: MinutesSourceKind
    public let agenda: String
    public let attendance: [String]
    public let transcript: [TranscriptLine]
    public let notes: [NoteLine]
    public let discussion: [String]
    public let decisions: [String]
    public let actions: [ActionLine]
    public let unknownVoiceCount: Int
    public let pendingTaskSuggestionCount: Int

    public init(source: MinutesSourceKind, agenda: String, attendance: [String],
                transcript: [TranscriptLine], notes: [NoteLine], discussion: [String],
                decisions: [String], actions: [ActionLine], unknownVoiceCount: Int,
                pendingTaskSuggestionCount: Int) {
        self.source = source
        self.agenda = agenda
        self.attendance = attendance
        self.transcript = transcript
        self.notes = notes
        self.discussion = discussion
        self.decisions = decisions
        self.actions = actions
        self.unknownVoiceCount = unknownVoiceCount
        self.pendingTaskSuggestionCount = pendingTaskSuggestionCount
    }

    public var fingerprint: String {
        let materialActions = actions.map { action in
            MinutesFingerprintPayload.Action(
                title: action.title,
                owner: action.owner,
                dueMilliseconds: action.dueMilliseconds,
                completed: action.completed
            )
        }.sorted { actionSortKey($0) < actionSortKey($1) }
        let payload = MinutesFingerprintPayload(
            agenda: agenda,
            attendance: attendance,
            transcript: transcript,
            notes: notes,
            discussion: discussion,
            decisions: decisions,
            actions: materialActions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func actionSortKey(_ action: MinutesFingerprintPayload.Action) -> String {
        let due = action.dueMilliseconds.map(String.init) ?? ""
        return [action.title, action.owner, due, action.completed ? "1" : "0"]
            .joined(separator: "\u{0}")
    }

    @MainActor
    public static func make(from meeting: Meeting) -> MinutesReviewContentSnapshot {
        let typedNotes = meeting.summary?.modelVersion == typedNotesModelVersion
        let transcript = meeting.orderedTranscriptSegments.map {
            TranscriptLine(startMilliseconds: milliseconds($0.startTime),
                           speaker: clean($0.speaker?.name ?? "Unknown"), text: clean($0.text))
        }
        let notes = meeting.notes.sorted {
            $0.timestamp != $1.timestamp ? $0.timestamp < $1.timestamp : $0.id.uuidString < $1.id.uuidString
        }.map { NoteLine(timestampMilliseconds: milliseconds($0.timestamp), text: clean($0.content)) }
        let absent = Set(meeting.absentParticipantIDs ?? [])
        let attendance = meeting.namedAttendees.map {
            "\(clean($0.name))|\(absent.contains($0.id) ? "absent" : "present")"
        }.sorted()
        let actions = meeting.actionItems.map {
            ActionLine(id: $0.id.uuidString, title: clean($0.title), owner: clean($0.assignee?.name ?? ""),
                       dueMilliseconds: $0.dueDate.map { milliseconds($0.timeIntervalSince1970) }, completed: $0.isCompleted)
        }.sorted { $0.id < $1.id }
        var unknown = Set<String>()
        for segment in meeting.transcriptSegments {
            guard let speaker = segment.speaker else { unknown.insert("unassigned"); continue }
            if speaker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (speaker.recordingVoiceLabel != nil && speaker.name == speaker.recordingVoiceLabel) {
                unknown.insert(speaker.id.uuidString)
            }
        }
        let source: MinutesSourceKind = typedNotes ? .typedNotes : (transcript.isEmpty ? .missing : .transcript)
        return MinutesReviewContentSnapshot(
            source: source,
            agenda: clean(meeting.agendaText ?? ""),
            attendance: attendance,
            transcript: transcript,
            notes: notes,
            discussion: ([meeting.summary?.executiveSummary].compactMap { $0 }
                + (meeting.summary?.keyPoints ?? [])).map(clean),
            decisions: decisionLines(meeting),
            actions: actions,
            unknownVoiceCount: unknown.count,
            pendingTaskSuggestionCount: meeting.pendingTaskSuggestions.count
        )
    }

    /// Each decision plus its decided-by person, so changing only the decider
    /// is a material edit that returns finalized minutes to Draft.
    @MainActor
    private static func decisionLines(_ meeting: Meeting) -> [String] {
        let decisions = meeting.summary?.keyDecisions ?? []
        let record = MeetingRecordStore.shared.record(for: meeting.id)
        return decisions.enumerated().map { index, text in
            let decider = record.decider(at: index)?.uuidString ?? ""
            return decider.isEmpty ? clean(text) : "\(clean(text))|\(decider)"
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int64 {
        guard seconds.isFinite else { return 0 }
        return Int64((seconds * 1_000).rounded())
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MinutesFingerprintPayload: Codable {
    struct Action: Codable {
        let title: String
        let owner: String
        let dueMilliseconds: Int64?
        let completed: Bool
    }

    let agenda: String
    let attendance: [String]
    let transcript: [MinutesReviewContentSnapshot.TranscriptLine]
    let notes: [MinutesReviewContentSnapshot.NoteLine]
    let discussion: [String]
    let decisions: [String]
    let actions: [Action]
}
