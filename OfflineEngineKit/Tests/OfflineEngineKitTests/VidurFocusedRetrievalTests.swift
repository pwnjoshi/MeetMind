import XCTest
@testable import OfflineEngineKit

/// "How did the budget discussion go?" is the story of one meeting. The model must not read the open issue of one
/// meeting next to the decision of another and blend them ("not approved" and "approve a $10,000 budget").
final class VidurFocusedRetrievalTests: XCTestCase {
    private let calendar = VidurEvalFixtures.calendar

    /// 22 Nov. The budget is an open issue.
    private var quick: VidurMeetingRecord {
        VidurMeetingRecord(
            title: "Quick meeting", date: VidurEvalFixtures.date(2025, 11, 22, 10), attendees: ["Pawan", "Neha"],
            openIssues: [VidurMeetingLine(text: "Budget is not decided", timestamp: 20,
                                          quote: "the budget is not yet decided", speaker: "Pawan")],
            turns: [VidurMeetingTurn(text: "prepare the agenda by friday", start: 3, speaker: "Pawan"),
                    VidurMeetingTurn(text: "the budget is not yet decided and that is pending", start: 20, speaker: "Pawan")])
    }

    /// 23 Nov. A different meeting that mentions a budget once.
    private var design: VidurMeetingRecord {
        VidurMeetingRecord(
            title: "Design sync", date: VidurEvalFixtures.date(2025, 11, 23, 10), attendees: ["Maya"],
            decisions: [VidurMeetingLine(text: "Approve the budget of 10000 dollars", timestamp: 40, speaker: "Maya")])
    }

    private func retrieve(_ question: String) -> VidurRagRetrieval {
        VidurRagTestSupport.retrieve(question, index: VidurRagTestSupport.index([quick, design]))
    }

    private func prompt(_ retrieval: VidurRagRetrieval, question: String) -> VidurRagPrompt {
        let input = VidurRagPromptInput(question: question, userName: "Neha", now: VidurEvalFixtures.now,
                                        calendar: calendar, retrieval: retrieval)
        return VidurRagPromptBuilder.build(input)
    }

    func testHowDidItGoReadsOnlyTheMeetingThatDiscussesTheTopicMost() {
        let result = retrieve("How did the budget discussion go?")
        XCTAssertEqual(result.focusedMeeting?.title, "Quick meeting")
        XCTAssertEqual(result.scopedMeetings.map(\.title), ["Quick meeting"])
        XCTAssertFalse(result.hits.isEmpty)
        XCTAssertTrue(result.hits.allSatisfy { $0.meetingTitle == "Quick meeting" },
                      result.hits.map(\.meetingTitle).joined(separator: ", "))
        XCTAssertEqual(result.facts.map(\.meetingTitle), ["Quick meeting"])
    }

    func testWhatHappenedWithTheTopicIsAlsoOneMeeting() {
        let result = retrieve("What happened with the budget?")
        XCTAssertEqual(result.focusedMeeting?.title, "Quick meeting")
        XCTAssertTrue(result.hits.allSatisfy { $0.meetingTitle == "Quick meeting" })
    }

    func testAskingAcrossMeetingsKeepsEveryMeeting() {
        let result = retrieve("How did the budget discussion go across all meetings?")
        XCTAssertNil(result.focusedMeeting)
        XCTAssertEqual(result.scopedMeetings.count, 2)
        XCTAssertTrue(result.hits.contains { $0.meetingTitle == "Quick meeting" })
        XCTAssertTrue(result.hits.contains { $0.meetingTitle == "Design sync" })
    }

    func testPlainQuestionsAreNotNarrowedToOneMeeting() {
        let result = retrieve("What did we decide about the budget?")
        XCTAssertNil(result.focusedMeeting)
        XCTAssertTrue(result.hits.contains { $0.meetingTitle == "Design sync" })
    }

    func testRoutingWords() {
        for question in ["How did the budget discussion go?", "and how was the launch?", "What happened with the vendor?",
                         "What was the outcome of the review?"] {
            XCTAssertTrue(VidurRagRouting.isOutcomeQuestion(question), question)
        }
        for question in ["How long was the design review?", "How many engineers are we hiring?", "What did we decide?"] {
            XCTAssertFalse(VidurRagRouting.isOutcomeQuestion(question), question)
        }
        for question in ["How did the budget go across all meetings?", "How did it go in the meetings?",
                         "How has the budget changed over time?", "How did the launch go overall?"] {
            XCTAssertTrue(VidurRagRouting.asksAcrossMeetings(question), question)
        }
        XCTAssertFalse(VidurRagRouting.asksAcrossMeetings("How did the budget discussion go?"))
    }

    func testPromptNamesTheOneMeetingItReads() {
        let question = "How did the budget discussion go?"
        let built = prompt(retrieve(question), question: question)
        XCTAssertTrue(built.system.contains("All blocks are from one meeting, Quick meeting (Sat 22 Nov)"), built.system)
        XCTAssertTrue(built.system.contains("Meetings searched (1): Quick meeting (Sat 22 Nov)"), built.system)
        XCTAssertFalse(built.user.contains("Design sync"), built.user)
    }

    func testPromptRequiresNamingTheMeetingForEveryFactWhenSeveralAreRead() {
        let question = "How did the budget discussion go across all meetings?"
        let built = prompt(retrieve(question), question: question)
        XCTAssertTrue(built.system.contains("name the meeting and day for each fact"), built.system)
        XCTAssertTrue(built.system.contains("Never blend them into one statement"), built.system)
        XCTAssertFalse(built.system.contains("All blocks are from one meeting"), built.system)
        XCTAssertTrue(built.user.contains("Design sync"), built.user)
    }

    func testSingleMeetingPromptHasNoMultiMeetingRule() {
        let question = "How did the budget discussion go?"
        let retrieval = VidurRagTestSupport.retrieve(question, index: VidurRagTestSupport.index([quick]))
        let built = prompt(retrieval, question: question)
        XCTAssertNil(retrieval.focusedMeeting)
        XCTAssertFalse(built.system.contains("name the meeting and day for each fact"), built.system)
        XCTAssertFalse(built.system.contains("All blocks are from one meeting"), built.system)
    }
}
