import Foundation

// MARK: - Process-wide processing gate

/// Process-wide "heavy analysis is running" flag.
///
/// `MeetingAnalysisPipeline` keeps its own `running` flag private, so the Vidur answer engine
/// cannot ask it directly. Whoever starts a transcription / diarization / minutes analysis run
/// should wrap it in `OfflineProcessingGate.run { ... }` (or call `begin()` / `end()`).
/// While the gate is busy `VidurAnswerEngine` refuses to answer and evicts its warm model so the
/// two never hold a language model in memory at the same time.
public enum OfflineProcessingGate {
    /// Posted (on the calling thread) every time the gate goes from idle to busy.
    public static let didBeginNotification = Notification.Name("OfflineProcessingGate.didBegin")

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var depth = 0
        func enter() -> Bool { lock.lock(); defer { lock.unlock() }; depth += 1; return depth == 1 }
        func leave() { lock.lock(); defer { lock.unlock() }; depth = max(0, depth - 1) }
        var isBusy: Bool { lock.lock(); defer { lock.unlock() }; return depth > 0 }
    }

    private static let state = State()

    public static var isProcessing: Bool { state.isBusy }

    public static func begin() {
        if state.enter() { NotificationCenter.default.post(name: didBeginNotification, object: nil) }
    }

    public static func end() { state.leave() }

    public static func run<T>(_ body: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await body()
    }
}

// MARK: - Tokenizer (English + Hinglish)

public enum VidurTokenizer {
    /// English question words plus common Hinglish function words. Content words such as
    /// "kaam", "tay" or "deadline" are intentionally absent so they still match.
    public static let stopWords: Set<String> = [
        "the", "and", "for", "are", "was", "were", "what", "when", "where", "which", "who", "whom", "why", "how",
        "did", "does", "has", "have", "had", "this", "that", "these", "those", "with", "from", "about", "into",
        "our", "your", "their", "there", "been", "will", "would", "should", "could", "can", "any", "all", "not",
        "you", "she", "his", "her", "its", "they", "them", "but", "also", "just", "then", "than", "too", "very",
        "we", "do", "of", "to", "in", "on", "it", "be", "an", "as", "at", "by", "if", "or", "so", "up", "no", "my",
        "me", "he", "am", "us", "go", "got", "get", "did", "any",
        "hai", "hain", "tha", "thi", "the", "ho", "hoga", "hogi", "honge", "raha", "rahi", "rahe",
        "ka", "ki", "ke", "ko", "se", "me", "mein", "main", "par", "pe", "ne", "kya", "kab", "kaun", "kon",
        "kisne", "kisko", "kyun", "kyu", "kaise", "kaisa", "kahan", "aur", "ya", "to", "toh", "bhi", "hi",
        "yeh", "ye", "woh", "wo", "is", "us", "isme", "usme", "mera", "meri", "hum", "humne", "aap", "tum",
        "kar", "karna", "karo", "kiya", "kia", "gaya", "gayi", "liye", "wala", "wali", "wale", "nahi", "nahin",
        // Devanagari function words. Content words stay searchable.
        "\u{0939}\u{0948}", "\u{0939}\u{0948}\u{0902}", "\u{0925}\u{093E}", "\u{0925}\u{0940}", "\u{0925}\u{0947}",
        "\u{0915}\u{093E}", "\u{0915}\u{0940}", "\u{0915}\u{0947}", "\u{0915}\u{094B}", "\u{092E}\u{0947}\u{0902}",
        "\u{0938}\u{0947}", "\u{092A}\u{0930}", "\u{0928}\u{0947}", "\u{0914}\u{0930}", "\u{092F}\u{093E}",
        "\u{0924}\u{094B}", "\u{092D}\u{0940}", "\u{0915}\u{094D}\u{092F}\u{093E}", "\u{0915}\u{092C}",
        "\u{0915}\u{094C}\u{0928}", "\u{0915}\u{093F}\u{0938}\u{0928}\u{0947}", "\u{092F}\u{0939}", "\u{0935}\u{0939}",
        "\u{0907}\u{0938}", "\u{0909}\u{0938}", "\u{0915}\u{093F}", "\u{0939}\u{092E}", "\u{0906}\u{092A}",
        "\u{092E}\u{0948}\u{0902}", "\u{0928}\u{0939}\u{0940}\u{0902}", "\u{0932}\u{093F}\u{090F}", "\u{0917}\u{092F}\u{093E}",
        "\u{0917}\u{0908}", "\u{0939}\u{0941}\u{0906}", "\u{0939}\u{0941}\u{0908}", "\u{0939}\u{094B}",
        "\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}", "\u{0915}\u{0948}\u{0938}\u{0947}", "\u{0915}\u{0939}\u{093E}\u{0901}",
        "\u{0915}\u{0939}\u{093E}\u{0902}", "\u{092C}\u{093E}\u{0930}\u{0947}"
    ]

