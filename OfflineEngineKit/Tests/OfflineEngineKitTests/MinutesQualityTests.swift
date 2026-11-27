import XCTest
@testable import OfflineEngineKit

/// Offline quality fixture for Hindi, Hinglish and English multi-speaker meetings. Each case runs through the
/// reducer twice: with an empty model result (the deterministic floor) and with noisy model output (duplicated
/// tasks, tasks invented from cancelled or refused requests). Both runs must produce exactly the expected
/// tasks, decisions and open issues, so a false positive fails as loudly as a miss.
final class MinutesQualityTests: XCTestCase {
    private struct Line {
        let speaker: String?
        let text: String
        init(_ text: String, speaker: String? = nil) { self.speaker = speaker; self.text = text }
    }

    private struct ExpectedTask {
        let keyword: String
        let owner: String?
        let deadline: String?
        let evidenceCount: Int?
        init(_ keyword: String, owner: String? = nil, deadline: String? = nil, evidence: Int? = nil) {
            self.keyword = keyword; self.owner = owner; self.deadline = deadline; self.evidenceCount = evidence
        }
    }

    private struct Case {
        let name: String
        let lines: [Line]
        var participants: [String] = []
        var speakerNames: [String: String] = [:]
        var tasks: [ExpectedTask] = []
        var decisions: [String] = []
        var openIssues: [String] = []
        /// Exact agenda topics, in order, when the case checks agenda grouping.
        var topics: [String]? = nil
        /// The first formal resolution, when the case checks resolution wording.
        var resolution: String? = nil
        var nextMeetingDate: String? = nil
        var nextMeetingTime: String? = nil
        /// A task the noisy model invents from a request that was refused or cancelled (1-based turn).
        var invented: (turn: Int, title: String, quote: String)? = nil

        init(_ name: String, _ lines: [Line]) { self.name = name; self.lines = lines }
    }

    // MARK: - Fixture

