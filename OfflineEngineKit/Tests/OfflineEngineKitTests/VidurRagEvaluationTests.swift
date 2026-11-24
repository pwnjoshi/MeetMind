import XCTest
@testable import OfflineEngineKit

/// One question and the saved record that must come back for it.
private struct RagCase {
    let id: String
    let question: String
    var history: [VidurChatTurn] = []
    /// The meeting the source must come from. Nil accepts any meeting.
    var meeting: String?
    /// Accepted kinds of record. Empty accepts any kind.
    var kinds: Set<VidurRagKind> = []
    /// At least one of these (case-insensitive) must appear in the record's text.
    var containsAny: [String]
}

/// Retrieval quality over the four synthetic meetings of `VidurEvalFixtures` (English, Hindi and Hinglish).
/// A case passes when a record that answers the question is among the top six hits or the facts blocks.
final class VidurRagEvaluationTests: XCTestCase {
    private static let cases: [RagCase] = [
        RagCase(id: "decide-pune", question: "What did we decide about the Pune vendor?",
                meeting: "Launch readiness", kinds: [.decision], containsAny: ["Pune vendor"]),
        RagCase(id: "owner-presentation", question: "Who is responsible for sending the presentation to the client?",
                meeting: "Launch readiness", kinds: [.action], containsAny: ["presentation"]),
        RagCase(id: "launch-date", question: "When is the launch?",
                meeting: "Launch readiness", containsAny: ["20 November"]),
        RagCase(id: "absent-launch", question: "Who was absent from the launch readiness meeting?",
                meeting: "Launch readiness", kinds: [.attendance, .facts], containsAny: ["Absent: Arjun Mehta"]),
        RagCase(id: "open-marketing-budget", question: "What is still open about the marketing budget?",
                meeting: "Launch readiness", containsAny: ["marketing budget", "Budget for marketing"]),
        RagCase(id: "hiring-engineers", question: "How many engineers are we hiring?",
                meeting: "Hiring review", containsAny: ["two backend engineers"]),
        RagCase(id: "hiring-why", question: "Why did the hiring review open backend roles?",
                meeting: "Hiring review", containsAny: ["backend"]),
        RagCase(id: "maya-onboarding", question: "What did Maya say about the onboarding screen?",
                meeting: "Design review", containsAny: ["onboarding"]),
        RagCase(id: "maya-tasks", question: "What are Maya's tasks?",
                meeting: "Design review", kinds: [.action], containsAny: ["Revise onboarding screen copy"]),
        RagCase(id: "pawan-done", question: "Which tasks did Pawan complete?",
                meeting: "Launch readiness", kinds: [.action], containsAny: ["Book the launch venue"]),
        RagCase(id: "hindi-vendor-payment", question: "\u{0935}\u{0947}\u{0902}\u{0921}\u{0930} \u{092A}\u{0947}\u{092E}\u{0947}\u{0902}\u{091F} \u{0915}\u{093E} \u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0941}\u{0906}?",
                meeting: "Weekly sync", containsAny: ["\u{0935}\u{0947}\u{0902}\u{0921}\u{0930}"]),
        RagCase(id: "hinglish-vendor-payment", question: "vendor payment kab tak clear hoga?",
                meeting: "Weekly sync", containsAny: ["\u{0935}\u{0947}\u{0902}\u{0921}\u{0930}"]),
        RagCase(id: "english-finds-hindi-budget", question: "Is the budget decided in the weekly sync?",
                meeting: "Weekly sync", kinds: [.openIssue, .transcript], containsAny: ["\u{092C}\u{091C}\u{091F}"]),
        RagCase(id: "agenda-launch", question: "What is the agenda for the launch readiness meeting?",
                meeting: "Launch readiness", kinds: [.agenda, .facts], containsAny: ["Vendor selection"]),
        RagCase(id: "design-length", question: "How long was the design review?",
                meeting: "Design review", kinds: [.facts], containsAny: ["23 min"]),
        RagCase(id: "hiring-attendees", question: "Who attended the hiring review?",
                meeting: "Hiring review", kinds: [.attendance, .facts], containsAny: ["Arjun Mehta"]),
        RagCase(id: "neha-owes", question: "What does Neha owe?",
                kinds: [.action], containsAny: ["owner: Neha Sharma"]),
        RagCase(id: "pricing-copy-due", question: "When is the pricing page copy due?",
                meeting: "Weekly sync", kinds: [.action], containsAny: ["Send pricing page copy"]),
        RagCase(id: "last-week-discussion", question: "What was discussed last week?",
                meeting: "Launch readiness", containsAny: ["launch", "vendor", "budget"]),
        RagCase(id: "launch-date-agreed", question: "Did we agree on a launch date?",
                meeting: "Launch readiness", containsAny: ["20 November"]),
        RagCase(id: "who-suggested-pune", question: "Who suggested going with the Pune vendor?",
                meeting: "Launch readiness", containsAny: ["Pune vendor"]),
        RagCase(id: "unresolved-budget", question: "Which budget issues are unresolved?",
                kinds: [.openIssue], containsAny: ["budget", "\u{092C}\u{091C}\u{091F}"]),
        RagCase(id: "hinglish-pawan-vendor", question: "Aur Pawan ne kya bola vendor ke baare mein?",
                containsAny: ["vendor", "\u{0935}\u{0947}\u{0902}\u{0921}\u{0930}"]),
        RagCase(id: "arjun-promised", question: "What did Arjun promise?",
                kinds: [.action], containsAny: ["Post the backend job description", "Update the invoice tracker"]),
        RagCase(id: "follow-up-neha", question: "and Neha?",
                history: [VidurChatTurn(question: "What did Pawan promise last week?", answer: "Pawan Kumar has 1 open task from last week.")],
                meeting: "Launch readiness", kinds: [.action], containsAny: ["Send the presentation"])
    ]