    /// Lower-cased words with stop words removed, light suffix stripping and doubled-vowel
    /// folding, so "meeting"/"meet", "decisions"/"decision" and "kaam"/"kam", "theek"/"thik" meet.
    public static func tokens(_ text: String) -> [String] {
        var output: [String] = []
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let raw = String(word)
            guard !stopWords.contains(raw) else { continue }
            let normalized = normalize(raw)
            guard normalized.count >= 2 || (normalized.count == 1 && normalized.first?.isNumber == true) else { continue }
            output.append(normalized)
        }
        return output
    }

    static func normalize(_ word: String) -> String {
        // Only Latin words are stemmed or folded; Devanagari and digits pass through.
        guard word.unicodeScalars.allSatisfy({ $0.isASCII }), word.contains(where: { $0.isLetter }) else { return word }
        var value = word
        if value.count > 4 {
            if value.hasSuffix("ies") { value = String(value.dropLast(3)) + "y" }
            else if value.hasSuffix("sses") { value = String(value.dropLast(2)) }
            else if value.hasSuffix("s"), !value.hasSuffix("ss"), !value.hasSuffix("us"), !value.hasSuffix("is") {
                value = String(value.dropLast())
            }
        }
        if value.count > 5, value.hasSuffix("ing") { value = String(value.dropLast(3)) }
        else if value.count > 4, value.hasSuffix("ed") { value = String(value.dropLast(2)) }
        if value.count > 4, value.hasSuffix("e") { value = String(value.dropLast()) }
        // Transliteration folding: "theek"/"thik", "kaam"/"kam", "poora"/"pura".
        return value.replacingOccurrences(of: "ee", with: "i")
            .replacingOccurrences(of: "oo", with: "u")
            .replacingOccurrences(of: "aa", with: "a")
    }
}

// MARK: - BM25

public struct VidurRankedHit: Sendable, Equatable {
    public let index: Int
    public let score: Double
    public init(index: Int, score: Double) { self.index = index; self.score = score }
}

public enum VidurBM25 {
    /// Okapi BM25 over pre-tokenized documents. Returns only documents that match at least one
    /// query token, best first; ties keep document order.
    public static func rank(queryTokens: [String], documents: [[String]], limit: Int,
                            k1: Double = 1.2, b: Double = 0.75) -> [VidurRankedHit] {
        let query = Array(Set(queryTokens))
        guard !query.isEmpty, !documents.isEmpty, limit > 0 else { return [] }
        let count = Double(documents.count)
        let averageLength = max(1.0, Double(documents.reduce(0) { $0 + $1.count }) / count)
        var documentFrequency: [String: Int] = [:]
        var frequencies: [[String: Int]] = []
        frequencies.reserveCapacity(documents.count)
        let wanted = Set(query)
        for document in documents {
            var local: [String: Int] = [:]
            for token in document where wanted.contains(token) { local[token, default: 0] += 1 }
            for token in local.keys { documentFrequency[token, default: 0] += 1 }
            frequencies.append(local)
        }
        var hits: [VidurRankedHit] = []
        for (index, local) in frequencies.enumerated() where !local.isEmpty {
            let length = Double(documents[index].count)
            var score = 0.0
            for token in query {
                guard let tf = local[token].map(Double.init), let df = documentFrequency[token].map(Double.init) else { continue }
                let idf = log(1.0 + (count - df + 0.5) / (df + 0.5))
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * length / averageLength))
            }
            if score > 0 { hits.append(VidurRankedHit(index: index, score: score)) }
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return Array(hits.prefix(limit))
    }
}

// MARK: - Retrieval windows