    private func cases() -> [Case] {
        var all: [Case] = []

        // 1-2. A request with owner and deadline in Hindi, confirmed by "haan".
        var c = Case("hinglish request with owner, deadline and haan", [
            Line("Neha, kya aap Friday tak report bhej sakti ho?", speaker: "A"), Line("Haan.", speaker: "B")])
        c.tasks = [ExpectedTask("report", owner: "Neha", deadline: "Friday tak", evidence: 2)]
        all.append(c)

        c = Case("devanagari request with owner, deadline and haan", [
            Line("नेहा, क्या आप शुक्रवार तक रिपोर्ट भेज सकती हो?", speaker: "A"), Line("हाँ।", speaker: "B")])
        c.tasks = [ExpectedTask("report", owner: "Neha", deadline: "शुक्रवार तक", evidence: 2)]
        all.append(c)

        // 3-4. Self-commitments resolved through the speaker's name.
        c = Case("devanagari self-commitment", [Line("मैं कल तक रिपोर्ट भेज दूँगा।", speaker: "S1")])
        c.speakerNames = ["S1": "Rahul"]
        c.tasks = [ExpectedTask("report", owner: "Rahul", deadline: "कल तक")]
        all.append(c)

        c = Case("hinglish self-commitment with an english verb", [
            Line("Main kal tak sheet update kar dunga.", speaker: "S2")])
        c.speakerNames = ["S2": "Priya"]
        c.tasks = [ExpectedTask("sheet", owner: "Priya", deadline: "kal tak")]
        all.append(c)

        // 5. Owner resolved against the participant list.
        c = Case("hinglish request canonicalizes the owner from participants", [
            Line("Neha, kya aap kal tak report bhej sakti ho?")])
        c.participants = ["Neha Sharma"]
        c.tasks = [ExpectedTask("report", owner: "Neha Sharma", deadline: "kal tak")]
        all.append(c)

        // 6. A numeric date deadline.
        c = Case("hinglish request with a date deadline", [Line("Neha, 15 December tak slides bhej dena.")])
        c.tasks = [ExpectedTask("slides", owner: "Neha", deadline: "15 December tak")]
        all.append(c)

        // 7. Declined task.
        c = Case("declined with an explanation creates nothing", [
            Line("Rahul, can you send the invoice by Friday?", speaker: "A"),
            Line("Sorry, I can't do that this week.", speaker: "B")])
        c.invented = (1, "Send the invoice", "Rahul, can you send the invoice by Friday?")
        all.append(c)

        // 8-9. Cancelled tasks, in English and in Hinglish.
        c = Case("cancelled in the next turn (english)", [
            Line("Maya, please send the vendor list by Monday.", speaker: "A"),
            Line("Actually, never mind that.", speaker: "A")])
        c.invented = (1, "Send the vendor list", "Maya, please send the vendor list by Monday.")
        all.append(c)

        c = Case("cancelled after an acceptance (hinglish)", [
            Line("Neha, report bhej dena.", speaker: "A"), Line("Haan.", speaker: "B"),
            Line("Rehne do yaar.", speaker: "A")])
        c.invented = (1, "Send the report", "Neha, report bhej dena.")
        all.append(c)

        // 10. One accepted request and one refused request in the same thread.
        c = Case("one accepted and one refused request", [
            Line("Rahul, can you book the room?", speaker: "A"), Line("Sure.", speaker: "B"),
            Line("Maya, can you send the notes?", speaker: "A"), Line("No, I can't.", speaker: "C")])
        c.tasks = [ExpectedTask("room", owner: "Rahul", evidence: 2)]
        all.append(c)

        // 11. A group commitment without a named owner is not a task.
        c = Case("group commitment without an owner creates nothing", [
            Line("Hum next week tak vendor se baat karenge.")])
        all.append(c)

        // 12-13. Decisions with a reason.
        c = Case("english decision with a reason", [Line("Let's go with Stripe because the fees are lower.")])
        c.decisions = ["stripe"]
        c.resolution = "That the Stripe be adopted (because the fees are lower)."
        all.append(c)

        c = Case("hinglish decision with a reason", [Line("Stripe final hai kyunki price kam hai.")])
        c.decisions = ["stripe"]
        c.resolution = "That the Stripe be finalized (lower price)."
        all.append(c)

        // 14. A decision not to do something.
        c = Case("decision against an action", [Line("We decided not to renew the contract.")])
        c.decisions = ["renew"]
        all.append(c)

        // 15. A hinglish decision that names a date.
        c = Case("hinglish tay hua with a date", [Line("Tay hua, demo 15 December ko rakhenge.")])
        c.decisions = ["demo"]
        all.append(c)

        // 16-17. Deferred decisions.
        c = Case("english deferral to the next meeting", [
            Line("We will defer the pricing decision to the next meeting.")])
        c.openIssues = ["defer"]
        all.append(c)

        c = Case("hinglish deferral to the next meeting", [Line("Pricing par baat agli meeting mein karenge.")])
        c.openIssues = ["pricing"]
        all.append(c)

        // 18-20. Open issues left unresolved.
        c = Case("unresolved question with pata nahi", [Line("Hiring ka budget kitna hoga, ye abhi pata nahi.")])
        c.openIssues = ["budget"]
        all.append(c)

        c = Case("devanagari undecided topic", [Line("बजट अभी तय नहीं हुआ।")])
        c.openIssues = ["budget"]
        all.append(c)

        c = Case("hinglish pending approval", [Line("Legal approval abhi pending hai.")])
        c.openIssues = ["pending"]
        all.append(c)

        // 21-22. Agenda grouping in both languages.
        c = Case("hinglish agenda statement groups its topics", [Line("Aaj hum budget aur hiring par baat karenge.")])
        c.topics = ["Budget", "Hiring"]
        all.append(c)

        c = Case("english agenda statement groups its topics", [Line("Today we will discuss budget and hiring.")])
        c.topics = ["Budget", "Hiring"]
        all.append(c)

        // 23-24. Next-meeting dates.
        c = Case("next meeting date in english", [Line("The next meeting is on Monday at 11 am.")])
        c.nextMeetingDate = "Monday"
        c.nextMeetingTime = "11 am"
        all.append(c)

        c = Case("next meeting date in hinglish", [Line("Agli meeting 25 November ko 11 baje hogi.")])
        c.nextMeetingDate = "25 November"
        c.nextMeetingTime = "11 baje"
        all.append(c)

        // 25. A short meeting that mixes agenda, request, acceptance, an open issue and a decision.
        c = Case("mini meeting with every kind of outcome", [
            Line("Today we will discuss budget and hiring.", speaker: "A"),
            Line("Rahul, can you share the hiring plan by Friday?", speaker: "A"),
            Line("Sure.", speaker: "B"),
            Line("The budget is not decided yet.", speaker: "A"),
            Line("Let's go with the agency route because it is faster.", speaker: "A")])
        c.tasks = [ExpectedTask("hiring plan", owner: "Rahul", deadline: "by Friday", evidence: 2)]
        c.decisions = ["agency route"]
        c.openIssues = ["budget"]
        c.topics = ["Budget", "Hiring"]
        all.append(c)

        return all
    }

