import XCTest
@testable import OfflineEngineKit

private final class FakeAnswerSession: MeetingAnalysisSession {
    var inputTokenLimit: Int { 1400 }
    private(set) var windows: [[AnalysisTurn]] = []
    var failure: Error?

    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int { 100 }

    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        windows.append(turns)
        if let failure { throw failure }
        let turn = turns[0]
        let point = SupportedPoint(text: "Answer from \(turn.id)",
                                   evidence: [SourceEvidence(turnID: turn.id, quote: String(turn.text.prefix(8)))])
        return LocalAnalysisResult(discussion: [point], decisions: [], tasks: [])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    private(set) var sessions: [FakeAnswerSession] = []
    func make() -> FakeAnswerSession {
        lock.lock(); defer { lock.unlock() }
        loads += 1
        let session = FakeAnswerSession()
        sessions.append(session)
        return session
    }
    var loadCount: Int { lock.lock(); defer { lock.unlock() }; return loads }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}

final class VidurAnswerEngineTests: XCTestCase {
    private let turns = [
        AnalysisTurn(id: "t0", text: "Welcome everyone to the weekly sync.", start: 0, end: 4, speaker: "Asha"),
        AnalysisTurn(id: "t1", text: "Pricing page launch moves to Friday because legal review is pending.", start: 5, end: 12, speaker: "Rahul"),
        AnalysisTurn(id: "t2", text: "Rahul will send the revised quote kal tak.", start: 13, end: 18, speaker: "Asha")
    ]

    private func profile(_ id: String, revision: String = "r1") -> ModelProfile {
        ModelProfile(id: id, name: id, revision: revision, files: [])
    }

    private func makeEngine(counter: Counter, clock: MutableClock = MutableClock(), idle: TimeInterval = 180,
                            revision: @escaping @Sendable () -> String = { "r1" },
                            gate: @escaping @Sendable () -> Bool = { true }) -> VidurAnswerEngine {
        VidurAnswerEngine(
            profileLookup: { model in ModelProfile(id: model.rawValue, name: model.rawValue, revision: revision(), files: []) },
            folderResolver: { _ in URL(fileURLWithPath: "/tmp/fake-model") },
            sessionMaker: { _ in counter.make() },
            resourceGate: gate, clock: { clock.now }, idleTimeout: idle, observeSystemEvents: false)
    }

    func testSecondQuestionReusesWarmSession() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        let first = try await engine.answer(question: "When does the pricing page launch?", turns: turns, model: .fast)
        let second = try await engine.answer(question: "Who sends the quote?", turns: turns, model: .fast)
        XCTAssertFalse(first.usedWarmSession)
        XCTAssertTrue(second.usedWarmSession)
        XCTAssertEqual(counter.loadCount, 1)
        let warm = await engine.isWarm
        XCTAssertTrue(warm)
    }

    func testChangingModelOrRevisionReplacesSession() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .large)
        XCTAssertEqual(counter.loadCount, 2)
        let key = await engine.warmModelKey
        XCTAssertEqual(key, "qwen-4b@r1")
    }

    func testEvictionForcesReload() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        await engine.evict()
        let warm = await engine.isWarm
        XCTAssertFalse(warm)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        XCTAssertEqual(counter.loadCount, 2)
        let evictions = await engine.evictionCount
        XCTAssertEqual(evictions, 1)
    }

    func testIdleEvictionOnlyAfterTimeout() async throws {
        let counter = Counter()
        let clock = MutableClock()
        let engine = makeEngine(counter: counter, clock: clock, idle: 180)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        clock.advance(120)
        await engine.evictIfIdle()
        var warm = await engine.isWarm
        XCTAssertTrue(warm)
        clock.advance(61)
        await engine.evictIfIdle()
        warm = await engine.isWarm
        XCTAssertFalse(warm)
    }

    func testIdleTimerEvictsWithoutManualCall() async throws {
        let counter = Counter()
        let engine = VidurAnswerEngine(
            profileLookup: { model in ModelProfile(id: model.rawValue, name: "x", revision: "r1", files: []) },
            folderResolver: { _ in URL(fileURLWithPath: "/tmp/fake-model") },
            sessionMaker: { _ in counter.make() }, idleTimeout: 0.05)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        for _ in 0..<60 {
            let stillWarm = await engine.isWarm
            if !stillWarm { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let warm = await engine.isWarm
        XCTAssertFalse(warm)
    }

    func testRefusesWhileProcessingAndEvictsWarmSession() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        OfflineProcessingGate.begin()
        defer { OfflineProcessingGate.end() }
        do {
            _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
            XCTFail("Must refuse while the pipeline is processing")
        } catch { XCTAssertTrue(error.localizedDescription.contains("paused")) }
        let warm = await engine.isWarm
        XCTAssertFalse(warm)
    }

    func testResourceGateBlocksModelLoad() async {
        let counter = Counter()
        let engine = makeEngine(counter: counter, gate: { false })
        do {
            _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
            XCTFail("Must not load when the device is too warm")
        } catch { XCTAssertEqual(counter.loadCount, 0) }
    }

    func testUnmatchedQuestionNeverLoadsModel() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        let result = try await engine.answer(question: "Which vendor hosts the database?", turns: turns, model: .fast)
        XCTAssertTrue(result.points.isEmpty)
        XCTAssertEqual(counter.loadCount, 0)
    }

    func testAnswerUsesSingleBoundedWindow() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        let filler = String(repeating: "filler words here ", count: 6)
        let long: [AnalysisTurn] = (0..<40).map { (index: Int) -> AnalysisTurn in
            let suffix = index == 20 ? "budget approval" : ""
            return AnalysisTurn(id: "t\(index)", text: filler + suffix,
                                start: Double(index), end: Double(index + 1), speaker: nil)
        }
        let result = try await engine.answer(question: "budget approval", turns: long, model: .fast)
        XCTAssertTrue(result.windowTurnIDs.contains("t20"))
        let bytes = long.filter { result.windowTurnIDs.contains($0.id) }.reduce(0) { $0 + $1.text.utf8.count }
        XCTAssertLessThanOrEqual(bytes, VidurAnswerEngine.maximumWindowBytes)
        XCTAssertEqual(counter.sessions.first?.windows.count, 1)
    }

    func testMemoryErrorEvictsSession() async throws {
        let counter = Counter()
        let engine = makeEngine(counter: counter)
        _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast)
        counter.sessions[0].failure = OfflineError.memoryBudget(requiredEstimate: 10, budget: 5)
        do { _ = try await engine.answer(question: "pricing page", turns: turns, model: .fast) } catch {}
        let warm = await engine.isWarm
        XCTAssertFalse(warm)
    }

    func testAnswerPresetIsCompact() {
        XCTAssertEqual(LocalModelConfiguration.answer.outputTokens, 160)
        XCTAssertEqual(LocalModelConfiguration.answer.contextTokens, 2048)
        XCTAssertLessThan(Int(LocalModelConfiguration.answer.inputTokens) + LocalModelConfiguration.answer.outputTokens,
                          Int(LocalModelConfiguration.answer.contextTokens))
    }
}