public enum VidurRetriever {
    public static func rankTurns(question: String, turns: [AnalysisTurn], limit: Int) -> [VidurRankedHit] {
        VidurBM25.rank(queryTokens: VidurTokenizer.tokens(question),
                       documents: turns.map { VidurTokenizer.tokens($0.text) }, limit: limit)
    }

    /// Meeting prefix of ids shaped like "m3t14" so a window never straddles two meetings.
    static func meetingKey(_ id: String) -> String {
        guard id.hasPrefix("m"), let separator = id.firstIndex(of: "t") else { return "" }
        return String(id[id.startIndex..<separator])
    }

    /// The best-matching turn plus neighbours from the same meeting, at most `maxBytes` of text.
    /// A single oversized turn is cut at a word boundary; the cut text is still a substring of
    /// the original, so evidence quotes remain valid against the full turn.
    public static func window(question: String, turns: [AnalysisTurn], maxBytes: Int = 900) -> [AnalysisTurn] {
        guard let top = rankTurns(question: question, turns: turns, limit: 1).first else { return [] }
        return window(around: top.index, turns: turns, maxBytes: maxBytes)
    }

    public static func window(around index: Int, turns: [AnalysisTurn], maxBytes: Int) -> [AnalysisTurn] {
        guard turns.indices.contains(index), maxBytes > 0 else { return [] }
        let key = meetingKey(turns[index].id)
        var chosen = [clipped(turns[index], maxBytes: maxBytes)]
        var used = chosen[0].text.utf8.count
        var low = index - 1, high = index + 1
        var preferPrevious = true
        while low >= 0 || high < turns.count {
            let candidateIndex: Int
            if preferPrevious, low >= 0 { candidateIndex = low; low -= 1 }
            else if high < turns.count { candidateIndex = high; high += 1 }
            else { candidateIndex = low; low -= 1 }
            preferPrevious.toggle()
            guard candidateIndex >= 0, candidateIndex < turns.count else { continue }
            let candidate = turns[candidateIndex]
            guard meetingKey(candidate.id) == key else { continue }
            let size = candidate.text.utf8.count
            guard used + size <= maxBytes else { break }
            if candidateIndex < index { chosen.insert(candidate, at: 0) } else { chosen.append(candidate) }
            used += size
        }
        return chosen
    }

    static func clipped(_ turn: AnalysisTurn, maxBytes: Int) -> AnalysisTurn {
        guard turn.text.utf8.count > maxBytes else { return turn }
        var text = ""
        var bytes = 0
        for character in turn.text {
            let size = String(character).utf8.count
            if bytes + size > maxBytes { break }
            text.append(character)
            bytes += size
        }
        if let space = text.lastIndex(of: " "), text.distance(from: text.startIndex, to: space) > text.count / 2 {
            text = String(text[text.startIndex..<space])
        }
        return AnalysisTurn(id: turn.id, text: text, start: turn.start, end: turn.end, speaker: turn.speaker)
    }
}

// MARK: - Engine

public struct VidurEngineResult: Sendable {
    /// Points from the model whose evidence quotes were validated against `windowTurnIDs`.
    public let points: [SupportedPoint]
    public let windowTurnIDs: [String]
    /// True when an already loaded session answered (no model load happened for this call).
    public let usedWarmSession: Bool
}

