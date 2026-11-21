import Foundation
import OfflineEngineKit

public enum VidurAnswerStage: Sendable, Equatable {
    /// A usable answer that may still be replaced.
    case instant
    /// The refined answer is being generated. `answer` holds the best answer so far, if any.
    case refining
    case final
}

public enum VidurAnswerTier: Sendable, Equatable {
    case none
    /// Tier 0: read from the saved minutes, tasks, decisions, people and agenda.
    case structured
    /// Tier 1: exact transcript quotes ranked by BM25.
    case quote
    /// Tier 2: written by an on-device model from retrieved quotes.
    case generated
}

public struct VidurAnswerUpdate: Sendable, Equatable {
    public let stage: VidurAnswerStage
    public let tier: VidurAnswerTier
    public let answer: VidurAnswer?
}

public struct VidurTieredRequest: Sendable {
    public let question: String
    public let sources: [VidurSourceMeeting]
    /// Saved structured data for the current meeting. Pass nil for series and all-meeting scopes.
    public let facts: VidurMeetingFacts?
    public let length: VidurAnswerLength
    /// False while minutes are being generated, so the language model is not loaded.
    public let allowRefinement: Bool

    public init(question: String, sources: [VidurSourceMeeting], facts: VidurMeetingFacts?,
                length: VidurAnswerLength, allowRefinement: Bool = true) {
        self.question = question
        self.sources = sources
        self.facts = facts
        self.length = length
        self.allowRefinement = allowRefinement
    }
}

/// Seams for the model-backed tier so tests run without a model.
public struct VidurTieredHooks: Sendable {
    public var refinementAvailable: @Sendable () async -> Bool
    public var refine: @Sendable (_ question: String, _ sources: [VidurSourceMeeting],
                                  _ length: VidurAnswerLength) async throws -> VidurAnswer

    public init(refinementAvailable: @escaping @Sendable () async -> Bool,
                refine: @escaping @Sendable (String, [VidurSourceMeeting], VidurAnswerLength) async throws -> VidurAnswer) {
        self.refinementAvailable = refinementAvailable
        self.refine = refine
    }

    public static let live = VidurTieredHooks(
        refinementAvailable: {
            if AppleIntelligenceAnswerer.isAvailable { return true }
            return await VidurAnswerService.isModelInstalled()
        },
        refine: { question, sources, length in
            try await VidurTieredAnswerService.liveRefine(question: question, sources: sources, length: length)
        })
}

public enum VidurTieredAnswerService {
    /// Name of the engine Tier 2 will use on this iPhone.
    public static var activeEngineName: String {
        AppleIntelligenceAnswerer.isAvailable ? "Apple Intelligence on-device" : "Qwen on-device"
    }

    public static var isAppleIntelligenceActive: Bool { AppleIntelligenceAnswerer.isAvailable }

    /// Loads the Qwen model ahead of the first question. Does nothing when Apple Intelligence is
    /// active, the model is not installed, or the device is busy.
    public static func prewarm() async {
        guard !AppleIntelligenceAnswerer.isAvailable, await VidurAnswerService.isModelInstalled() else { return }
        await VidurAnswerEngine.shared.prewarm(model: VidurModel.selected)
    }

    public static func stream(_ request: VidurTieredRequest, hooks: VidurTieredHooks = .live) -> AsyncStream<VidurAnswerUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await run(request, hooks: hooks) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func run(_ request: VidurTieredRequest, hooks: VidurTieredHooks = .live,
                           emit: @Sendable (VidurAnswerUpdate) -> Void) async {
        let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            emit(.init(stage: .final, tier: .none, answer: VidurAnswer(text: "Ask a question first.", kind: .failed)))
            return
        }
        guard question.utf8.count <= VidurAnswerService.maximumQuestionBytes else {
            emit(.init(stage: .final, tier: .none,
                       answer: VidurAnswer(text: "Ask a shorter question (300 characters or fewer).", kind: .failed)))
            return
        }
        let hasTranscript = request.sources.contains { !$0.turns.isEmpty }
        guard hasTranscript || request.facts != nil else {
            emit(.init(stage: .final, tier: .none,
                       answer: VidurAnswer(text: "There is no saved transcript to search yet.", kind: .notFound)))
            return
        }

        // Tier 0: saved minutes, tasks, decisions, people.
        var interim: VidurAnswer?
        if let facts = request.facts,
           let structured = VidurStructuredAnswerer.answer(
               question: question, facts: facts,
               extraNames: request.sources.flatMap { $0.turns.compactMap(\.speaker) }) {
            let answer = VidurAnswer(text: structured.answer.text, citations: structured.answer.citations,
                                     kind: .extractive, notice: "From the minutes saved for this meeting.")
            if structured.isComplete {
                emit(.init(stage: .final, tier: .structured, answer: answer))
                return
            }
            interim = answer
        }
        guard !Task.isCancelled else { return }