final class VidurRetrievalTests: XCTestCase {
    func testHinglishTokenizationKeepsContentWordsAndDropsFunctionWords() {
        let tokens = VidurTokenizer.tokens("Pricing page ka launch kab hai? Rahul ne kal tak quote bhejna hai")
        XCTAssertTrue(tokens.contains(VidurTokenizer.tokens("pricing")[0]))
        XCTAssertTrue(tokens.contains(VidurTokenizer.tokens("launch")[0]))
        XCTAssertTrue(tokens.contains(VidurTokenizer.tokens("rahul")[0]))
        XCTAssertTrue(tokens.contains(VidurTokenizer.tokens("kal")[0]))
        XCTAssertFalse(tokens.contains("ka"))
        XCTAssertFalse(tokens.contains("hai"))
        XCTAssertFalse(tokens.contains("kab"))
    }

    func testSpellingVariantsAndInflectionsMeet() {
        XCTAssertEqual(VidurTokenizer.tokens("theek")[0], VidurTokenizer.tokens("thik")[0])
        XCTAssertEqual(VidurTokenizer.tokens("kaam")[0], VidurTokenizer.tokens("kam")[0])
        XCTAssertEqual(VidurTokenizer.tokens("decisions")[0], VidurTokenizer.tokens("decision")[0])
        XCTAssertEqual(VidurTokenizer.tokens("meetings")[0], VidurTokenizer.tokens("meeting")[0])
        XCTAssertEqual(VidurTokenizer.tokens("decided")[0], VidurTokenizer.tokens("deciding")[0])
    }

    func testDevanagariWordsSurviveTokenization() {
        XCTAssertEqual(VidurTokenizer.tokens("कल मीटिंग"), ["कल", "मीटिंग"])
    }

    func testBM25PrefersRareTermsAndShortFocusedDocuments() {
        let docs = [
            "the team talked about the budget and the schedule and many other things in the review",
            "budget",
            "schedule schedule review review"
        ].map(VidurTokenizer.tokens)
        let hits = VidurBM25.rank(queryTokens: VidurTokenizer.tokens("budget"), documents: docs, limit: 3)
        XCTAssertEqual(hits.map(\.index), [1, 0])
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    func testBM25ReturnsNothingWhenNoTermMatches() {
        let docs = [VidurTokenizer.tokens("hello there")]
        XCTAssertTrue(VidurBM25.rank(queryTokens: ["zebra"], documents: docs, limit: 3).isEmpty)
    }

    func testRankTurnsFindsHinglishTurn() {
        let turns = [
            AnalysisTurn(id: "t0", text: "Aaj ka agenda budget aur hiring hai", start: 0, end: 3, speaker: nil),
            AnalysisTurn(id: "t1", text: "Vendor payment agle hafte tak clear karna hai", start: 4, end: 8, speaker: nil)
        ]
        let hits = VidurRetriever.rankTurns(question: "Vendor payment kab tak clear hoga?", turns: turns, limit: 2)
        XCTAssertEqual(hits.first?.index, 1)
    }

    func testWindowStaysInsideOneMeetingAndByteBudget() {
        let turns = [
            AnalysisTurn(id: "m0t0", text: "Other meeting talked about the roadmap", start: 0, end: 1, speaker: nil),
            AnalysisTurn(id: "m1t0", text: "Roadmap review is on Monday", start: 0, end: 1, speaker: nil),
            AnalysisTurn(id: "m1t1", text: "Everyone agreed", start: 1, end: 2, speaker: nil)
        ]
        let window = VidurRetriever.window(question: "roadmap review", turns: turns, maxBytes: 900)
        XCTAssertEqual(window.map(\.id), ["m1t0", "m1t1"])
    }

    func testOversizedTurnIsClippedToSubstring() {
        let text = String(repeating: "alpha beta gamma ", count: 200) + "needle"
        let turns = [AnalysisTurn(id: "t0", text: text, start: 0, end: 1, speaker: nil)]
        let window = VidurRetriever.window(question: "alpha", turns: turns, maxBytes: 900)
        XCTAssertEqual(window.count, 1)
        XCTAssertLessThanOrEqual(window[0].text.utf8.count, 900)
        XCTAssertTrue(text.contains(window[0].text))
    }
}