/// Keeps one loaded local language model warm for chat-style questions.
///
/// - One session is cached per `model id@revision`. Folder verification goes through
///   `OfflineModelStore.verifiedFolder`, which hashes at most once per process.
/// - The session is evicted on memory warning, app background, idle timeout (3 min) and when
///   `OfflineProcessingGate` becomes busy.
/// - Each question decodes exactly one retrieved window (<= 900 transcript bytes) with the
///   compact `LocalModelConfiguration.answer` preset instead of analyzing many chunks.
public actor VidurAnswerEngine {
    public static let shared = VidurAnswerEngine()
    public static let idleTimeout: TimeInterval = 180
    public static let maximumWindowBytes = 900
    public static let maximumQuestionBytes = 300

    typealias ProfileLookup = @Sendable (VidurModel) throws -> ModelProfile
    typealias FolderResolver = @Sendable (ModelProfile) async throws -> URL
    typealias SessionMaker = @Sendable (URL) throws -> any MeetingAnalysisSession
    typealias ResourceGate = @Sendable () -> Bool
    typealias Clock = @Sendable () -> Date

    private let profileLookup: ProfileLookup
    private let folderResolver: FolderResolver
    private let sessionMaker: SessionMaker
    private let resourceGate: ResourceGate
    private let clock: Clock
    private let idleTimeoutSeconds: TimeInterval
    private let observeSystemEvents: Bool

    private var cached: (key: String, session: any MeetingAnalysisSession)?
    private var lastUsed = Date.distantPast
    private var idleTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Counters for diagnostics and tests. They contain no meeting content.
    public private(set) var sessionLoadCount = 0
    public private(set) var evictionCount = 0

    public init() {
        self.init(profileLookup: { model in
                      guard let profile = try OfflineModelStore.profiles().first(where: { $0.id == model.rawValue }) else {
                          throw OfflineError.unavailable("The offline analysis model is unavailable.")
                      }
                      return profile
                  },
                  folderResolver: { try await OfflineModelStore.shared.verifiedFolder($0) },
                  sessionMaker: { folder in
                      try LocalLanguageModel(url: folder.appendingPathComponent("model.gguf"), configuration: .answer)
                  },
                  resourceGate: { MeetingAnalysisPipeline.defaultResourceGate() },
                  clock: { Date() },
                  idleTimeout: VidurAnswerEngine.idleTimeout,
                  observeSystemEvents: true)
    }

    init(profileLookup: @escaping ProfileLookup, folderResolver: @escaping FolderResolver,
         sessionMaker: @escaping SessionMaker, resourceGate: @escaping ResourceGate = { true },
         clock: @escaping Clock = { Date() }, idleTimeout: TimeInterval = VidurAnswerEngine.idleTimeout,
         observeSystemEvents: Bool = false) {
        self.profileLookup = profileLookup
        self.folderResolver = folderResolver
        self.sessionMaker = sessionMaker
        self.resourceGate = resourceGate
        self.clock = clock
        self.idleTimeoutSeconds = idleTimeout
        self.observeSystemEvents = observeSystemEvents
    }

    public var isWarm: Bool { cached != nil }
    public var warmModelKey: String? { cached?.key }

    // MARK: Public API

    /// Answers from one retrieved window. Returns an empty result without touching the model when
    /// no transcript turn shares a word with the question.
    public func answer(question rawQuestion: String, turns: [AnalysisTurn],
                       model: VidurModel = VidurModel.selected) async throws -> VidurEngineResult {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.utf8.count <= Self.maximumQuestionBytes, !turns.isEmpty else {
            throw OfflineError.unavailable("Ask a short question after a transcript is available.")
        }
        try ensureNotProcessing()
        let window = VidurRetriever.window(question: question, turns: turns, maxBytes: Self.maximumWindowBytes)
        guard !window.isEmpty else {
            return VidurEngineResult(points: [], windowTurnIDs: [], usedWarmSession: isWarm)
        }
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        try ensureNotProcessing()
        guard resourceGate() else {
            throw OfflineError.unavailable("iPhone is too warm or in Low Power Mode. Vidur is using quick matches only.")
        }
        let (session, warm) = try await loadedSession(for: model)
        idleTask?.cancel()
        do {
            let result = try session.analyze(turns: window, meetingDate: Date(),
                                             timezone: TimeZone.current.identifier, question: question)
            lastUsed = clock()
            scheduleIdleEviction()
            return VidurEngineResult(points: result.discussion, windowTurnIDs: window.map(\.id), usedWarmSession: warm)
        } catch {
            if case OfflineError.memoryBudget = error { evict() }
            else { scheduleIdleEviction() }
            throw error
        }
    }

    /// Total prompt size (instructions, snippets, earlier chat) the engine aims for. Snippets beyond it
    /// are dropped, lowest ranked first.
    public static let groundedInputTokenBudget = 1500
    public static let maximumGroundedMaxTokens = 300

    /// Writes a direct, cited answer from numbered snippets (minutes, transcript, notes).
    ///
    /// The snippets are fitted to `groundedInputTokenBudget` using the model's own tokenizer. The
    /// model's citations are validated: ids that do not name a shown snippet are discarded.
    public func answerGrounded(_ request: VidurGroundedRequest,
                               model: VidurModel = VidurModel.selected) async throws -> VidurGroundedResult {
        let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.utf8.count <= Self.maximumQuestionBytes, !request.snippets.isEmpty else {
            throw OfflineError.unavailable("Ask a short question after a transcript is available.")
        }
        try ensureNotProcessing()
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        try ensureNotProcessing()
        guard resourceGate() else {
            throw OfflineError.unavailable("iPhone is too warm or in Low Power Mode. Vidur is using quick matches only.")
        }
        let (session, warm) = try await loadedSession(for: model)
        idleTask?.cancel()
        guard let grounded = session as? VidurGroundedSession else {
            throw OfflineError.unavailable("The loaded model cannot write answers.")
        }
        let language = request.language ?? VidurAnswerLanguage.detect(question)
        let maxTokens = min(max(request.maxTokens, 64), Self.maximumGroundedMaxTokens)
        do {
            let fitted = try VidurGroundedFitter.fit(request.snippets, budget: Self.groundedInputTokenBudget) { texts in
                try grounded.groundedTokenCount(question: question, context: texts, history: request.history,
                                                language: language, maxSentences: request.maxSentences)
            }
            let output = try grounded.answer(question: question, context: fitted.texts, language: language,
                                             maxTokens: maxTokens, history: request.history,
                                             maxSentences: request.maxSentences)
            lastUsed = clock()
            scheduleIdleEviction()
            let cited = VidurGroundedParser.citedIndices(output.citationLabels, snippetCount: fitted.kept.count)
                .map { fitted.kept[$0] }
            let notDiscussed = VidurGroundedParser.isNotDiscussed(output.answer)
            let found = output.found && !output.answer.isEmpty && !notDiscussed
            return VidurGroundedResult(
                answer: found ? output.answer : VidurGroundedPrompt.notDiscussed(for: language),
                found: found, citedIndices: found ? cited : [], keptIndices: fitted.kept, language: language,
                usedWarmSession: warm, promptTokens: fitted.tokens, truncated: output.truncated)
        } catch {
            if case OfflineError.memoryBudget = error { evict() }
            else { scheduleIdleEviction() }
            throw error
        }
    }

    /// Loads the model ahead of the first question. Best effort: returns false when it did not load.
    @discardableResult
    public func prewarm(model: VidurModel = VidurModel.selected) async -> Bool {
        guard !OfflineProcessingGate.isProcessing, resourceGate() else { return false }
        await acquire()
        defer { release() }
        guard !Task.isCancelled, !OfflineProcessingGate.isProcessing else { return false }
        do {
            _ = try await loadedSession(for: model)
            lastUsed = clock()
            scheduleIdleEviction()
            return true
        } catch { return false }
    }

    /// Drops the warm session and frees its memory.
    public func evict() {
        idleTask?.cancel()
        idleTask = nil
        guard cached != nil else { return }
        cached = nil
        evictionCount += 1
    }

    /// Evicts only when the session has been unused for the idle timeout.
    public func evictIfIdle() {
        guard cached != nil, clock().timeIntervalSince(lastUsed) >= idleTimeoutSeconds else { return }
        evict()
    }

    // MARK: Internals

    private func ensureNotProcessing() throws {
        guard !OfflineProcessingGate.isProcessing else {
            evict()
            throw OfflineError.unavailable("Vidur's model is paused while minutes are being generated.")
        }
    }

    private func loadedSession(for model: VidurModel) async throws -> (any MeetingAnalysisSession, Bool) {
        let profile = try profileLookup(model)
        let key = "\(profile.id)@\(profile.revision)"
        if let cached, cached.key == key { return (cached.session, true) }
        cached = nil // never hold two language models at once
        let folder = try await folderResolver(profile)
        try Task.checkCancellation()
        startObservingIfNeeded()
        let session = try sessionMaker(folder)
        cached = (key, session)
        sessionLoadCount += 1
        return (session, false)
    }

    private func scheduleIdleEviction() {
        idleTask?.cancel()
        let nanoseconds = UInt64(max(0, idleTimeoutSeconds) * 1_000_000_000)
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.evictIfIdle()
        }
    }

    private func startObservingIfNeeded() {
        guard observeSystemEvents, observers.isEmpty else { return }
        // UIKit names are spelled out so this file builds on macOS test hosts too.
        let names: [Notification.Name] = [
            OfflineProcessingGate.didBeginNotification,
            Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            Notification.Name("UIApplicationDidEnterBackgroundNotification")
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.evict() }
            })
        }
    }

    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}
