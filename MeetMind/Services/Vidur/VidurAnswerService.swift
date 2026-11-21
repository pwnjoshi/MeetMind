import Foundation
import OfflineEngineKit

// MARK: - Value types (Sendable snapshots so no SwiftData object crosses an actor boundary)

public struct VidurSourceTurn: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let speaker: String?

    public init(text: String, start: TimeInterval, end: TimeInterval, speaker: String?) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

public struct VidurSourceMeeting: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let date: Date
    public let turns: [VidurSourceTurn]

    public init(id: UUID, title: String, date: Date, turns: [VidurSourceTurn]) {
        self.id = id
        self.title = title
        self.date = date
        self.turns = turns
    }

    @MainActor
    public static func make(from meeting: Meeting) -> VidurSourceMeeting {
        var turns = meeting.orderedTranscriptSegments.compactMap { segment -> VidurSourceTurn? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VidurSourceTurn(text: text, start: segment.startTime, end: segment.endTime,
                                   speaker: segment.speaker == nil ? nil : segment.speakerDisplayName)
        }
        // Typed notes are searchable too, so a question can be answered when audio was not transcribed.
        let notes = meeting.notes.compactMap { note -> VidurSourceTurn? in
            let text = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VidurSourceTurn(text: text, start: note.timestamp, end: note.timestamp, speaker: "Note")
        }
        if !notes.isEmpty {
            turns = (turns + notes).enumerated().sorted {
                $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset
            }.map(\.element)
        }
        return VidurSourceMeeting(id: meeting.id, title: meeting.title, date: meeting.createdAt, turns: turns)
    }
}

/// A quote from a saved transcript that backs an answer.
public struct VidurCitation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let meetingID: UUID?
    public let meetingTitle: String
    public let timestamp: TimeInterval
    public let quote: String
    public let speaker: String?
    /// "Decision", "Action", "Summary" and so on when the source is a minutes item. Nil for a transcript quote.
    public let sourceLabel: String?
    /// False for minutes items that carry no moment in the recording.
    public let hasTimestamp: Bool

    public init(id: UUID = UUID(), meetingID: UUID?, meetingTitle: String, timestamp: TimeInterval,
                quote: String, speaker: String? = nil, sourceLabel: String? = nil, hasTimestamp: Bool = true) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.timestamp = timestamp
        self.quote = quote
        self.speaker = speaker
        self.sourceLabel = sourceLabel
        self.hasTimestamp = hasTimestamp
    }

    public var timecode: String { VidurTimecode.string(timestamp) }
}

