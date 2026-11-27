import XCTest
@testable import OfflineEngineKit

final class VidurRagRetrieverTests: XCTestCase {
    private func retrieve(_ question: String, history: [VidurChatTurn] = [], limit: Int = 6) -> VidurRagRetrieval {
        VidurRagTestSupport.retrieve(question, history: history, limit: limit)
    }

    func testDecisionQuestionFindsTheDecisionRecord() {
        let result = retrieve("What did we decide on launch?")
        XCTAssertTrue(result.hits.contains { $0.kind == .decision && $0.text.contains("Launch on 20 November") },
                      result.hits.map(\.text).joined(separator: "\n"))
        XCTAssertTrue(result.filters.intents.contains(.decisions))
        XCTAssertLessThanOrEqual(result.hits.count, 6)
    }

    func testPersonFilterBringsThatPersonsActions() {
        let result = retrieve("What tasks does Pawan have?")
        XCTAssertTrue(result.filters.people.contains("Pawan Kumar"), "\(result.filters.people)")
        XCTAssertTrue(result.hits.contains { $0.kind == .action && $0.speaker == "Pawan Kumar" })
    }

    func testLastMeetingFilterScopesEverythingToThatMeeting() {
        let result = retrieve("What did we decide in the last meeting?")
        XCTAssertTrue(result.filters.lastMeeting)
        XCTAssertEqual(result.scopedMeetings.map(\.title), ["Design review"])
        XCTAssertFalse(result.hits.isEmpty)
        XCTAssertTrue(result.hits.allSatisfy { $0.meetingTitle == "Design review" })
        XCTAssertEqual(result.facts.map(\.meetingTitle), ["Design review"])
    }

    func testDateRangeFilterKeepsOnlyMeetingsInThePeriod() {
        let result = retrieve("What was discussed last week?")
        XCTAssertEqual(result.filters.rangeLabel, "last week")
        XCTAssertEqual(result.scopedMeetings.map(\.title), ["Launch readiness"])
        XCTAssertTrue(result.hits.allSatisfy { $0.meetingTitle == "Launch readiness" })
        XCTAssertFalse(result.filters.relaxed)
    }

    func testMeetingTitleFilter() {
        let result = retrieve("What did we discuss in the Weekly sync?")
        XCTAssertEqual(result.filters.meetingTitles, ["Weekly sync"])
        XCTAssertEqual(result.scopedMeetings.map(\.title), ["Weekly sync"])
    }

    func testFollowUpBorrowsThePeopleAndPeriodOfThePreviousQuestion() {
        let history = [VidurChatTurn(question: "What did Pawan promise last week?",
                                     answer: "Pawan Kumar has 1 open task from last week.")]
        let result = retrieve("and Neha?", history: history)
        XCTAssertEqual(result.scopedMeetings.map(\.title), ["Launch readiness"])
        XCTAssertTrue(result.filters.people.contains("Neha Sharma"), "\(result.filters.people)")
    }

    func testEnglishQuestionFindsHindiSpeech() {
        let result = retrieve("Who is clearing the vendor payment?")
        XCTAssertTrue(result.hits.contains { $0.meetingTitle == "Weekly sync" },
                      result.hits.map(\.meetingTitle).joined(separator: ", "))
        XCTAssertTrue(result.facts.contains { $0.meetingTitle == "Weekly sync" })
    }

    func testHindiQuestionFindsEnglishMinutes() {
        // "Pune vendor" is only written in Roman letters; the question uses the Devanagari spelling of "vendor".
        let result = retrieve("\u{0935}\u{0947}\u{0902}\u{0921}\u{0930} \u{0915}\u{093E}\u{0902}\u{091F}\u{094D}\u{0930}\u{0947}\u{0915}\u{094D}\u{091F} \u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0941}\u{0906}")
        XCTAssertFalse(result.hits.isEmpty)
        XCTAssertTrue(result.hits.contains { $0.meetingTitle == "Launch readiness" || $0.meetingTitle == "Weekly sync" })
    }