        // Tier 1: exact quotes ranked by BM25.
        let speakers = VidurFastAnswerer.speakerFilter(question: question, sources: request.sources)
        let quote = VidurFastAnswerer.answer(question: question, sources: request.sources, speakerFilter: speakers)
        var best = quote ?? interim
        var bestTier: VidurAnswerTier = quote != nil ? .quote : (interim != nil ? .structured : .none)

        guard request.allowRefinement, hasTranscript, await hooks.refinementAvailable() else {
            if let best {
                emit(.init(stage: .final, tier: bestTier, answer: best))
            } else if !request.allowRefinement {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Minutes are still being generated, so Vidur can only use quick matches right now. Nothing matched.",
                    kind: .unavailable)))
            } else if hasTranscript {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Vidur could not answer this question.", kind: .unavailable,
                    notice: "Vidur's local model is not downloaded. " + VidurAnswerService.unavailableHint)))
            } else {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(text: "Not discussed in the transcripts searched.", kind: .notFound)))
            }
            return
        }
        guard !Task.isCancelled else { return }

        // Tier 2: show the best quick answer now, then refine.
        emit(.init(stage: .refining, tier: bestTier, answer: best))
        do {
            let refined = try await hooks.refine(question, request.sources, request.length)
            guard !Task.isCancelled else { return }
            if refined.kind == .notFound, let current = best {
                let combined = VidurAnswer(
                    text: current.text, citations: current.citations, kind: current.kind,
                    notice: "Vidur's model found no direct answer. These are the closest saved lines.")
                emit(.init(stage: .final, tier: bestTier, answer: combined))
            } else if refined.kind == .notFound, let interim {
                let combined = VidurAnswer(text: interim.text + "\n\n" + refined.text, citations: interim.citations,
                                           kind: .notFound)
                emit(.init(stage: .final, tier: .structured, answer: combined))
            } else {
                emit(.init(stage: .final, tier: refined.kind == .generated ? .generated : bestTier, answer: refined))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if let current = best {
                best = VidurAnswer(text: current.text, citations: current.citations, kind: current.kind,
                                   notice: "Quick match shown. Refinement was not available: \(error.localizedDescription)")
                bestTier = quote != nil ? .quote : .structured
                emit(.init(stage: .final, tier: bestTier, answer: best))
            } else {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Vidur could not answer this question.", kind: .failed, notice: error.localizedDescription)))
            }
        }
    }

    // MARK: Live Tier 2

    static func liveRefine(question: String, sources: [VidurSourceMeeting],
                           length: VidurAnswerLength) async throws -> VidurAnswer {
        let (turns, index) = VidurAnswerService.modelTurns(for: sources)
        if AppleIntelligenceAnswerer.isAvailable {
            do {
                return try await appleRefine(question: question, turns: turns, index: index)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall through to the downloaded model when Apple Intelligence declines or fails.
                guard await VidurAnswerService.isModelInstalled() else { throw error }
            }
        }
        guard await VidurAnswerService.isModelInstalled() else {
            throw OfflineError.unavailable("Vidur's local model is not downloaded. " + VidurAnswerService.unavailableHint)
        }
        let result = try await VidurAnswerEngine.shared.answer(question: question, turns: turns, model: VidurModel.selected)
        guard !result.points.isEmpty else {
            return VidurAnswer(text: "Not discussed in the transcripts searched.", kind: .notFound)
        }
        return VidurAnswerService.validatedAnswer(points: result.points, index: index, length: length)
    }

    private static func appleRefine(question: String, turns: [AnalysisTurn],
                                    index: VidurAnswerService.TurnIndex) async throws -> VidurAnswer {
        let hits = VidurRetriever.rankTurns(question: question, turns: turns, limit: 3)
        guard !hits.isEmpty else { return VidurAnswer(text: "Not discussed in the transcripts searched.", kind: .notFound) }
        var included = Set<String>()
        var excerpts: [String] = []
        var citations: [VidurCitation] = []
        let queryTokens = Set(VidurTokenizer.tokens(question))
        for hit in hits {
            for turn in VidurRetriever.window(around: hit.index, turns: turns, maxBytes: 650) where included.insert(turn.id).inserted {
                let who = turn.speaker.map { "\($0): " } ?? ""
                excerpts.append("[\(VidurTimecode.string(turn.start))] \(who)\(turn.text)")
            }
            if citations.count < 2, let source = index[turns[hit.index].id] {
                citations.append(VidurCitation(
                    meetingID: source.meeting.id, meetingTitle: source.meeting.title, timestamp: source.turn.start,
                    quote: VidurFastAnswerer.bestSentence(in: source.turn.text, queryTokens: queryTokens),
                    speaker: source.turn.speaker))
            }
        }
        let reply = try await AppleIntelligenceAnswerer.answer(question: question, excerpts: excerpts)
        if AppleIntelligenceAnswerer.isNotDiscussed(reply) {
            return VidurAnswer(text: "Not discussed in the transcripts searched.", kind: .notFound)
        }
        return VidurAnswer(text: reply, citations: citations, kind: .generated,
                           notice: "Written by Apple Intelligence on this iPhone from the quotes below.")
    }
}