public enum VidurTimecode {
    public static func string(_ time: TimeInterval) -> String {
        let total = time.isFinite ? Int(max(0, time)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public enum VidurAnswerKind: Sendable, Equatable {
    /// Produced by the on-device model and validated against transcript quotes.
    case generated
    /// No model answer. Only transcript lines that match the question words are quoted.
    case extractive
    /// The model ran and found nothing in the searched transcripts.
    case notFound
    /// The local model is not downloaded and nothing matched by keyword.
    case unavailable
    /// The model run failed (memory, battery conditions, invalid output).
    case failed
}

public struct VidurAnswer: Sendable, Equatable {
    public let text: String
    public let citations: [VidurCitation]
    public let kind: VidurAnswerKind
    /// Truthful status line shown with the answer (for example the model route hint).
    public let notice: String?

    public init(text: String, citations: [VidurCitation] = [], kind: VidurAnswerKind, notice: String? = nil) {
        self.text = text
        self.citations = citations
        self.kind = kind
        self.notice = notice
    }

    /// Whether this answer is worth saving to Vidur history.
    public var isRecordable: Bool {
        switch kind {
        case .generated, .extractive, .notFound: return true
        case .unavailable, .failed: return false
        }
    }
}

// MARK: - Service

public enum VidurAnswerService {
    public static let unavailableHint = "Download a model in Settings \u{2192} Vidur."
    public static let maximumQuestionBytes = 300

    public typealias ModelCall = @Sendable (String, [AnalysisTurn]) async throws -> [SupportedPoint]

    /// True when the selected Vidur model has been downloaded and verified on this iPhone.
    public static func isModelInstalled() async -> Bool {
        let identifier = VidurModel.selected.rawValue
        guard let profiles = try? OfflineModelStore.profiles(),
              let profile = profiles.first(where: { $0.id == identifier }) else { return false }
        return await OfflineModelStore.shared.isInstalled(profile)
    }

    /// Answers a question from the supplied transcripts using the existing local model path.
    /// The closures exist so tests can run without a model.
    public static func answer(
        question rawQuestion: String,
        sources: [VidurSourceMeeting],
        length: VidurAnswerLength,
        modelIsInstalled: (@Sendable () async -> Bool)? = nil,
        modelCall: ModelCall? = nil
    ) async -> VidurAnswer {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return VidurAnswer(text: "Ask a question first.", kind: .failed)
        }
        guard question.utf8.count <= maximumQuestionBytes else {
            return VidurAnswer(text: "Ask a shorter question (300 characters or fewer).", kind: .failed)
        }
        guard sources.contains(where: { !$0.turns.isEmpty }) else {
            return VidurAnswer(text: "There is no saved transcript to search yet.", kind: .notFound)
        }

        let installed: Bool
        if let modelIsInstalled {
            installed = await modelIsInstalled()
        } else {
            installed = await isModelInstalled()
        }
        guard installed else {
            return fallback(question: question, sources: sources, length: length,
                            reason: "Vidur's local model is not downloaded. " + unavailableHint,
                            emptyKind: .unavailable)
        }

        let (turns, index) = modelTurns(for: sources)


        let points: [SupportedPoint]
        do {
            if let modelCall {
                points = try await modelCall(question, turns)
            } else {
                points = try await MeetingAnalysisPipeline.shared.answer(
                    question: question, turns: turns, model: VidurModel.selected)
            }
        } catch {
            return fallback(question: question, sources: sources, length: length,
                            reason: error.localizedDescription, emptyKind: .failed)
        }

        return validatedAnswer(points: points, index: index, length: length)
    }

    typealias TurnIndex = [String: (meeting: VidurSourceMeeting, turn: VidurSourceTurn)]

    /// Flattens sources into model turns ("m0t3") plus the lookup used to validate evidence.
    static func modelTurns(for sources: [VidurSourceMeeting]) -> (turns: [AnalysisTurn], index: TurnIndex) {
        var turns: [AnalysisTurn] = []
        var index: TurnIndex = [:]
        for (meetingIndex, meeting) in sources.enumerated() {
            for (turnIndex, turn) in meeting.turns.enumerated() {
                let id = "m\(meetingIndex)t\(turnIndex)"
                turns.append(AnalysisTurn(id: id, text: turn.text, start: turn.start, end: turn.end,
                                          speaker: turn.speaker))
                index[id] = (meeting, turn)
            }
        }
        return (turns, index)
    }

    /// Keeps only points whose quotes really occur in the cited transcript turn.
    static func validatedAnswer(points: [SupportedPoint], index: TurnIndex, length: VidurAnswerLength) -> VidurAnswer {
        let limit = maximumPoints(for: length)
        var keptText: [String] = []
        var citations: [VidurCitation] = []
        var seen = Set<String>()
        for point in points {
            guard keptText.count < limit else { break }
            var pointCitations: [VidurCitation] = []
            for evidence in point.evidence where !evidence.quote.isEmpty {
                let root = evidence.turnID.split(separator: ".").first.map(String.init) ?? evidence.turnID
                guard let hit = index[evidence.turnID] ?? index[root], hit.turn.text.contains(evidence.quote) else { continue }
                pointCitations.append(VidurCitation(meetingID: hit.meeting.id, meetingTitle: hit.meeting.title,
                                                    timestamp: hit.turn.start, quote: evidence.quote,
                                                    speaker: hit.turn.speaker))
            }
            guard !pointCitations.isEmpty else { continue }
            keptText.append(point.text)
            for citation in pointCitations where seen.insert("\(citation.meetingID?.uuidString ?? "")|\(citation.timestamp)|\(citation.quote)").inserted {
                citations.append(citation)
            }
        }
        guard !keptText.isEmpty else {
            return VidurAnswer(text: "Not discussed in the transcripts searched.", kind: .notFound)
        }
        return VidurAnswer(text: keptText.joined(separator: "\n"), citations: citations, kind: .generated)
    }
    static func maximumPoints(for length: VidurAnswerLength) -> Int {
        max(1, length.maxTokens / 110)
    }

    private static func fallback(question: String, sources: [VidurSourceMeeting], length: VidurAnswerLength,
                                 reason: String, emptyKind: VidurAnswerKind) -> VidurAnswer {
        let matches = extractiveCitations(question: question, sources: sources, limit: maximumPoints(for: length) + 1)
        guard !matches.isEmpty else {
            return VidurAnswer(text: "Vidur could not answer this question.", kind: emptyKind, notice: reason)
        }
        let lines = matches.map { citation -> String in
            let who = citation.speaker.map { "\($0): " } ?? ""
            return "\u{2022} [\(citation.timecode)] \(who)\(citation.quote)"
        }
        let text = "Closest transcript lines (matched by keyword, not generated):\n" + lines.joined(separator: "\n")
        return VidurAnswer(text: text, citations: matches, kind: .extractive, notice: reason)
    }

    // MARK: Extractive matching (no model)

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "was", "were", "what", "when", "where", "which", "who", "whom", "why", "how",
        "did", "does", "has", "have", "had", "this", "that", "these", "those", "with", "from", "about", "into",
        "our", "your", "their", "there", "been", "will", "would", "should", "could", "can", "any", "all", "not"
    ]

    public static func queryTerms(_ question: String) -> [String] {
        question.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    /// Transcript lines that contain the question's words, best match first. Quotes whole lines only.
    public static func extractiveCitations(question: String, sources: [VidurSourceMeeting], limit: Int) -> [VidurCitation] {
        let terms = Set(queryTerms(question))
        guard !terms.isEmpty, limit > 0 else { return [] }
        var scored: [(score: Int, order: Int, citation: VidurCitation)] = []
        var order = 0
        for meeting in sources {
            for turn in meeting.turns {
                order += 1
                let lower = turn.text.lowercased()
                var score = 0
                for term in terms where lower.contains(term) { score += 1 }
                guard score > 0 else { continue }
                let citation = VidurCitation(meetingID: meeting.id, meetingTitle: meeting.title,
                                             timestamp: turn.start, quote: turn.text, speaker: turn.speaker)
                scored.append((score, order, citation))
            }
        }
        let ranked = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return ranked.prefix(limit).map { $0.citation }
    }
}
