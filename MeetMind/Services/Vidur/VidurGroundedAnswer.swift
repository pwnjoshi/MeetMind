import Foundation
import OfflineEngineKit

/// User choice in Settings, Vidur, "Deep answers". On by default. Off means instant answers only, no model.
public enum VidurDeepAnswerSetting {
    public static let key = "Manent_Vidur_DeepAnswers"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

public enum VidurGroundingError: LocalizedError, Equatable {
    case uncited
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .uncited: return "Vidur could not tie its answer to the meeting."
        case .timedOut: return "Vidur took too long."
        }
    }
}

/// Turns the model's validated output into a `VidurAnswer` with source rows.
public enum VidurGroundedAnswerBuilder {
    public static let maximumCitations = 4

    public static func citation(from snippet: VidurContextSnippet, question: String) -> VidurCitation {
        if let label = snippet.kind.sourceLabel {
            return VidurCitation(meetingID: snippet.meetingID, meetingTitle: snippet.meetingTitle,
                                 timestamp: snippet.timestamp ?? 0, quote: snippet.quote, speaker: snippet.speaker,
                                 sourceLabel: label, hasTimestamp: snippet.timestamp != nil)
        }
        let quote = VidurFastAnswerer.bestSentence(in: snippet.quote, queryTokens: Set(VidurGroundedRetriever.terms(question)))
        return VidurCitation(meetingID: snippet.meetingID, meetingTitle: snippet.meetingTitle,
                             timestamp: snippet.timestamp ?? 0, quote: quote, speaker: snippet.speaker)
    }

    /// - Throws: `VidurGroundingError.uncited` when the model claims an answer but cites nothing real and
    ///   shares fewer than two content words with the snippets it saw.
    public static func build(result: VidurGroundedResult, snippets: [VidurContextSnippet], question: String) throws -> VidurAnswer {
        guard result.found else {
            return VidurAnswer(text: result.answer, kind: .notFound)
        }
        var seen = Set<String>()
        var citations: [VidurCitation] = []
        func add(_ position: Int) {
            guard snippets.indices.contains(position), citations.count < maximumCitations else { return }
            let snippet = snippets[position]
            let key = "\(snippet.kind.rawValue)|\(snippet.meetingID?.uuidString ?? "")|\(snippet.timestamp ?? -1)|\(snippet.quote)"
            guard seen.insert(key).inserted else { return }
            citations.append(citation(from: snippet, question: question))
        }
        result.citedIndices.forEach(add)
        var notice: String?
        if citations.isEmpty {
            let shown = result.keptIndices.compactMap { snippets.indices.contains($0) ? snippets[$0] : nil }
            let shownTerms = Set(shown.flatMap { VidurGroundedRetriever.terms($0.searchText) })
            let answerTerms = Set(VidurGroundedRetriever.terms(result.answer))
            guard answerTerms.intersection(shownTerms).count >= 2 else { throw VidurGroundingError.uncited }
            let preferred = result.keptIndices.filter { snippets.indices.contains($0) && snippets[$0].kind != .summary }
            (preferred.isEmpty ? result.keptIndices : preferred).prefix(2).forEach(add)
            notice = "Sources are the closest matches to this answer."
        }
        return VidurAnswer(text: result.answer, citations: citations, kind: .generated, notice: notice)
    }
}

/// Runs async work against a deadline. The caller gets control back at the deadline even if the work
/// is slow to notice cancellation; the work is cancelled either way.
enum VidurDeadline {
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    static func run<T: Sendable>(seconds: TimeInterval,
                                 _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let job = Task { try await work() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let gate = Gate()
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    if gate.claim() {
                        job.cancel()
                        continuation.resume(throwing: VidurGroundingError.timedOut)
                    }
                }
                Task {
                    do {
                        let value = try await job.value
                        if gate.claim() { timer.cancel(); continuation.resume(returning: value) }
                    } catch {
                        if gate.claim() { timer.cancel(); continuation.resume(throwing: error) }
                    }
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}
