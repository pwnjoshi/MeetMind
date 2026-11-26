import XCTest
@testable import OfflineEngineKit

/// The scripted Neha/Pawan meeting must produce the same document-grade minutes whatever script the
/// transcript uses: topics, formal resolutions, contextual actions with owners and dates, formal open
/// issues, agenda topics, an English summary and suggested attendees.
final class MinutesDocumentTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? TimeZone.current

    /// Wednesday 11 November 2026.
    private var meetingDate: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 11
        parts.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 1_794_391_200)
    }

    private func reduce(_ lines: [MinutesFixtureLine], participants: [String],
                        model: LocalAnalysisResult = LocalAnalysisResult(discussion: [], decisions: [], tasks: []))
        -> ReducedMeetingAnalysis {
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "minutes", stage: .completed,
            turns: MinutesFixtures.turns(lines), speakers: [], analysis: [model], analyzedChunks: 1)
        return MeetingAnalysisReducer.reduce(checkpoint, participants: participants, meetingDate: meetingDate, timeZone: utc)
    }

    private func assertDocument(_ lines: [MinutesFixtureLine], budgetSubject: String, name: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let reduced = reduce(lines, participants: ["Neha", "Pawan"])
        let minutes = reduced.minutes
        let debug = "\(name): topics=\(minutes.topics.map(\.title)) resolutions=\(minutes.resolutions.map(\.text)) actions=\(minutes.actions.map(\.title)) owners=\(minutes.actions.map { $0.owner ?? "nil" }) open=\(minutes.openIssues.map(\.text)) tasks=\(reduced.tasks.map(\.title)) decisions=\(reduced.decisions.map(\.text)) summary=\(minutes.executiveSummary)"

        XCTAssertEqual(reduced.tasks.count, 2, debug, file: file, line: line)
        XCTAssertEqual(reduced.decisions.count, 2, debug, file: file, line: line)
        XCTAssertEqual(reduced.openIssues.count, 2, debug, file: file, line: line)

        // Formal resolutions with the rationale and the original quotes as evidence.
        XCTAssertEqual(minutes.resolutions.map(\.text),
                       ["That the launch be held on 20 November.",
                        "That the Pune vendor be engaged (preferred for lower price)."],
                       debug, file: file, line: line)
        XCTAssertEqual(minutes.resolutions.last?.rationale, "lower price", debug, file: file, line: line)
        XCTAssertTrue(minutes.resolutions.allSatisfy { !$0.evidence.isEmpty }, debug, file: file, line: line)

        // Actions carry an owner and a resolved date.
        XCTAssertEqual(minutes.actions.map(\.title),
                       ["Prepare the agenda", "Send the presentation to the client"],
                       debug, file: file, line: line)
        XCTAssertEqual(minutes.actions.map { $0.owner ?? "nil" }, ["Pawan", "Neha"], debug, file: file, line: line)
        XCTAssertEqual(minutes.actions.map { $0.dueDate ?? "nil" }, ["2026-11-13", "2026-11-12"], debug, file: file, line: line)
        XCTAssertTrue(minutes.actions.allSatisfy { $0.deadlineText != nil }, debug, file: file, line: line)
        // The checkpoint stores the same tasks as review suggestions.
        let stored = reduced.checkpoint.analysis.flatMap(\.tasks)
        XCTAssertEqual(stored.map(\.title), minutes.actions.map(\.title), debug, file: file, line: line)
        XCTAssertEqual(stored.map { $0.owner ?? "nil" }, ["Pawan", "Neha"], debug, file: file, line: line)

        // Formal open issues.
        XCTAssertEqual(minutes.openIssues.map(\.text),
                       [budgetSubject + " \u{2014} not yet decided; to be taken up at the next meeting.",
                        "Design change \u{2014} not yet decided."],
                       debug, file: file, line: line)

        // Topics in discussion order with outcomes and English bullets.
        XCTAssertEqual(minutes.topics.map { $0.title.lowercased() },
                       ["launch date", "vendor", "budget", "design change"], debug, file: file, line: line)
        XCTAssertEqual(minutes.topics.map { $0.outcome?.kind.rawValue ?? "none" },
                       ["resolved", "resolved", "deferred", "open"], debug, file: file, line: line)
        XCTAssertEqual(minutes.topics.first?.outcome?.text, "the launch be held on 20 November.", debug, file: file, line: line)
        for topic in minutes.topics {
            XCTAssertFalse(topic.discussion.isEmpty, debug, file: file, line: line)
            for bullet in topic.discussion {
                XCTAssertFalse(HindiText.containsDevanagari(bullet), bullet, file: file, line: line)
            }
        }
        XCTAssertTrue(minutes.topics.dropFirst().first?.discussion.contains("The Pune vendor was preferred for its lower price.") == true,
                      debug, file: file, line: line)
        XCTAssertEqual(minutes.agendaText.lowercased(), "launch date\nvendor\nbudget\ndesign change", debug, file: file, line: line)

        // Polished English summary.
        let marketing = budgetSubject.lowercased()
        let expected = "Neha and Pawan discussed the launch date, vendor, budget and design change. "
            + "They decided to launch on 20 November and go with the Pune vendor. "
            + "Next steps are to prepare the agenda and send the presentation to the client. "
            + "The \(marketing) and design change remain open."
        XCTAssertEqual(reduced.executiveSummary, expected, debug, file: file, line: line)
        XCTAssertEqual(minutes.executiveSummary, expected, debug, file: file, line: line)
        let restored = try? JSONDecoder().decode(MinutesContent.self, from: JSONEncoder().encode(minutes))
        let statements = restored?.summaryStatements ?? []
        XCTAssertEqual(statements.map(\.text).joined(separator: " "), expected, debug, file: file, line: line)
        XCTAssertTrue(statements.allSatisfy { !$0.evidence.isEmpty }, debug, file: file, line: line)
        XCTAssertFalse(HindiText.containsDevanagari(reduced.executiveSummary), debug, file: file, line: line)

        // Evidence quotes stay exact substrings of their cited turns.
        let sources = Dictionary(uniqueKeysWithValues: reduced.checkpoint.turns.map { ($0.id, $0.text) })
        var evidence: [SourceEvidence] = []
        evidence += minutes.resolutions.flatMap(\.evidence)
        evidence += minutes.actions.flatMap(\.evidence)
        evidence += minutes.openIssues.flatMap(\.evidence)
        evidence += minutes.topics.flatMap(\.evidence)
        evidence += minutes.suggestedAttendees.flatMap(\.evidence)
        for item in evidence {
            XCTAssertTrue(sources[item.turnID]?.contains(item.quote) == true, "Ungrounded quote: \(item.quote)", file: file, line: line)
        }
    }

    func testActionTitlesRemoveSpokenFillerAndKeepSelectionCriteria() {
        XCTAssertEqual(
            MinutesComposer.actionTitle("Continue focusing more on the models, right, which is more suitable and accurate"),
            "Continue evaluating models for suitability and accuracy")
        XCTAssertEqual(
            MinutesComposer.actionTitle("Continue your research and narrow down your user segment and make sure you look for user segment that very closely requires the need of physical media"),
            "Continue researching and narrow down the target user segment, focusing on users who need physical media")
    }

    func testOverviewKeepsCitedBlockerWhenRankingIsUnavailable() {
        let agenda = AnalysisTurn(id: "agenda", text: "First, the rollout.", start: 0, end: 1, speaker: nil)
        let blocker = AnalysisTurn(id: "blocker", text: "The rollout is blocked by the vendor audit.",
                                   start: 2, end: 4, speaker: nil)
        let agendaSource = SourceEvidence(turnID: agenda.id, quote: agenda.text)
        let blockerSource = SourceEvidence(turnID: blocker.id, quote: blocker.text)
        let point = SupportedPoint(text: "Rollout progress is waiting for the pending vendor audit sign-off.",
                                   evidence: [blockerSource])
        let invented = "The rollout is blocked by a funding freeze."
        let wrongQuote = SupportedPoint(text: invented, evidence: [
            SourceEvidence(turnID: blocker.id, quote: invented)
        ])
        var hindi = HindiAnalysis()
        hindi.topics = [HindiTopic(title: "Rollout", evidence: agendaSource)]

        let minutes = MinutesBuilder.build(.init(turns: [agenda, blocker], hindi: hindi, decisions: [],
            discussion: [wrongQuote, point, point], rankedDiscussion: [], openIssues: [], tasks: [], participants: [],
            speakerNames: [:], meetingDate: nil, timeZone: utc))

        let statements = minutes.summaryStatements.filter { $0.text == point.text }
        XCTAssertEqual(statements.count, 1)
        XCTAssertFalse(minutes.executiveSummary.contains(invented))
        XCTAssertEqual(statements.first?.evidence.map(\.turnID), [blocker.id])
    }

    func testDevanagariPunctuatedTranscript() {
        assertDocument(MinutesFixtures.devanagari, budgetSubject: "Marketing budget", name: "devanagari")
    }

    func testDevanagariUnpunctuatedMergedTranscript() {
        assertDocument(MinutesFixtures.unpunctuated, budgetSubject: "Marketing budget", name: "unpunctuated")
    }

    func testRomanizedHinglishTranscript() {
        assertDocument(MinutesFixtures.romanized, budgetSubject: "Marketing budget", name: "romanized")
    }

    func testEnglishTranscript() {
        assertDocument(MinutesFixtures.english, budgetSubject: "Budget", name: "english")
    }

    // MARK: - Attendees

    func testNamesHeardInTheConversationAreSuggestedUnlessAlreadyAttendees() {
        let renderings: [(String, [MinutesFixtureLine])] = [
            ("devanagari", MinutesFixtures.devanagari), ("unpunctuated", MinutesFixtures.unpunctuated),
            ("romanized", MinutesFixtures.romanized), ("english", MinutesFixtures.english)
        ]
        for (name, lines) in renderings {
            let partial = reduce(lines, participants: ["Neha"]).minutes.suggestedAttendees
            XCTAssertEqual(partial.map(\.name), ["Pawan"], name)
            XCTAssertFalse(partial.first?.evidence.isEmpty ?? true, name)
            let none = reduce(lines, participants: []).minutes.suggestedAttendees
            XCTAssertEqual(Set(none.map(\.name)), Set(["Neha", "Pawan"]), name)
            XCTAssertTrue(reduce(lines, participants: ["Neha", "Pawan"]).minutes.suggestedAttendees.isEmpty, name)
        }
    }

    func testVoiceLabelsAreNamedFromTheConversation() {
        let turns = MinutesFixtures.turns(MinutesFixtures.romanized)
        let inferred = SpeakerNameInference.infer(turns: turns, participants: ["Neha", "Pawan"], speakerNames: [:])
        XCTAssertEqual(inferred["S1"], "Neha")
        XCTAssertEqual(inferred["S2"], "Pawan")
        // A name the user already assigned is never overridden.
        let kept = SpeakerNameInference.infer(turns: turns, participants: ["Neha", "Pawan"], speakerNames: ["S1": "Pawan"])
        XCTAssertEqual(kept["S1"], "Pawan")
    }

    // MARK: - Model output

    func testModelDiscussionThatCopiesTheTranscriptIsNotUsed() {
        let copy = SupportedPoint(text: "Yes, 20 November works for me.",
                                  evidence: [SourceEvidence(turnID: "t4", quote: "Yes, 20 November works for me.")])
        let paraphrase = SupportedPoint(text: "Both agreed the launch timing is settled and the vendor choice follows.",
                                        evidence: [SourceEvidence(turnID: "t4", quote: "We agreed to launch on 20 November.")])
        let devanagariPoint = SupportedPoint(text: "\u{0939}\u{093E}\u{0901} 20 November \u{0938}\u{0939}\u{0940} \u{0930}\u{0939}\u{0947}\u{0917}\u{093E}",
                                             evidence: [SourceEvidence(turnID: "t4", quote: "Yes, 20 November works for me.")])
        let model = LocalAnalysisResult(discussion: [copy, paraphrase, devanagariPoint], decisions: [], tasks: [])
        let reduced = reduce(MinutesFixtures.english, participants: ["Neha", "Pawan"], model: model)
        XCTAssertFalse(reduced.discussion.contains { $0.text.contains("works for me") })
        XCTAssertFalse(reduced.discussion.contains { HindiText.containsDevanagari($0.text) })
        XCTAssertFalse(reduced.discussion.contains { $0.text.contains("the vendor choice follows") })
    }

    func testDecisionDoesNotBorrowAReasonFromADifferentVendor() {
        let lines = [
            MinutesFixtureLine(speaker: "S1", text: "The Delhi vendor has a lower price."),
            MinutesFixtureLine(speaker: "S2", text: "We agreed to go with the Pune vendor.")
        ]
        let decision = reduce(lines, participants: []).minutes.resolutions.first
        XCTAssertNotNil(decision)
        XCTAssertNil(decision?.rationale)
        XCTAssertEqual(decision?.evidence.count, 1)
    }

    // MARK: - Dates and phrases

    func testSpokenDeadlinesResolveAgainstTheMeetingDate() {
        let cases: [(String, String?)] = [
            ("by Friday", "2026-11-13"), ("Friday \u{0924}\u{0915}", "2026-11-13"), ("kal tak", "2026-11-12"),
            ("by tomorrow", "2026-11-12"), ("parso tak", "2026-11-13"), ("today", "2026-11-11"),
            ("20 November", "2026-11-20"), ("by the 15th", "2026-11-15"), ("5 November", "2027-11-05"),
            ("agle hafte tak", "2026-11-18"), ("whenever", nil)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(DueDateResolver.resolve(text, meetingDate: meetingDate, timeZone: utc), expected, text)
        }
        XCTAssertNil(DueDateResolver.resolve("by Friday", meetingDate: nil, timeZone: utc))
    }

    func testResolutionWording() {
        XCTAssertEqual(MinutesBuilder.shortPhrase("We agreed to launch on 20 November."), "launch on 20 November")
        XCTAssertEqual(MinutesBuilder.shortPhrase("Okay, let's go with the Pune vendor."), "go with the Pune vendor")
        XCTAssertEqual(MinutesBuilder.formalResolution(short: "go with the new design", original: "", rationale: nil, hasLaunchContext: true),
                       "That the new design be adopted.")
        XCTAssertEqual(MinutesBuilder.formalResolution(short: "finalize the budget", original: "", rationale: nil, hasLaunchContext: false),
                       "That the budget be finalized.")
        XCTAssertEqual(MinutesBuilder.formalResolution(short: "go with the Pune vendor", original: "", rationale: "because it is cheaper",
                                                       hasLaunchContext: false),
                       "That the Pune vendor be engaged (because it is cheaper).")
        XCTAssertEqual(MinutesBuilder.openIssueText(subject: "Design change", undecided: true, pending: false, nextMeeting: false),
                       "Design change \u{2014} not yet decided.")
        XCTAssertEqual(MinutesBuilder.englishSubject("The design change is also not decided yet."), "Design change")
        XCTAssertNil(MinutesBuilder.englishSubject("We have not decided to change the design."))
    }

    func testRunOnEnglishIsSplitAtSentenceOpenersAndPunctuatedTextIsLeftAlone() {
        let runOn = AnalysisTurn(id: "t1",
            text: "we agreed to launch on 20 November okay now let's talk about the vendor and the budget",
            start: 0, end: 5, speaker: nil)
        let pieces = ActionExtractor.sentencePieces([runOn])[0]
        XCTAssertEqual(pieces, ["we agreed to launch on 20 November", "okay now let's talk about the vendor and the budget"])
        for piece in pieces { XCTAssertTrue(runOn.text.contains(piece)) }
        let punctuated = AnalysisTurn(id: "t2",
            text: "We agreed to launch on 20 November, okay, now let's talk about the vendor and the budget.",
            start: 0, end: 5, speaker: nil)
        XCTAssertEqual(ActionExtractor.sentencePieces([punctuated])[0].count, 1)
    }

    func testNextMeetingNeedsADateOrTime() {
        let without = MinutesFixtures.turns(MinutesFixtures.romanized)
        XCTAssertNil(NextMeetingFinder.find(turns: without, meetingDate: meetingDate, timeZone: utc))
        let turn = AnalysisTurn(id: "t1", text: "Next meeting on Thursday at 10 am.", start: 0, end: 3, speaker: nil)
        let found = NextMeetingFinder.find(turns: [turn], meetingDate: meetingDate, timeZone: utc)
        XCTAssertEqual(found?.dateText, "Thursday")
        XCTAssertEqual(found?.timeText, "10 am")
        XCTAssertEqual(found?.isoDate, "2026-11-12")
    }

    // MARK: - Codable

    func testMinutesSurviveTheCheckpointRoundTripAndOldCheckpointsStillDecode() throws {
        let reduced = reduce(MinutesFixtures.english, participants: ["Neha"])
        let data = try JSONEncoder().encode(reduced.checkpoint)
        let decoded = try JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data)
        XCTAssertEqual(decoded.minutes?.topics.count, reduced.minutes.topics.count)
        XCTAssertEqual(decoded.minutes?.suggestedAttendees.map(\.name), ["Pawan"])
        XCTAssertEqual(decoded.minutes?.resolutions.first?.text, "That the launch be held on 20 November.")

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let minutes = try XCTUnwrap(object["minutes"] as? [String: Any])
        for key in ["executiveSummary", "topics", "resolutions", "actions", "openIssues", "suggestedAttendees"] {
            XCTAssertNotNil(minutes[key], key)
        }
        let topics = try XCTUnwrap(minutes["topics"] as? [[String: Any]])
        let outcome = try XCTUnwrap(topics.first?["outcome"] as? [String: Any])
        XCTAssertEqual(outcome["kind"] as? String, "resolved")

        var legacy = object
        legacy.removeValue(forKey: "minutes")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(try JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: legacyData).minutes)
    }

    // MARK: - Prompt

    func testMinutesPromptAsksForEnglishRephrasingWithinTheSystemBudget() throws {
        let turn = AnalysisTurn(id: "t1", text: "Pawan, can you prepare the agenda?", start: 0, end: 2, speaker: nil)
        let prompt = try LocalLanguageModel.makePrompt(turns: [turn], meetingDate: Date(timeIntervalSince1970: 1_700_000_000),
                                                       timezone: "Asia/Kolkata")
        let system = prompt.components(separatedBy: "<|im_end|>")[0]
        XCTAssertLessThanOrEqual(system.utf8.count, 2300)
        XCTAssertTrue(system.contains("rephrased"))
        XCTAssertTrue(system.contains("formal English resolutions"))
        XCTAssertNotEqual(OfflineAnalysisContract.promptVersion, "meeting-analysis-v7")
    }
}