    // MARK: - Harness

    private func turns(for testCase: Case) -> [AnalysisTurn] {
        testCase.lines.enumerated().map { index, line in
            AnalysisTurn(id: "t\(index + 1)", text: line.text, start: Double(index) * 4,
                         end: Double(index) * 4 + 3, speaker: line.speaker)
        }
    }

    private func reduce(_ testCase: Case, model: LocalAnalysisResult) -> ReducedMeetingAnalysis {
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "quality", stage: .completed,
            turns: turns(for: testCase), speakers: [], analysis: [model], analyzedChunks: 1)
        return MeetingAnalysisReducer.reduce(checkpoint, participants: testCase.participants,
                                             speakerNames: testCase.speakerNames)
    }

    private func noisyModel(for testCase: Case, floor: ReducedMeetingAnalysis) -> LocalAnalysisResult {
        var tasks: [SuggestedTask] = []
        for task in floor.tasks {
            guard let first = task.evidence.first else { continue }
            tasks.append(SuggestedTask(title: task.title, category: "Other", owner: nil, deadlineText: nil,
                                       priority: nil, evidence: [first]))
            tasks.append(SuggestedTask(title: task.title, category: task.category, owner: task.owner,
                                       deadlineText: task.deadlineText, priority: nil, evidence: [first]))
        }
        if let invented = testCase.invented {
            tasks.append(SuggestedTask(title: invented.title, category: "Create/Update", owner: "Pawan",
                deadlineText: nil, priority: nil,
                evidence: [SourceEvidence(turnID: "t\(invented.turn)", quote: invented.quote)]))
        }
        var decisions: [SupportedPoint] = []
        if testCase.decisions.isEmpty, let evidence = floor.tasks.first?.evidence.first {
            // An assignment is not a decision.
            decisions.append(SupportedPoint(text: "The team agreed on the action.", evidence: [evidence]))
        }
        return LocalAnalysisResult(discussion: [], decisions: decisions, tasks: tasks)
    }

    private func assertMatches(_ testCase: Case, _ reduced: ReducedMeetingAnalysis, label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let summary = "[\(label)] \(testCase.name): tasks=\(reduced.tasks.map { "\($0.title)|\($0.owner ?? "nil")|\($0.deadlineText ?? "nil")" }) decisions=\(reduced.decisions.map(\.text)) open=\(reduced.openIssues.map(\.text)) topics=\(reduced.agendaTopics) resolutions=\(reduced.minutes.resolutions.map(\.text)) next=\(reduced.minutes.nextMeeting?.text ?? "nil")"
        XCTAssertEqual(reduced.tasks.count, testCase.tasks.count, summary, file: file, line: line)
        let sourceTurns = turns(for: testCase)
        for expected in testCase.tasks {
            guard let found = reduced.tasks.first(where: { $0.title.lowercased().contains(expected.keyword.lowercased()) }) else {
                XCTFail("Missing task '\(expected.keyword)'. \(summary)", file: file, line: line)
                continue
            }
            XCTAssertEqual(found.owner, expected.owner, summary, file: file, line: line)
            XCTAssertEqual(found.deadlineText?.lowercased(), expected.deadline?.lowercased(), summary, file: file, line: line)
            if let count = expected.evidenceCount {
                XCTAssertEqual(found.evidence.count, count, summary, file: file, line: line)
            }
        }
        XCTAssertEqual(reduced.decisions.count, testCase.decisions.count, summary, file: file, line: line)
        for keyword in testCase.decisions {
            XCTAssertTrue(reduced.decisions.contains { $0.text.lowercased().contains(keyword.lowercased()) },
                          "Missing decision '\(keyword)'. \(summary)", file: file, line: line)
        }
        XCTAssertEqual(reduced.openIssues.count, testCase.openIssues.count, summary, file: file, line: line)
        for keyword in testCase.openIssues {
            XCTAssertTrue(reduced.openIssues.contains { $0.text.lowercased().contains(keyword.lowercased()) },
                          "Missing open issue '\(keyword)'. \(summary)", file: file, line: line)
        }
        if let topics = testCase.topics {
            XCTAssertEqual(reduced.agendaTopics, topics, summary, file: file, line: line)
        }
        if let resolution = testCase.resolution {
            XCTAssertEqual(reduced.minutes.resolutions.first?.text, resolution, summary, file: file, line: line)
        }
        if let date = testCase.nextMeetingDate {
            XCTAssertEqual(reduced.minutes.nextMeeting?.dateText, date, summary, file: file, line: line)
        }
        if let time = testCase.nextMeetingTime {
            XCTAssertEqual(reduced.minutes.nextMeeting?.timeText, time, summary, file: file, line: line)
        }
        // Every quote must be an exact substring of its cited turn.
        let evidence = reduced.tasks.flatMap(\.evidence) + reduced.decisions.flatMap(\.evidence)
            + reduced.openIssues.flatMap(\.evidence)
        for item in evidence {
            let source = sourceTurns.first { $0.id == item.turnID }?.text ?? ""
            XCTAssertTrue(source.contains(item.quote), "Ungrounded quote '\(item.quote)'. \(summary)", file: file, line: line)
        }
    }

    // MARK: - Tests

    func testFixtureCoversTheRequestedScenarios() {
        let all = cases()
        XCTAssertGreaterThanOrEqual(all.count, 25)
        XCTAssertGreaterThanOrEqual(all.filter { !$0.tasks.isEmpty }.count, 8)
        XCTAssertGreaterThanOrEqual(all.filter { !$0.decisions.isEmpty }.count, 5)
        XCTAssertGreaterThanOrEqual(all.filter { !$0.openIssues.isEmpty }.count, 5)
        XCTAssertGreaterThanOrEqual(all.filter { $0.invented != nil }.count, 3)
        XCTAssertGreaterThanOrEqual(all.filter { $0.lines.contains { HindiText.containsDevanagari($0.text) } }.count, 3)
    }

    func testDeterministicFloorWithEmptyModelOutput() {
        for testCase in cases() {
            let reduced = reduce(testCase, model: LocalAnalysisResult(discussion: [], decisions: [], tasks: []))
            assertMatches(testCase, reduced, label: "floor")
        }
    }

    func testNoisyModelOutputDoesNotChangeTheResult() {
        for testCase in cases() {
            let floor = reduce(testCase, model: LocalAnalysisResult(discussion: [], decisions: [], tasks: []))
            let noisy = reduce(testCase, model: noisyModel(for: testCase, floor: floor))
            assertMatches(testCase, noisy, label: "noisy")
        }
    }

    // MARK: - Cancellation wording

    func testWholeClauseCancellationsOnly() {
        for cancelled in ["Never mind.", "Actually, never mind that.", "Rehne do.", "Rehne do yaar.", "No need.",
                          "Forget it.", "Cancel that.", "Ok, scrap that.", "Ab zaroorat nahi hai."] {
            XCTAssertTrue(ActionExtractor.isCancellation(cancelled), cancelled)
        }
        for other in ["Rahul, cancel that booking.", "Sure, no need to remind me.", "Ok.", "No.", "I will send it.",
                      "Please cancel the hotel booking today."] {
            XCTAssertFalse(ActionExtractor.isCancellation(other), other)
        }
    }

    // MARK: - Prompt normalization and chunk efficiency

    func testPromptShowsDevanagariTurnsInRomanLetters() throws {
        let turn = AnalysisTurn(id: "t1", text: "मैं कल तक रिपोर्ट भेज दूँगा।", start: 0, end: 3, speaker: nil)
        let prompt = try LocalLanguageModel.makePrompt(turns: [turn], meetingDate: Date(), timezone: "UTC")
        let user = prompt.components(separatedBy: "<|im_start|>user")[1]
        XCTAssertFalse(HindiText.containsDevanagari(user), user)
        XCTAssertTrue(user.contains("kal tak report bhej dunga"), user)
        XCTAssertTrue(user.contains("\"id\":\"t1\"") || user.contains("\"id\" : \"t1\""), user)
    }

    func testRomanQuotesAreMappedBackToTheOriginalSentence() {
        let text = "मैं कल तक रिपोर्ट भेज दूँगा। ठीक है।"
        let turn = AnalysisTurn(id: "t1", text: text, start: 0, end: 3, speaker: nil)
        let evidence = SourceEvidence(turnID: "t1", quote: "kal tak")
        let model = LocalAnalysisResult(
            discussion: [SupportedPoint(text: "Report due tomorrow.", evidence: [evidence])], decisions: [],
            tasks: [SuggestedTask(title: "Send the report", category: "Follow-up", owner: nil, deadlineText: "kal tak",
                                  priority: nil, evidence: [evidence])])
        let restored = PromptNormalizer.restoringQuotes(in: model, original: [turn])
        XCTAssertEqual(restored.tasks.first?.evidence.first?.quote, "मैं कल तक रिपोर्ट भेज दूँगा।")
        XCTAssertEqual(restored.discussion.first?.evidence.first?.quote, "मैं कल तक रिपोर्ट भेज दूँगा।")
        // The restored quote is an exact substring, so the sanitizer keeps the task.
        XCTAssertEqual(restored.sanitized(against: [turn]).tasks.count, 1)
        // A quote the model wrote in the original script is kept as is.
        let original = SourceEvidence(turnID: "t1", quote: "ठीक है")
        let kept = PromptNormalizer.restoringQuotes(
            in: LocalAnalysisResult(discussion: [SupportedPoint(text: "Agreed.", evidence: [original])], decisions: [], tasks: []),
            original: [turn])
        XCTAssertEqual(kept.discussion.first?.evidence.first?.quote, "ठीक है")
        // A quote that exists nowhere is unchanged and the sanitizer drops it.
        let invented = SourceEvidence(turnID: "t1", quote: "send everything tomorrow")
        let dropped = PromptNormalizer.restoringQuotes(
            in: LocalAnalysisResult(discussion: [SupportedPoint(text: "Invented.", evidence: [invented])], decisions: [], tasks: []),
            original: [turn]).sanitized(against: [turn])
        XCTAssertTrue(dropped.discussion.isEmpty)
    }

    func testPiecesAlwaysConcatenateToTheOriginalText() {
        for text in ["", "Hello", "Hello. World! Is it? Yes.", "3.5 lakh. Next", "मैं कल आऊँगा। ठीक है। ok.",
                     "One. \n Two.   Three"] {
            XCTAssertEqual(PromptNormalizer.pieces(of: text).joined(), text, text)
        }
        XCTAssertEqual(PromptNormalizer.pieces(of: "A. B. C.").count, 3)
    }

    func testChunkCueDetectorSkipsOnlyChunksWithNothingToExtract() {
        func chunk(_ text: String) -> [AnalysisTurn] { [AnalysisTurn(id: "t1", text: text, start: 0, end: 2, speaker: nil)] }
        XCTAssertFalse(ChunkCueDetector.needsModel(chunk("Good morning everyone. Thanks for joining. Bye.")))
        XCTAssertFalse(ChunkCueDetector.needsModel(chunk("नमस्ते सब लोग")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("Pawan, please send the deck.")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("Who owns this?")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("कल तक भेज देना")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("Budget abhi decide nahi hua")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("The launch is on 20 November")))
        // A long stretch of speech may still hold a discussion point.
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk("The staging dashboard shows elevated latency across the European region during peak traffic.")))
        XCTAssertTrue(ChunkCueDetector.needsModel(chunk(String(repeating: "alpha ", count: 45))))
        XCTAssertFalse(ChunkCueDetector.needsModel(chunk(String(repeating: "alpha ", count: 10))))
    }

    func testOutputBudgetAndPrefixHelpers() {
        XCTAssertEqual(LocalLanguageModel.outputBudget(transcriptBytes: 100, limit: 768), 448)
        XCTAssertEqual(LocalLanguageModel.outputBudget(transcriptBytes: 600, limit: 768), 706)
        XCTAssertEqual(LocalLanguageModel.outputBudget(transcriptBytes: 1800, limit: 768), 768)
        XCTAssertEqual(LocalLanguageModel.outputBudget(transcriptBytes: 1800, limit: 300), 300)
        XCTAssertEqual(LocalLanguageModel.commonPrefixLength([1, 2, 3, 4], [1, 2, 9]), 2)
        XCTAssertEqual(LocalLanguageModel.commonPrefixLength([], [1]), 0)
        XCTAssertEqual(LocalLanguageModel.commonPrefixLength([5, 6], [5, 6]), 2)
    }

    func testResultCacheKeyFollowsPromptAndOriginalText() {
        let first = AnalysisTurn(id: "t1", text: "Pawan, send the deck.", start: 0, end: 1, speaker: nil)
        let other = AnalysisTurn(id: "t1", text: "Pawan, send the notes.", start: 0, end: 1, speaker: nil)
        let key = LocalLanguageModel.cacheKey(prompt: "p", turns: [first])
        XCTAssertEqual(key, LocalLanguageModel.cacheKey(prompt: "p", turns: [first]))
        XCTAssertNotEqual(key, LocalLanguageModel.cacheKey(prompt: "p", turns: [other]))
        XCTAssertNotEqual(key, LocalLanguageModel.cacheKey(prompt: "q", turns: [first]))
    }

    func testPromptMentionsRomanScriptAndCancellation() throws {
        let turn = AnalysisTurn(id: "t1", text: "Hello", start: 0, end: 1, speaker: nil)
        let prompt = try LocalLanguageModel.makePrompt(turns: [turn], meetingDate: Date(), timezone: "UTC")
        for needle in ["Roman letters", "rehne do", "never in decisions", "main ... dunga"] {
            XCTAssertTrue(prompt.contains(needle), needle)
        }
        XCTAssertEqual(OfflineAnalysisContract.promptVersion, "meeting-analysis-v14")
    }

    // MARK: - One model

    func testOnlyTheSmallModelRemains() throws {
        XCTAssertEqual(VidurModel.allCases, [.fast])
        XCTAssertEqual(VidurModel.fast.rawValue, "qwen-1.7b")
        XCTAssertFalse(try OfflineModelStore.profiles().contains { $0.id == "qwen-4b" })
        XCTAssertFalse(VidurModel.fast.title.contains("4B"))
    }

    func testSavedSelectionOfTheRetiredModelMigrates() {
        let suite = "VidurModelMigration-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("qwen-4b", forKey: VidurModel.preferenceKey)
        VidurModel.migrateSavedSelection(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: VidurModel.preferenceKey), "qwen-1.7b")
        defaults.removeObject(forKey: VidurModel.preferenceKey)
        VidurModel.migrateSavedSelection(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: VidurModel.preferenceKey))
    }

    func testRetiredModelFoldersAreDeletedAndOthersKept() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("retired-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["qwen-4b-0123456789ab", "qwen-4b-0123456789ab.download", "qwen-1.7b-fedcba987654", "diarization-aaaaaaaaaaaa"]
        for name in names {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: folder.appendingPathComponent("model.gguf"))
        }
        let store = OfflineModelStore(rootDirectory: root)
        let removed = await store.removeRetiredModels(ids: VidurModel.retiredModelIDs)
        XCTAssertEqual(Set(removed), ["qwen-4b-0123456789ab", "qwen-4b-0123456789ab.download"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(Set(remaining), ["qwen-1.7b-fedcba987654", "diarization-aaaaaaaaaaaa"])
        let again = await store.removeRetiredModels(ids: VidurModel.retiredModelIDs)
        XCTAssertTrue(again.isEmpty)
    }
}
