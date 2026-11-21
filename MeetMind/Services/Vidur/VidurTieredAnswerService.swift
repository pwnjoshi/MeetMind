import Foundation
import OfflineEngineKit

public enum VidurAnswerStage: Sendable, Equatable {
    /// A usable answer that may still be replaced.
    case instant
    /// The deep answer is being generated. `answer` holds a reliable quick answer when there is one.
    case refining
    case final
}

public enum VidurAnswerTier: Sendable, Equatable {
    case none
    /// Tier 0: read from the saved minutes, tasks, decisions, people and agenda.
    case structured
    /// Tier 1: exact transcript quotes ranked by BM25.
    case quote
    /// Tier 2: written by an on-device model from the minutes, transcript and notes.
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
    /// Minutes of other meetings in scope. They feed deep answers but not the instant structured tier.
    public let additionalFacts: [VidurMeetingFacts]
    /// Up to the last two question and answer pairs, so follow-ups such as "aur Neha ne?" work.
    public let history: [VidurChatTurn]
    /// True when the user turned off deep answers in Settings.
    public let userDisabledRefinement: Bool

    public init(question: String, sources: [VidurSourceMeeting], facts: VidurMeetingFacts?,
                length: VidurAnswerLength, allowRefinement: Bool = true,
                additionalFacts: [VidurMeetingFacts] = [], history: [VidurChatTurn] = [],
                userDisabledRefinement: Bool = false) {
        self.question = question
        self.sources = sources
        self.facts = facts
        self.length = length
        self.allowRefinement = allowRefinement && !userDisabledRefinement
        self.additionalFacts = additionalFacts
        self.history = history
        self.userDisabledRefinement = userDisabledRefinement
    }
}

/// Everything the deep answer tier needs.
public struct VidurRefineInput: Sendable {
    public let question: String
    public let sources: [VidurSourceMeeting]
    public let facts: [VidurMeetingFacts]
    public let history: [VidurChatTurn]
    public let length: VidurAnswerLength
}

/// Seams for the model-backed tier so tests run without a model.
public struct VidurTieredHooks: Sendable {
    public static let defaultRefineTimeout: TimeInterval = 8

    public var refinementAvailable: @Sendable () async -> Bool
    public var refine: @Sendable (_ input: VidurRefineInput) async throws -> VidurAnswer
    /// Seconds before the deep answer is abandoned and the quick answer is kept.
    public var refineTimeout: TimeInterval

    public init(refinementAvailable: @escaping @Sendable () async -> Bool,
                refineTimeout: TimeInterval = VidurTieredHooks.defaultRefineTimeout,
                refine: @escaping @Sendable (VidurRefineInput) async throws -> VidurAnswer) {
        self.refinementAvailable = refinementAvailable
        self.refineTimeout = refineTimeout
        self.refine = refine
    }

