import Foundation
import OfflineEngineKit

public enum VidurAnswerStage: Sendable, Equatable {
    /// A usable answer that may still be replaced.
    case instant
    /// The deep answer is being written. `answer` holds the quick answer or the words written so far.
    case refining
    case final
}

public enum VidurAnswerTier: Sendable, Equatable {
    case none
    /// Tier 0: read from the saved minutes, tasks, decisions, people and agenda.
    case structured
    /// Tier 1: exact transcript quotes ranked by BM25.
    case quote
    /// Tier 2: written by an on-device model from the retrieved minutes and transcript passages.
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
    /// Up to the last four question and answer pairs, so follow-ups such as "aur Neha ne?" work.
    public let history: [VidurChatTurn]
    /// True when the user turned off deep answers in Settings.
    public let userDisabledRefinement: Bool
    /// Names the user goes by, so "my tasks" and "what do I owe" find their own tasks.
    public let selfNames: [String]

    public init(question: String, sources: [VidurSourceMeeting], facts: VidurMeetingFacts?,
                length: VidurAnswerLength, allowRefinement: Bool = true,
                additionalFacts: [VidurMeetingFacts] = [], history: [VidurChatTurn] = [],
                userDisabledRefinement: Bool = false, selfNames: [String] = [UserProfile.defaultLocalName]) {
        self.question = question
        self.sources = sources
        self.facts = facts
        self.length = length
        self.allowRefinement = allowRefinement && !userDisabledRefinement
        self.additionalFacts = additionalFacts
        self.history = history
        self.userDisabledRefinement = userDisabledRefinement
        self.selfNames = selfNames
    }
}

/// Everything the deep answer tier needs.
public struct VidurRefineInput: Sendable {
    public let question: String
    public let sources: [VidurSourceMeeting]
    public let facts: [VidurMeetingFacts]
    public let history: [VidurChatTurn]
    public let length: VidurAnswerLength
    public let selfNames: [String]
    /// Receives the reply as the model writes it. Nil when nobody is watching.
    public let onPartial: (@Sendable (String) -> Void)?
}

/// Everything the "say it naturally" step needs. The verified text comes from the saved minutes.
public struct VidurRephraseInput: Sendable {
    public let question: String
    public let sources: [VidurSourceMeeting]
    public let facts: [VidurMeetingFacts]
    public let history: [VidurChatTurn]
    public let selfNames: [String]
    public let verifiedText: String
    public let onPartial: (@Sendable (String) -> Void)?
}

/// Seams for the model-backed tier so tests run without a model.
public struct VidurTieredHooks: Sendable {
    /// Writing a cited answer takes a model load (first question only), about three seconds of prefill and
    /// up to 160 tokens of output, so the deadline is generous. Words stream to the screen meanwhile.
    public static let defaultRefineTimeout: TimeInterval = 20

    public var refinementAvailable: @Sendable () async -> Bool
    /// True when the model is loaded and the device is cool, so a quick answer can be reworded in a few seconds.
    public var rephraseAvailable: @Sendable () async -> Bool
    /// Says the verified quick answer naturally. Returns nil when the model could not do it faithfully.
    public var rephrase: @Sendable (_ input: VidurRephraseInput) async throws -> String?
    public var refine: @Sendable (_ input: VidurRefineInput) async throws -> VidurAnswer
    /// Seconds before the deep answer is abandoned and the quick answer is kept.
    public var refineTimeout: TimeInterval

    public init(refinementAvailable: @escaping @Sendable () async -> Bool,
                refineTimeout: TimeInterval = VidurTieredHooks.defaultRefineTimeout,
                rephraseAvailable: @escaping @Sendable () async -> Bool = { false },
                rephrase: @escaping @Sendable (VidurRephraseInput) async throws -> String? = { _ in nil },
                refine: @escaping @Sendable (VidurRefineInput) async throws -> VidurAnswer) {
        self.refinementAvailable = refinementAvailable
        self.refineTimeout = refineTimeout
        self.rephraseAvailable = rephraseAvailable
        self.rephrase = rephrase
        self.refine = refine
    }

    public static let live = VidurTieredHooks(
        refinementAvailable: {
            if AppleIntelligenceAnswerer.isAvailable { return true }
            return await VidurAnswerService.isModelInstalled()
        },
        rephraseAvailable: {
            await VidurTieredAnswerService.rephraseIsFast()
        },
        rephrase: { input in
            try await VidurTieredAnswerService.liveRephrase(input)
        },
        refine: { input in
            try await VidurTieredAnswerService.liveRefine(input)
        })
}

