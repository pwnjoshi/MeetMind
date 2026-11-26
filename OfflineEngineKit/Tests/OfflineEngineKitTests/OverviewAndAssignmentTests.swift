import XCTest
@testable import OfflineEngineKit

/// Indirect task assignments ("I would recommend that Meera ...") and the deterministic overview.
/// All text is synthetic.
final class OverviewAndAssignmentTests: XCTestCase {
    private func checkpoint(turns: [AnalysisTurn], analysis: [LocalAnalysisResult] = []) -> MeetingAnalysisCheckpoint {
        MeetingAnalysisCheckpoint(sourceSignature: "fixture", stage: .completed, turns: turns,
                                  speakers: [], analysis: analysis, analyzedChunks: analysis.count)
    }

    private func turn(_ id: String, _ text: String) -> AnalysisTurn {
        AnalysisTurn(id: id, text: text, start: 0, end: 1, speaker: nil)
    }

    // MARK: - Indirect assignments

    func testRecommendationAssignsTheNamedPersonWithoutAnyModelTask() throws {
        let sentence = "However, I would recommend that Meera goes further on the checkout flow and looks for some good examples of rival apps."
        let turns = [turn("t0", "The checkout flow needs a cleaner layout."), turn("t1", sentence)]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns), participants: ["Meera", "Dev"])
        let task = try XCTUnwrap(reduced.tasks.first { $0.owner == "Meera" })
        XCTAssertEqual(task.title, "Go further on the checkout flow and look for some good examples of rival apps")
        XCTAssertEqual(task.evidence.first?.turnID, "t1")
        XCTAssertTrue(sentence.contains(task.evidence.first?.quote ?? "missing"))
    }

    func testRecommendationVariantsAndShouldAssignTheNamedPerson() throws {
        let turns = [
            turn("a", "We suggest that Dev reviews the pricing draft by Friday."),
            turn("b", "Meera should update the onboarding checklist.")
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns), participants: ["Meera", "Dev"])
        let dev = try XCTUnwrap(reduced.tasks.first { $0.owner == "Dev" })
        XCTAssertEqual(dev.title, "Review the pricing draft")
        XCTAssertEqual(dev.deadlineText?.lowercased(), "by friday")
        let meera = try XCTUnwrap(reduced.tasks.first { $0.owner == "Meera" })
        XCTAssertEqual(meera.title, "Update the onboarding checklist")
    }

    func testNegatedOrDescriptiveRecommendationsMakeNoTask() {
        let lines = [
            "I would not recommend that Meera goes further on the checkout flow.",
            "I wouldn't recommend that Dev reviews the pricing draft.",
            "Meera should not update the onboarding checklist.",
            "Meera is doing research on rival apps.",
            "I would recommend that we ship the beta next month."
        ]
        let turns = lines.enumerated().map { turn("t\($0.offset)", $0.element) }
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns), participants: ["Meera", "Dev"])
        XCTAssertTrue(reduced.tasks.isEmpty, "\(reduced.tasks.map(\.title))")
    }

    func testVocativeContinueAssignmentsAreStillFound() {
        let turns = [
            turn("a", "Meera, you continue with the interview notes."),
            turn("b", "Dev, you can continue with your pricing research.")
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns), participants: ["Meera", "Dev"])
        XCTAssertEqual(reduced.tasks.compactMap(\.owner), ["Meera", "Dev"])
    }

    // MARK: - Chunk boundaries

    func testAssignmentSurvivesWhenItsContextIsInAnotherChunk() throws {
        var turns = (0..<46).map { turn("t\($0)", "Item \($0) on the shared checklist was discussed briefly.") }
        turns[24] = turn("t24", "The prototype still has gaps in the checkout flow.")
        turns[25] = turn("t25", "However, I would recommend that Priya goes further on the checkout flow and looks for strong examples of rival apps.")

        let chunks = MeetingAnalysisPipeline.analysisChunks(turns, maxJSONBytes: MeetingAnalysisPipeline.analysisChunkBytes)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(Set(chunks.flatMap { $0.map(\.id) }), Set(turns.map(\.id)), "no turn is dropped")
        // Each chunk repeats the last turn of the one before it, so the context turn and the
        // recommendation always share a chunk.
        XCTAssertTrue(chunks.contains { chunk in
            let ids = chunk.map(\.id)
            return ids.contains("t24") && ids.contains("t25")
        })
        func reduce(_ plan: [[AnalysisTurn]]) -> [SuggestedTask] {
            var saved = checkpoint(turns: turns, analysis: plan.map { _ in LocalAnalysisResult(discussion: [], decisions: [], tasks: []) })
            saved.chunkTurnIDs = plan.map { $0.map(\.id) }
            return MeetingAnalysisReducer.reduce(saved, participants: ["Priya", "Dev"]).tasks
        }
        // The planned chunks, and the worst case where the recommendation opens a new chunk.
        let worst = [Array(turns[..<25]), Array(turns[25...])]
        for plan in [chunks, worst] {
            let found = reduce(plan).first { $0.owner == "Priya" }
            XCTAssertEqual(found?.evidence.first?.turnID, "t25")
        }
    }

    // MARK: - Overview

    private let overviewTurns = [
        "And then we can organically grow it using the shared component library.",
        "Meera has been testing the checkout prototype with early users.",
        "Revenue forecasts depend on the pilot results from two retailers.",
        "Dev, please send the pricing draft by Friday."
    ]
    private let copied = "And then we can organically grow it using the shared component library."
    private let namesMeera = "Meera is running early user trials of the checkout prototype."
    private let good = "Forecasting revenue hinges on how the retailer pilots turn out."

    private func overviewCheckpoint() -> MeetingAnalysisCheckpoint {
        let turns = overviewTurns.enumerated().map { turn("t\($0.offset)", $0.element) }
        func point(_ text: String, _ index: Int) -> SupportedPoint {
            SupportedPoint(text: text, evidence: [SourceEvidence(turnID: turns[index].id, quote: turns[index].text)])
        }
        let discussion = [point(copied, 0), point(namesMeera, 1), point(good, 2)]
        var saved = checkpoint(turns: turns, analysis: [LocalAnalysisResult(discussion: discussion, decisions: [], tasks: [])])
        saved.rankedOverviewFacts = discussion
        return saved
    }

    func testOverviewGroupsFollowUpsAndKeepsTimingQuestionOpen() {
        let turns = [
            turn("timing", "During the recording, should we do the processing part or do all the things later on?"),
            turn("flow", "I would recommend that Vaishnavi goes further on the user flow and looks for some good designs of competitor apps."),
            turn("models", "Aditya, you can continue focusing more on the models, right, which is more suitable and accurate."),
            turn("audience", "Garima, you continue your research and narrow down your user segment."),
            turn("poc", "Pawan, please continue with the POC.")
        ]
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "overview", stage: .completed,
            turns: turns, speakers: [], analysis: [], analyzedChunks: 0)
        let result = MeetingAnalysisReducer.reduce(checkpoint)
        XCTAssertTrue(result.executiveSummary.contains("whether to process audio during recording or afterward"))
        XCTAssertTrue(result.executiveSummary.contains("Next steps are to"))
        XCTAssertFalse(result.executiveSummary.contains("Vaishnavi will"))
        XCTAssertEqual(Set(result.minutes.actions.compactMap(\.owner)), ["Vaishnavi", "Aditya", "Garima", "Pawan"])
        XCTAssertTrue(result.decisions.isEmpty)
    }

    func testOverviewKeepsOneCleanContextSentenceAndNamesNobodyWithoutATask() {
        let reduced = MeetingAnalysisReducer.reduce(overviewCheckpoint(), participants: ["Meera", "Dev"])
        let statements = reduced.minutes.summaryStatements.map(\.text)
        let contexts = statements.filter { [copied, namesMeera, good].contains($0) }
        XCTAssertEqual(contexts, [good])
        for statement in statements {
            XCTAssertNil(MinutesRegex.firstMatch(#"(?i)^(?:and|so|also|but|then)\b"#, in: statement), statement)
            XCTAssertFalse(overviewTurns.contains(statement), "copies the transcript: \(statement)")
        }
        XCTAssertFalse(reduced.executiveSummary.contains("organically"))
        XCTAssertFalse(reduced.executiveSummary.contains("Meera is running"))
        XCTAssertTrue(reduced.tasks.contains { $0.owner == "Dev" })
    }

    func testOverviewIsFullyDeterministicWhenNoContextSentencePasses() {
        var saved = overviewCheckpoint()
        saved.rankedOverviewFacts = nil
        let turns = saved.turns
        let bad = [copied, namesMeera].map { text in
            SupportedPoint(text: text, evidence: [SourceEvidence(turnID: turns[0].id, quote: turns[0].text)])
        }
        saved.analysis = [LocalAnalysisResult(discussion: bad, decisions: [], tasks: [])]
        let reduced = MeetingAnalysisReducer.reduce(saved, participants: ["Meera", "Dev"])
        let statements = reduced.minutes.summaryStatements.map(\.text)
        XCTAssertFalse(statements.contains(copied))
        XCTAssertFalse(statements.contains(namesMeera))
        XCTAssertFalse(reduced.executiveSummary.isEmpty)
    }

    func testOverviewSentenceRules() {
        let turns = overviewTurns.enumerated().map { turn("t\($0.offset)", $0.element) }
        let owned = SuggestedTask(title: "Send the pricing draft", category: "Follow-up", owner: "Dev",
                                  deadlineText: nil, priority: nil, evidence: [])
        let names = MinutesBuilder.overviewNames(turns: turns, participants: ["Meera", "Dev"], speakerNames: [:],
                                                 tasks: [owned])
        func usable(_ text: String) -> Bool { MinutesBuilder.isUsableOverviewSentence(text, turns: turns, names: names) }
        XCTAssertTrue(usable(good))
        XCTAssertTrue(usable("Dev owns the vendor pricing follow-up."))
        for opener in ["And", "So", "But", "Also", "Then", "Okay", "Basically", "However", "Right", "Yeah"] {
            XCTAssertFalse(usable("\(opener) the vendor list changed after the pilot."), opener)
            XCTAssertFalse(usable("\(opener.lowercased()) the vendor list changed after the pilot."), opener)
        }
        XCTAssertFalse(usable(copied))
        XCTAssertFalse(usable(namesMeera))
        XCTAssertFalse(usable("Which retailers joined the pilot?"))
    }

    func testAttendeeNameMatchesOnlyAsACapitalizedWord() {
        let turns = overviewTurns.enumerated().map { turn("t\($0.offset)", $0.element) }
        let names = MinutesBuilder.overviewNames(turns: turns, participants: ["Meera", "Dev", "Mark"],
                                                 speakerNames: [:], tasks: [])
        func usable(_ text: String) -> Bool { MinutesBuilder.isUsableOverviewSentence(text, turns: turns, names: names) }
        XCTAssertTrue(usable("The vendor list will mark a new baseline after the pilot."))
        XCTAssertFalse(usable("The vendor list was raised by Mark after the pilot."))
    }

    func testAgendaLeadsTheOverview() {
        let reduced = MeetingAnalysisReducer.reduce(
            overviewCheckpoint(), participants: ["Meera", "Dev"],
            agenda: "- Pricing review\n2. Pilot plan\nHiring; Budget")
        XCTAssertTrue(reduced.executiveSummary.hasPrefix("Agenda: Pricing review; Pilot plan; Hiring. "),
                      reduced.executiveSummary)
        XCTAssertEqual(reduced.minutes.summaryStatements.first?.text, "Agenda: Pricing review; Pilot plan; Hiring.")
        let sentenceAfterAgenda = reduced.minutes.summaryStatements.dropFirst().first?.text
        XCTAssertEqual(sentenceAfterAgenda, good)
        let without = MeetingAnalysisReducer.reduce(overviewCheckpoint(), participants: ["Meera", "Dev"])
        XCTAssertFalse(without.executiveSummary.contains("Agenda:"))
    }

    func testAgendaSentenceIsBounded() {
        let long = String(repeating: "quarterly planning ", count: 8)
        let sentence = MinutesBuilder.agendaSentence("One\nTwo\nThree\nFour\n\(long)")
        XCTAssertEqual(sentence, "Agenda: One; Two; Three.")
        let single = MinutesBuilder.agendaSentence(long)
        XCTAssertNotNil(single)
        XCTAssertLessThanOrEqual((single ?? "").count, "Agenda: ".count + 60 + 1)
        XCTAssertNil(MinutesBuilder.agendaSentence("  \n "))
        XCTAssertNil(MinutesBuilder.agendaSentence(nil))
    }
}