    public static let live = VidurTieredHooks(
        refinementAvailable: {
            if AppleIntelligenceAnswerer.isAvailable { return true }
            return await VidurAnswerService.isModelInstalled()
        },
        refine: { input in
            try await VidurTieredAnswerService.liveRefine(input)
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
        guard VidurDeepAnswerSetting.isEnabled, !AppleIntelligenceAnswerer.isAvailable,
              await VidurAnswerService.isModelInstalled() else { return }
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
        let allFacts = (request.facts.map { [$0] } ?? []) + request.additionalFacts
        guard hasTranscript || !allFacts.isEmpty else {
            emit(.init(stage: .final, tier: .none,
                       answer: VidurAnswer(text: "There is no saved transcript to search yet.", kind: .notFound)))
            return
        }

        // Tier 0: saved minutes, tasks, decisions, people.
        var structuredAnswer: VidurAnswer?
        var structuredComplete = false
        if let facts = request.facts,
           let structured = VidurStructuredAnswerer.answer(
               question: question, facts: facts,
               extraNames: request.sources.flatMap { $0.turns.compactMap(\.speaker) }) {
            structuredAnswer = VidurAnswer(text: structured.answer.text, citations: structured.answer.citations,
                                           kind: .extractive, notice: "From the minutes saved for this meeting.")
            structuredComplete = structured.isComplete
        }
        guard !Task.isCancelled else { return }

        // Tier 1: exact quotes ranked by BM25. Not needed when the minutes answer the question fully.
        var quote: VidurAnswer?
        if !structuredComplete {
            let speakers = VidurFastAnswerer.speakerFilter(question: question, sources: request.sources)
            quote = VidurFastAnswerer.answer(question: question, sources: request.sources, speakerFilter: speakers)
        }
        let best: VidurAnswer?
        let bestTier: VidurAnswerTier
        if structuredComplete { best = structuredAnswer; bestTier = .structured }
        else if let quote { best = quote; bestTier = .quote }
        else if let structuredAnswer { best = structuredAnswer; bestTier = .structured }
        else { best = nil; bestTier = .none }

        guard request.allowRefinement, await hooks.refinementAvailable() else {
            if let best {
                emit(.init(stage: .final, tier: bestTier, answer: best))
            } else if request.userDisabledRefinement {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Nothing matched in the quick search. Turn on Deep answers in Settings, Vidur, for a full search.",
                    kind: .notFound)))
            } else if !request.allowRefinement {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Minutes are still being generated, so Vidur can only use quick matches right now. Nothing matched.",
                    kind: .unavailable)))
            } else {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Vidur could not answer this question.", kind: .unavailable,
                    notice: "Vidur's local model is not downloaded. " + VidurAnswerService.unavailableHint)))
            }
            return
        }
        guard !Task.isCancelled else { return }

        // Tier 2: always runs. Minutes data the user can rely on is shown while it thinks.
        emit(.init(stage: .refining, tier: structuredComplete ? .structured : .none,
                   answer: structuredComplete ? structuredAnswer : nil))
        let input = VidurRefineInput(question: question, sources: request.sources, facts: allFacts,
                                     history: request.history, length: request.length)
        do {
            let refined = try await VidurDeadline.run(seconds: hooks.refineTimeout) { try await hooks.refine(input) }
            guard !Task.isCancelled else { return }
            if refined.kind == .notFound {
                if structuredComplete, let current = best {
                    emit(.init(stage: .final, tier: .structured, answer: current))
                } else if let current = best, bestTier == .quote {
                    let combined = VidurAnswer(
                        text: current.text, citations: current.citations, kind: current.kind,
                        notice: "Vidur's model found no direct answer. These are the closest saved lines.")
                    emit(.init(stage: .final, tier: .quote, answer: combined))
                } else if let structuredAnswer {
                    let combined = VidurAnswer(text: structuredAnswer.text + "\n\n" + refined.text,
                                               citations: structuredAnswer.citations, kind: .notFound)
                    emit(.init(stage: .final, tier: .structured, answer: combined))
                } else {
                    emit(.init(stage: .final, tier: .none, answer: refined))
                }
            } else {
                emit(.init(stage: .final, tier: refined.kind == .generated ? .generated : bestTier, answer: refined))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if let current = best {
                let kept = VidurAnswer(text: current.text, citations: current.citations, kind: current.kind,
                                       notice: "Quick answer shown. Deep answer unavailable: \(error.localizedDescription)")
                emit(.init(stage: .final, tier: bestTier, answer: kept))
            } else {
                emit(.init(stage: .final, tier: .none, answer: VidurAnswer(
                    text: "Vidur could not answer this question.", kind: .failed, notice: error.localizedDescription)))
            }
        }
    }

    // MARK: Live Tier 2

    static func maximumTokens(for length: VidurAnswerLength) -> Int {
        switch length {
        case .brief: return 140
        case .standard: return 240
        case .detailed: return 300
        }
    }

    static func maximumSentences(for length: VidurAnswerLength) -> Int {
        switch length {
        case .brief: return 2
        case .standard: return 4
        case .detailed: return 5
        }
    }

    /// A short follow-up in English ("and Neha?") keeps the language of the previous question.
    static func answerLanguage(question: String, history: [VidurChatTurn]) -> VidurAnswerLanguage {
        let detected = VidurAnswerLanguage.detect(question)
        guard detected == .english, let previous = history.last,
              VidurGroundedRetriever.terms(question).count <= 3 else { return detected }
        return VidurAnswerLanguage.detect(previous.question)
    }

    static func liveRefine(_ input: VidurRefineInput) async throws -> VidurAnswer {
        let corpus = VidurSnippetBuilder.corpus(sources: input.sources, facts: input.facts)
        let names = input.facts.flatMap { $0.participantNames + $0.tasks.compactMap(\.owner) }
        let selected = VidurGroundedRetriever.select(question: input.question, history: input.history,
                                                     corpus: corpus, names: names)
        let language = answerLanguage(question: input.question, history: input.history)
        guard !selected.isEmpty else {
            return VidurAnswer(text: VidurGroundedPrompt.notDiscussed(for: language), kind: .notFound)
        }
        if AppleIntelligenceAnswerer.isAvailable {
            do {
                return try await appleRefine(question: input.question, selected: selected, language: language)
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
        let request = VidurGroundedRequest(
            question: input.question,
            snippets: selected.map { VidurSnippet(text: $0.text, isPinned: $0.isPinned) },
            history: Array(input.history.suffix(VidurGroundedPrompt.maximumHistoryTurns)),
            language: language, maxTokens: maximumTokens(for: input.length),
            maxSentences: maximumSentences(for: input.length))
        let result = try await VidurAnswerEngine.shared.answerGrounded(request, model: VidurModel.selected)
        return try VidurGroundedAnswerBuilder.build(result: result, snippets: selected, question: input.question)
    }

    private static func appleRefine(question: String, selected: [VidurContextSnippet],
                                    language: VidurAnswerLanguage) async throws -> VidurAnswer {
        let shown = Array(selected.prefix(10))
        let reply = try await AppleIntelligenceAnswerer.answer(question: question, excerpts: shown.map(\.text))
        if AppleIntelligenceAnswerer.isNotDiscussed(reply) {
            return VidurAnswer(text: VidurGroundedPrompt.notDiscussed(for: language), kind: .notFound)
        }
        let preferred = shown.filter { $0.kind != .summary }
        let citations = (preferred.isEmpty ? shown : preferred).prefix(2).map {
            VidurGroundedAnswerBuilder.citation(from: $0, question: question)
        }
        return VidurAnswer(text: reply, citations: citations, kind: .generated,
                           notice: "Written by Apple Intelligence on this iPhone from the sources below.")
    }
}
