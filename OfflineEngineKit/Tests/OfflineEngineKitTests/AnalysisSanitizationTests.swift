import XCTest
@testable import OfflineEngineKit

final class AnalysisSanitizationTests: XCTestCase {
    private let turns = [
        AnalysisTurn(id: "t1", text: "Rahul will send the estimate tomorrow.", start: 0, end: 2, speaker: nil),
        AnalysisTurn(id: "t2", text: "We have not decided to change the design.", start: 2, end: 4, speaker: nil)
    ]

    func testCopiedPromptExampleIsDroppedWhileGroundedItemsSurvive() {
        let grounded = SuggestedTask(title: "Send the estimate", category: "Follow-up", owner: "Rahul",
                                     deadlineText: "tomorrow", priority: nil,
                                     evidence: [SourceEvidence(turnID: "t1", quote: "Rahul will send the estimate tomorrow")])
        // A small model copying the prompt example: the quote is not in the transcript.
        let copied = SuggestedTask(title: "Prepare the agenda", category: "Create/Update", owner: "Pawan",
                                   deadlineText: "by Friday", priority: nil,
                                   evidence: [SourceEvidence(turnID: "t1", quote: "Pawan, can you prepare the agenda by Friday?")])
        let invented = SupportedPoint(text: "The Pune vendor is selected.",
                                      evidence: [SourceEvidence(turnID: "t2", quote: "Let's go with the Pune vendor.")])
        let raw = LocalAnalysisResult(discussion: [], decisions: [invented], tasks: [grounded, copied])

        let clean = raw.sanitized(against: turns)

        XCTAssertEqual(clean.tasks.map(\.title), ["Send the estimate"])
        XCTAssertTrue(clean.decisions.isEmpty)
        XCTAssertNoThrow(try clean.validate(against: turns))
    }

    func testCopiedExampleTextWithARealQuoteIsDropped() {
        // The quote is genuine, but the wording comes from the prompt, not the meeting.
        let leaked = SupportedPoint(text: "The Pune vendor is engaged (lower price).",
                                    evidence: [SourceEvidence(turnID: "t2", quote: "We have not decided")])
        let placeholder = SuggestedTask(title: "Prepare the [document]", category: "Create/Update", owner: "[Name]",
                                        deadlineText: nil, priority: nil,
                                        evidence: [SourceEvidence(turnID: "t1", quote: "send the estimate")])
        let real = SupportedPoint(text: "The design stays unchanged for now.",
                                  evidence: [SourceEvidence(turnID: "t2", quote: "We have not decided")])
        let clean = LocalAnalysisResult(discussion: [real], decisions: [leaked], tasks: [placeholder])
            .sanitized(against: turns)

        XCTAssertTrue(clean.decisions.isEmpty)
        XCTAssertTrue(clean.tasks.isEmpty)
        XCTAssertEqual(clean.discussion.map(\.text), ["The design stays unchanged for now."])
    }

    func testPuneIsKeptWhenTheMeetingMentionsIt() {
        let spoken = [AnalysisTurn(id: "t1", text: "Okay, let's go with the Pune vendor.", start: 0, end: 2, speaker: nil)]
        let decision = SupportedPoint(text: "The Pune vendor is approved.",
                                      evidence: [SourceEvidence(turnID: "t1", quote: "let's go with the Pune vendor")])
        let clean = LocalAnalysisResult(discussion: [], decisions: [decision], tasks: []).sanitized(against: spoken)
        XCTAssertEqual(clean.decisions.count, 1)
    }

    func testSpeakerLabelOwnerIsNotAPersonAndMergesWithNamedTask() {
        let turn = AnalysisTurn(id: "t1", text: "Rahul will send the estimate tomorrow.", start: 0, end: 2, speaker: "S1")
        let labelled = SuggestedTask(title: "Send the estimate", category: "Follow-up", owner: "S1",
                                     deadlineText: "tomorrow", priority: nil,
                                     evidence: [SourceEvidence(turnID: "t1", quote: "Rahul will send the estimate tomorrow.")])
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "fixture", stage: .completed, turns: [turn],
            speakers: [], analysis: [LocalAnalysisResult(discussion: [], decisions: [], tasks: [labelled])],
            analyzedChunks: 1)

        let reduced = MeetingAnalysisReducer.reduce(checkpoint)

        XCTAssertEqual(reduced.tasks.count, 1)
        XCTAssertEqual(reduced.tasks.first?.owner, "Rahul")
        XCTAssertEqual(reduced.tasks.first?.deadlineText?.lowercased(), "tomorrow")
    }

    func testSpeakerLabelPatternsAreRecognized() {
        for label in ["S1", "s2", "Speaker 3", "SPEAKER_00", "speaker_12"] {
            XCTAssertTrue(MeetingAnalysisReducer.isSpeakerLabel(label, knownLabels: []), label)
        }
        for name in ["Rahul", "Sam", "Sara Khan"] {
            XCTAssertFalse(MeetingAnalysisReducer.isSpeakerLabel(name, knownLabels: []), name)
        }
    }

    func testInvalidCategoryUnknownTurnAndEmptyTextAreDropped() {
        let badCategory = SuggestedTask(title: "Send", category: "Misc", owner: nil, deadlineText: nil, priority: nil,
                                        evidence: [SourceEvidence(turnID: "t1", quote: "send")])
        let unknownTurn = SupportedPoint(text: "Design", evidence: [SourceEvidence(turnID: "t9", quote: "design")])
        let empty = SupportedPoint(text: "  ", evidence: [SourceEvidence(turnID: "t2", quote: "design")])
        let raw = LocalAnalysisResult(discussion: [unknownTurn, empty], decisions: [], tasks: [badCategory])

        let clean = raw.sanitized(against: turns)

        XCTAssertTrue(clean.tasks.isEmpty)
        XCTAssertTrue(clean.discussion.isEmpty)
    }
}