    private func crowdedIndex() -> VidurRagIndex {
        let records = (1...4).map { number in
            VidurMeetingRecord(
                title: "Budget talk \(number)", date: VidurEvalFixtures.date(2025, 11, number + 5),
                attendees: ["Asha Rao"], summary: "The budget was reviewed in part \(number).",
                decisions: [VidurMeetingLine(text: "Approve budget \(number)", timestamp: 10, speaker: "Asha Rao")],
                tasks: [VidurMeetingTask(title: "Share budget sheet \(number)", owner: "Asha Rao")],
                turns: [VidurMeetingTurn(text: "The budget needs a final number \(number).", start: 5, speaker: "Asha Rao"),
                        VidurMeetingTurn(text: "I will share the budget sheet.", start: 30, speaker: "Asha Rao")])
        }
        return VidurRagTestSupport.index(records)
    }

    func testResultsAreDiversifiedAcrossMeetings() {
        let result = VidurRagTestSupport.retrieve("budget", index: crowdedIndex())
        XCTAssertEqual(result.hits.count, 6)
        var perMeeting: [UUID: Int] = [:]
        for hit in result.hits { perMeeting[hit.meetingID, default: 0] += 1 }
        XCTAssertGreaterThanOrEqual(perMeeting.count, 2)
        XCTAssertTrue(perMeeting.values.allSatisfy { $0 <= 3 }, "\(perMeeting.values)")
    }

    func testOverlappingTranscriptWindowsAreNotBothReturned() {
        let turns = (0..<12).map { number in
            VidurMeetingTurn(text: "Pricing point number \(number) needs review.", start: TimeInterval(number * 20), speaker: "Asha Rao")
        }
        let record = VidurMeetingRecord(title: "Pricing call", date: VidurEvalFixtures.date(2025, 11, 12), turns: turns)
        let result = VidurRagTestSupport.retrieve("pricing review", index: VidurRagTestSupport.index([record]))
        let windows = result.hits.filter { $0.kind == .transcript }
        XCTAssertFalse(windows.isEmpty)
        for first in windows {
            for second in windows where first.id != second.id {
                XCTAssertFalse(VidurRagRetriever.overlaps(first, second))
            }
        }
    }

    func testFactsBlocksAlwaysComeAlong() {
        let result = retrieve("What did we decide?")
        XCTAssertFalse(result.facts.isEmpty)
        XCTAssertLessThanOrEqual(result.facts.count, 2)
        XCTAssertTrue(result.facts.allSatisfy { $0.kind == .facts && $0.text.contains("Held ") })
        XCTAssertTrue(result.hits.allSatisfy { $0.kind != .facts })
    }

    func testOverdueFilterPrefersOpenLateTasks() {
        let result = retrieve("Any overdue tasks?")
        let late = result.hits.filter { $0.kind == .action && $0.isCompleted == false && ($0.dueDate ?? .distantFuture) < VidurEvalFixtures.now }
        XCTAssertFalse(late.isEmpty, result.hits.map(\.text).joined(separator: "\n"))
    }

    func testQuestionTheMeetingsDoNotCoverReturnsNothing() {
        let result = retrieve("What is the capital of France?")
        XCTAssertTrue(result.hits.isEmpty, result.hits.map(\.text).joined(separator: "\n"))
    }

    func testRankFusionRewardsChunksThatBothRankersLike() {
        // The decision names the topic AND is a decision, so it beats a transcript line that only names the topic.
        let record = VidurMeetingRecord(
            title: "Vendor call", date: VidurEvalFixtures.date(2025, 11, 12), attendees: ["Asha Rao"],
            decisions: [VidurMeetingLine(text: "Choose the Pune vendor", timestamp: 40, speaker: "Asha Rao")],
            turns: [VidurMeetingTurn(text: "The vendor sent a long note about vendor terms and vendor pricing.", start: 5, speaker: "Asha Rao"),
                    VidurMeetingTurn(text: "We talked about lunch.", start: 200, speaker: "Asha Rao")])
        let result = VidurRagTestSupport.retrieve("What did we decide about the vendor?", index: VidurRagTestSupport.index([record]))
        XCTAssertEqual(result.hits.first?.kind, .decision, result.hits.map { $0.kind.rawValue }.joined(separator: ","))
    }
}
