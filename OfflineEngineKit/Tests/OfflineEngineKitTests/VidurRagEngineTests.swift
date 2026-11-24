import XCTest
@testable import OfflineEngineKit

private final class FakeRagSession: MeetingAnalysisSession, VidurRagSession, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPrompts: [String] = []
    var reply = VidurModelAnswer(answer: "Pawan has the agenda.", citationLabels: ["c2", "c9"], found: true, truncated: false)
    var inputTokenLimit: Int { 1750 }

    var prompts: [String] { lock.lock(); defer { lock.unlock() }; return storedPrompts }

    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int { 100 }

    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult {
        LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
    }

    func promptTokenCount(_ prompt: String) throws -> Int { prompt.count / 3 }

    func generateRag(prompt: String, maxTokens: Int, onText: ((String) -> Void)?) throws -> VidurModelAnswer {
        lock.lock(); storedPrompts.append(prompt); lock.unlock()
        onText?("{\"answer\":\"Pawan has")
        onText?("{\"answer\":\"Pawan has the agenda. [2]\",\"citations\":[")
        return reply
    }
}

private final class PartialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ text: String) { lock.lock(); stored.append(text); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}

final class VidurRagEngineTests: XCTestCase {
    private func makeEngine(_ session: FakeRagSession) -> VidurAnswerEngine {
        VidurAnswerEngine(
            profileLookup: { model in ModelProfile(id: model.rawValue, name: model.rawValue, revision: "r1", files: []) },
            folderResolver: { _ in URL(fileURLWithPath: "/tmp/fake-model") },
            sessionMaker: { _ in session },
            resourceGate: { true }, observeSystemEvents: false)
    }

    private func request(_ question: String = "What did we decide on launch?") -> VidurRagRequest {
        let retrieval = VidurRagTestSupport.retrieve(question)
        return VidurRagRequest(input: VidurRagPromptInput(
            question: question, userName: "Neha Sharma", now: VidurEvalFixtures.now,
            calendar: VidurEvalFixtures.calendar, retrieval: retrieval))
    }

    func testAnswerIsStreamedCleanedAndCitedAgainstTheShownBlocks() async throws {
        let session = FakeRagSession()
        let engine = makeEngine(session)
        let partials = PartialBox()
        let result = try await engine.answerRag(request(), model: .fast) { partials.add($0) }
        XCTAssertEqual(partials.values, ["Pawan has", "Pawan has the agenda."], "Block markers never reach the screen")
        XCTAssertEqual(result.answer, "Pawan has the agenda.")
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.citedBlocks, [2], "c9 does not name a shown block")
        XCTAssertGreaterThanOrEqual(result.prompt.blocks.count, 2)
        XCTAssertFalse(result.usedWarmSession)
        let prompts = session.prompts
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first, result.prompt.text)
        XCTAssertTrue(prompts[0].contains("Context blocks:"))
    }

    func testSecondQuestionReusesTheWarmModel() async throws {
        let engine = makeEngine(FakeRagSession())
        _ = try await engine.answerRag(request(), model: .fast) { _ in }
        let second = try await engine.answerRag(request("What tasks does Pawan have?"), model: .fast) { _ in }
        XCTAssertTrue(second.usedWarmSession)
        let loads = await engine.sessionLoadCount
        XCTAssertEqual(loads, 1)
    }

    func testModelSayingNotFoundGivesNoCitationsAndKeepsAnHonestLine() async throws {
        let session = FakeRagSession()
        session.reply = VidurModelAnswer(answer: "", citationLabels: ["c1"], found: false, truncated: false)
        let result = try await makeEngine(session).answerRag(request(), model: .fast) { _ in }
        XCTAssertFalse(result.found)
        XCTAssertTrue(result.citedBlocks.isEmpty)
        XCTAssertEqual(result.answer, VidurGroundedPrompt.notDiscussedEnglish)
    }

    func testRefusesWithoutRetrievedContext() async {
        let empty = VidurRagRequest(input: VidurRagPromptInput(question: "Anything?", retrieval: .empty))
        do {
            _ = try await makeEngine(FakeRagSession()).answerRag(empty, model: .fast) { _ in }
            XCTFail("Nothing was retrieved, so the model must not run")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("transcript"), error.localizedDescription)
        }
    }

    func testRefusesWhileMinutesAreBeingGenerated() async {
        OfflineProcessingGate.begin()
        defer { OfflineProcessingGate.end() }
        do {
            _ = try await makeEngine(FakeRagSession()).answerRag(request(), model: .fast) { _ in }
            XCTFail("Must refuse while the pipeline is processing")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("paused"), error.localizedDescription)
        }
    }
}