/// Lets a growing reply reach the screen word by word instead of character by character.
final class VidurStreamGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ""

    func shouldEmit(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !text.isEmpty, text != last else { return false }
        let tail = text.last ?? " "
        let boundary = tail == " " || ".,;:!?\u{0964}".contains(tail)
        guard boundary || text.count - last.count >= 8 else { return false }
        last = text
        return true
    }
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
                           emit: @escaping @Sendable (VidurAnswerUpdate) -> Void) async {
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

        // Tiers 0 and 1: saved minutes, tasks, people and transcripts of every meeting in scope.
        // Pure in-memory search, so this takes milliseconds.
        let records = VidurRecordAdapter.records(facts: allFacts, sources: request.sources)
        let quick = VidurQuickAnswerer.answer(question: question, records: records, history: request.history,
                                              selfNames: request.selfNames)
        let quickAnswer = VidurAnswer(quick: quick)
        let found = quick.confidence != .notFound
        let quickTier: VidurAnswerTier = !found ? .none : (quick.intent == .topic ? .quote : .structured)
        guard !Task.isCancelled else { return }

        // The model writes the answer when the saved data found nothing, when the question asks "why" or
        // "how", or when it is open ended ("what were the main concerns?"). Facts the minutes state
        // outright stay as they are, or are reworded naturally when the model is already warm.
        let openEnded = VidurRagRouting.isOpenEnded(question)
        let needsDeepAnswer = quick.confidence == .notFound || (quick.confidence == .partial && quick.wantsReasoning)
            || openEnded
        guard needsDeepAnswer else {
            if found, request.allowRefinement, VidurRagRouting.canRephrase(quick.text), await hooks.rephraseAvailable() {
                emit(.init(stage: .refining, tier: quickTier, answer: quickAnswer))
                let natural = await rephrased(quickAnswer: quickAnswer, question: question, request: request,
                                              facts: allFacts, hooks: hooks, emit: emit)
                guard !Task.isCancelled else { return }
                if let natural {
                    let answer = VidurAnswer(text: natural, citations: quickAnswer.citations, kind: .generated,
                                             notice: nil, people: quickAnswer.people,
                                             relatedTasks: quickAnswer.relatedTasks, suggestions: quickAnswer.suggestions)
                    emit(.init(stage: .final, tier: .generated, answer: answer))
                    return
                }
            }
            emit(.init(stage: .final, tier: quickTier, answer: quickAnswer))
            return
        }
        guard request.allowRefinement, await hooks.refinementAvailable() else {
            let notice: String?
            if request.userDisabledRefinement {
                notice = "Turn on Deep answers in Settings, Vidur, for a full search."
            } else if !request.allowRefinement {
                notice = "Minutes are still being generated, so Vidur could only use quick matches."
            } else if found {
                notice = nil
            } else {
                notice = "Vidur's local model is not downloaded. " + VidurAnswerService.unavailableHint
            }
            emit(.init(stage: .final, tier: quickTier, answer: quickAnswer.withNotice(notice)))
            return
        }
        guard !Task.isCancelled else { return }

        // Tier 2: the model reads the best minutes and transcript passages. A reliable quick answer stays on
        // screen while it works; an open ended question shows the search animation instead.
        emit(.init(stage: .refining, tier: quickTier, answer: (found && !openEnded) ? quickAnswer : nil))
        let gate = VidurStreamGate()
        let input = VidurRefineInput(
            question: question, sources: request.sources, facts: allFacts, history: request.history,
            length: request.length, selfNames: request.selfNames,
            onPartial: { partial in
                guard gate.shouldEmit(partial) else { return }
                emit(.init(stage: .refining, tier: .generated, answer: VidurAnswer(text: partial, kind: .generated)))
            })
        do {
            let refined = try await VidurDeadline.run(seconds: hooks.refineTimeout) { try await hooks.refine(input) }
            guard !Task.isCancelled else { return }
            if refined.kind == .notFound {
                let notice = found ? "Vidur\u{2019}s model found nothing more in your meetings."
                : "Searched the saved minutes and transcripts with the on-device model."
                emit(.init(stage: .final, tier: quickTier, answer: quickAnswer.withNotice(notice)))
            } else {
                emit(.init(stage: .final, tier: refined.kind == .generated ? .generated : quickTier, answer: refined))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let kept = quickAnswer.withNotice("Quick answer shown. Deep answer unavailable: \(error.localizedDescription)")
            emit(.init(stage: .final, tier: quickTier, answer: kept))
        }
    }

    /// Asks the model to say the verified quick answer naturally. Nil keeps the saved wording.
    private static func rephrased(quickAnswer: VidurAnswer, question: String, request: VidurTieredRequest,
                                  facts: [VidurMeetingFacts], hooks: VidurTieredHooks,
                                  emit: @escaping @Sendable (VidurAnswerUpdate) -> Void) async -> String? {
        let gate = VidurStreamGate()
        let input = VidurRephraseInput(
            question: question, sources: request.sources, facts: facts, history: request.history,
            selfNames: request.selfNames, verifiedText: quickAnswer.text,
            onPartial: { partial in
                guard gate.shouldEmit(partial) else { return }
                emit(.init(stage: .refining, tier: .generated,
                           answer: VidurAnswer(text: partial, citations: quickAnswer.citations, kind: .generated,
                                               people: quickAnswer.people, relatedTasks: quickAnswer.relatedTasks)))
            })
        do {
            let seconds = min(hooks.refineTimeout, 12)
            return try await VidurDeadline.run(seconds: seconds) { try await hooks.rephrase(input) }
        } catch {
            return nil
        }
    }

    // MARK: Live Tier 2

    /// A reworded answer is only worth it when the model is already loaded and the iPhone is cool and not in
    /// Low Power Mode. Then it takes about five seconds. Otherwise the saved wording is shown at once.
    static func rephraseIsFast() async -> Bool {
        guard VidurDeepAnswerSetting.isEnabled, !AppleIntelligenceAnswerer.isAvailable else { return false }
        let info = ProcessInfo.processInfo
        guard !info.isLowPowerModeEnabled,
              info.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else { return false }
        return await VidurAnswerEngine.shared.isWarm
    }

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

    /// The saved meetings as one search index, rebuilt only when their content changes, and the best
    /// chunks and facts for this question.
    static func ragRetrieval(question: String, sources: [VidurSourceMeeting], facts: [VidurMeetingFacts],
                             history: [VidurChatTurn], selfNames: [String], limit: Int) -> VidurRagRetrieval {
        let records = VidurRecordAdapter.records(facts: facts, sources: sources)
        let index = VidurRagIndexCache.index(for: records)
        return VidurRagRetriever.retrieve(
            VidurRagQuery(question: question, history: history, selfNames: selfNames, limit: limit), index: index)
    }

    static func liveRefine(_ input: VidurRefineInput) async throws -> VidurAnswer {
        let language = answerLanguage(question: input.question, history: input.history)
        if AppleIntelligenceAnswerer.isAvailable {
            let corpus = VidurSnippetBuilder.corpus(sources: input.sources, facts: input.facts)
            let names = input.facts.flatMap { $0.participantNames + $0.tasks.compactMap(\.owner) }
            let selected = VidurGroundedRetriever.select(question: input.question, history: input.history,
                                                         corpus: corpus, names: names)
            guard !selected.isEmpty else {
                return VidurAnswer(text: VidurGroundedPrompt.notDiscussed(for: language), kind: .notFound)
            }
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
        return try await ragRefine(input, language: language)
    }

    /// Retrieval augmented answer: index, hybrid retrieval, a fitted prompt, streamed generation, and sources
    /// taken from the blocks the model cited.
    static func ragRefine(_ input: VidurRefineInput, language: VidurAnswerLanguage) async throws -> VidurAnswer {
        let retrieval = ragRetrieval(question: input.question, sources: input.sources, facts: input.facts,
                                     history: input.history, selfNames: input.selfNames,
                                     limit: VidurRagRetriever.defaultLimit)
        guard !retrieval.isEmpty else {
            return VidurAnswer(text: VidurGroundedPrompt.notDiscussed(for: language), kind: .notFound)
        }
        let promptInput = VidurRagPromptInput(
            question: input.question, history: input.history, userName: input.selfNames.first ?? "", now: Date(),
            retrieval: retrieval, language: language)
        let result = try await VidurAnswerEngine.shared.answerRag(
            VidurRagRequest(input: promptInput), model: VidurModel.selected) { partial in
                input.onPartial?(partial)
            }
        guard result.found else { return VidurAnswer(text: result.answer, kind: .notFound) }
        let sources = VidurRagCitations.sources(for: result)
        let citations = sources.items.map { source in
            VidurCitation(meetingID: source.meetingID, meetingTitle: source.meetingTitle,
                          timestamp: source.timestamp ?? 0, quote: source.quote, speaker: source.speaker,
                          sourceLabel: source.label, hasTimestamp: source.timestamp != nil)
        }
        guard !citations.isEmpty else { throw VidurGroundingError.uncited }
        var notices: [String] = []
        if sources.inferred { notices.append("Sources are the closest matches to this answer.") }
        if !VidurRagGuard.isFaithful(answer: result.answer, evidence: [result.prompt.user] + input.selfNames) {
            notices.append("Check the sources: a detail may not match your meetings.")
        }
        return VidurAnswer(text: result.answer, citations: citations, kind: .generated,
                           notice: notices.isEmpty ? nil : notices.joined(separator: " "))
    }

    /// Says a verified quick answer naturally. Returns nil unless the reworded text keeps every fact.
    static func liveRephrase(_ input: VidurRephraseInput) async throws -> String? {
        guard await VidurAnswerService.isModelInstalled() else { return nil }
        let retrieval = ragRetrieval(question: input.question, sources: input.sources, facts: input.facts,
                                     history: input.history, selfNames: input.selfNames, limit: 3)
        guard !retrieval.isEmpty else { return nil }
        let language = answerLanguage(question: input.question, history: input.history)
        let promptInput = VidurRagPromptInput(
            question: input.question, history: input.history, userName: input.selfNames.first ?? "", now: Date(),
            retrieval: retrieval, language: language, verifiedAnswer: input.verifiedText)
        let result = try await VidurAnswerEngine.shared.answerRag(
            VidurRagRequest(input: promptInput), model: VidurModel.selected) { partial in
                input.onPartial?(partial)
            }
        guard result.found, !result.truncated else { return nil }
        let evidence = [result.prompt.user] + input.selfNames
        guard VidurRagGuard.isFaithful(answer: result.answer, evidence: evidence),
              VidurRagGuard.keepsFacts(answer: result.answer, verified: input.verifiedText) else { return nil }
        return result.answer
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