    private func isCovered(_ testCase: RagCase, in retrieval: VidurRagRetrieval) -> Bool {
        (retrieval.hits + retrieval.facts).contains { chunk in
            if let meeting = testCase.meeting, chunk.meetingTitle != meeting { return false }
            if !testCase.kinds.isEmpty, !testCase.kinds.contains(chunk.kind) { return false }
            let text = chunk.text.lowercased()
            return testCase.containsAny.contains { text.contains($0.lowercased()) }
        }
    }

    func testThereAreAtLeastTwentyCases() {
        XCTAssertGreaterThanOrEqual(Self.cases.count, 20)
        XCTAssertEqual(Set(Self.cases.map(\.id)).count, Self.cases.count, "Case ids are unique")
    }

    func testTheExpectedRecordIsAmongTheTopSixHits() {
        let index = VidurRagTestSupport.index()
        var missed: [String] = []
        for testCase in Self.cases {
            let retrieval = VidurRagTestSupport.retrieve(testCase.question, history: testCase.history, limit: 6, index: index)
            XCTAssertLessThanOrEqual(retrieval.hits.count, 6, testCase.id)
            if !isCovered(testCase, in: retrieval) { missed.append(testCase.id) }
        }
        let recall = Double(Self.cases.count - missed.count) / Double(Self.cases.count)
        XCTAssertGreaterThanOrEqual(recall, 0.85, "Recall@6 \(recall). Missed: \(missed.joined(separator: ", "))")
    }

    func testEveryRetrievalIsAlsoSmallEnoughForThePrompt() {
        let index = VidurRagTestSupport.index()
        for testCase in Self.cases {
            let retrieval = VidurRagTestSupport.retrieve(testCase.question, history: testCase.history, index: index)
            let input = VidurRagPromptInput(question: testCase.question, history: testCase.history, userName: "Neha Sharma",
                                            now: VidurEvalFixtures.now, calendar: VidurEvalFixtures.calendar, retrieval: retrieval)
            let built = VidurRagPromptBuilder.build(input)
            XCTAssertLessThanOrEqual(built.estimatedTokens, VidurRagPromptBuilder.tokenBudget, testCase.id)
        }
    }
}
