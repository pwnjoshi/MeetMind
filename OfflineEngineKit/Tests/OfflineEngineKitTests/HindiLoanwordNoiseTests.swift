import XCTest
@testable import OfflineEngineKit

/// The scripted Neha/Pawan meeting as Whisper wrote it on a device: English loanwords spelled by ear in
/// Devanagari ("लोंच" for launch, "बजित" for budget, "वेंदर" for vendor). The minutes must match the ones
/// produced from clean transcripts, with and without a noisy model result.
final class HindiLoanwordNoiseTests: XCTestCase {
    private let noisyTexts: [String] = [
        "हाई पवन, चलो आज की मीटिंग शुरू करते हैं। आज हमें लोंज और बज़त पर बात करनी है।",
        "हाँ, नहा, ठीक है, पहले लौंच डेट की बात कर लेते हैं।",
        "मुझे लगता है हमें 20 नोवेंबर को लोंच करना चाहिए। तुम्हें क्या लगता है।",
        "हाँ, 20 नोवेंबर सही रहेगा, चलो, लोंच 20 नोवेंबर को ही फाइनल करते हैं।",
        "ठीक है, यह Final है, अग Wendor के बारे में बात करते हैं।",
        "मेरे हिसाब से पुनेवाला वेंदर अच्छा है, उसका प्राइस भी कम है।",
        "हाँ, लेट एस गो विद दिपुने वेंदर।",
        "पवन, क्या तुम फ्राइडे तक अजेंड तयार कर सकते हो।",
        "हाँ, जरूर, मैं फ्राइडे तक अजेंड बना दूंगा।",
        "और निहा, तुम कल तक प्लायंट को प्रेजंटेशन भेज दोगी।",
        "हाँ, मैं कल तक प्रेजंटेशन भेज दूंगी।",
        "बजित का क्या करें, मार्केटिंग के लिए कितना रखें।",
        "बजट अभी डिसाइड नहीं हुआ है, उस पर अगली मीटिंग में बात करेंगे।",
        "ठीक है, डिजाइन चेंज करना है या नहीं, वो भी अभीते नहीं हुआ।",
        "हाँ, वो भी पेंडिंग है। ठीक है, आज के लिए इतना ही। थैंक यू पवन।"
    ]

    private func alternating(_ index: Int) -> String? { index % 2 == 0 ? "S1" : "S2" }
    private func oneVoice(_ index: Int) -> String? { "S1" }

    private func makeTurns(speaker: (Int) -> String?) -> [AnalysisTurn] {
        var turns: [AnalysisTurn] = []
        for (index, text) in noisyTexts.enumerated() {
            turns.append(AnalysisTurn(id: "t\(index + 1)", text: text, start: Double(index * 5),
                                      end: Double(index * 5 + 4), speaker: speaker(index)))
        }
        return turns
    }

    private func reduce(_ turns: [AnalysisTurn], model: LocalAnalysisResult) -> ReducedMeetingAnalysis {
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "noisy-hindi", stage: .completed, turns: turns,
            speakers: [], analysis: [model], analyzedChunks: 1)
        return MeetingAnalysisReducer.reduce(checkpoint, participants: ["Neha", "Pawan"])
    }

    private var emptyModel: LocalAnalysisResult {
        LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
    }

    /// What the 1.7B model returned on the device after the reducer's first pass: a finalized date as a task,
    /// an undecided matter as a task with a sentence fragment as its deadline, and each commitment a second
    /// time with Devanagari left in the title.
    private var noisyModel: LocalAnalysisResult {
        let finalized = SourceEvidence(turnID: "t4", quote: "लोंच 20 नोवेंबर को ही फाइनल करते हैं")
        let undecided = SourceEvidence(turnID: "t14", quote: "डिजाइन चेंज करना है या नहीं, वो भी अभीते नहीं हुआ")
        let agendaPromise = SourceEvidence(turnID: "t9", quote: "मैं फ्राइडे तक अजेंड बना दूंगा")
        let presentationPromise = SourceEvidence(turnID: "t11", quote: "मैं कल तक प्रेजंटेशन भेज दूंगी")
        return LocalAnalysisResult(
            discussion: [],
            decisions: [SupportedPoint(text: "That the launch be held on November 20th.", evidence: [finalized])],
            tasks: [
                SuggestedTask(title: "Set the launch date for November 20th", category: "Follow-up", owner: "Pawan",
                              deadlineText: "by November 20th", priority: nil, evidence: [finalized]),
                SuggestedTask(title: "Confirm design change", category: "Follow-up", owner: "Neha",
                              deadlineText: "Abhite nahi hua", priority: nil, evidence: [undecided]),
                SuggestedTask(title: "Create अजेंड", category: "Create/Update", owner: "Pawan",
                              deadlineText: "फ्राइडे तक", priority: nil, evidence: [agendaPromise]),
                SuggestedTask(title: "Send प्रेजंटेशन", category: "Follow-up", owner: "Neha",
                              deadlineText: "कल तक", priority: nil, evidence: [presentationPromise])
            ])
    }

    private func assertExpectedMinutes(_ reduced: ReducedMeetingAnalysis, turns: [AnalysisTurn],
                                       file: StaticString = #filePath, line: UInt = #line) {
        let debug = "tasks=\(reduced.tasks.map { "\($0.title)|\($0.owner ?? "nil")|\($0.deadlineText ?? "nil")" }) decisions=\(reduced.decisions.map(\.text)) open=\(reduced.openIssues.map(\.text)) topics=\(reduced.agendaTopics) resolutions=\(reduced.minutes.resolutions.map(\.text)) summary=\(reduced.executiveSummary)"

        // Two tasks, in English, one per request and acceptance pair.
        XCTAssertEqual(reduced.tasks.count, 2, debug, file: file, line: line)
        let agenda = reduced.tasks.first { $0.title == "Prepare the agenda" }
        XCTAssertNotNil(agenda, debug, file: file, line: line)
        XCTAssertEqual(agenda?.owner, "Pawan", debug, file: file, line: line)
        XCTAssertEqual(MinutesComposer.englishDeadline(agenda?.deadlineText ?? ""), "by Friday", debug, file: file, line: line)
        let presentation = reduced.tasks.first { $0.title == "Send the presentation to the client" }
        XCTAssertNotNil(presentation, debug, file: file, line: line)
        XCTAssertEqual(presentation?.owner, "Neha", debug, file: file, line: line)
        XCTAssertEqual(MinutesComposer.englishDeadline(presentation?.deadlineText ?? ""), "by tomorrow", debug, file: file, line: line)
        XCTAssertFalse(reduced.tasks.contains { HindiText.containsDevanagari($0.title) }, debug, file: file, line: line)
        XCTAssertFalse(reduced.tasks.contains { $0.title.lowercased().contains("launch date") || $0.title.lowercased().contains("design") },
                       debug, file: file, line: line)

        // The English minutes carry the deadlines in English.
        XCTAssertEqual(Set(reduced.minutes.actions.compactMap(\.deadlineText)), ["by Friday", "by tomorrow"], debug, file: file, line: line)
        let stored = reduced.checkpoint.analysis.flatMap(\.tasks)
        XCTAssertEqual(Set(stored.compactMap(\.deadlineText)), ["by Friday", "by tomorrow"], debug, file: file, line: line)
        XCTAssertFalse(stored.contains { HindiText.containsDevanagari($0.title) }, debug, file: file, line: line)

        // Two decisions: the launch date and the Pune vendor, each once and in English.
        XCTAssertEqual(reduced.decisions.count, 2, debug, file: file, line: line)
        XCTAssertTrue(reduced.decisions.contains { $0.text.hasPrefix("Launch on 20 November") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.decisions.contains { $0.text.hasPrefix("Go with the Pune vendor") }, debug, file: file, line: line)
        XCTAssertFalse(reduced.decisions.contains { HindiText.containsDevanagari($0.text) }, debug, file: file, line: line)
        XCTAssertEqual(reduced.minutes.resolutions.count, 2, debug, file: file, line: line)
        XCTAssertTrue(reduced.minutes.resolutions.contains { $0.text == "That the launch be held on 20 November." }, debug, file: file, line: line)
        XCTAssertTrue(reduced.minutes.resolutions.contains { $0.text.hasPrefix("That the Pune vendor be engaged") }, debug, file: file, line: line)
        XCTAssertEqual(reduced.minutes.resolutions.last?.rationale, "lower price", debug, file: file, line: line)
        XCTAssertFalse(reduced.minutes.resolutions.contains { HindiText.containsDevanagari($0.text) }, debug, file: file, line: line)

        // Budget and design change stay open.
        XCTAssertEqual(reduced.openIssues.count, 2, debug, file: file, line: line)
        XCTAssertTrue(reduced.openIssues.contains { $0.text.lowercased().contains("budget") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.openIssues.contains { $0.text.lowercased().contains("design change") }, debug, file: file, line: line)
        XCTAssertFalse(reduced.openIssues.contains { HindiText.containsDevanagari($0.text) }, debug, file: file, line: line)

        // Agenda and summary.
        let topics = reduced.agendaTopics.map { $0.lowercased() }
        for expected in ["launch", "vendor", "budget"] {
            XCTAssertTrue(topics.contains { $0.contains(expected) }, debug, file: file, line: line)
        }
        XCTAssertTrue(topics.contains { $0.contains("design") }, debug, file: file, line: line)
        XCTAssertFalse(reduced.agendaTopics.contains { HindiText.containsDevanagari($0) }, debug, file: file, line: line)
        XCTAssertFalse(HindiText.containsDevanagari(reduced.executiveSummary), debug, file: file, line: line)
        XCTAssertTrue(reduced.executiveSummary.contains("20 November"), debug, file: file, line: line)
        XCTAssertTrue(reduced.executiveSummary.contains("Pune vendor"), debug, file: file, line: line)
        XCTAssertTrue(reduced.executiveSummary.contains("Pawan will prepare the agenda by Friday"), debug, file: file, line: line)
        XCTAssertTrue(reduced.discussion.contains { $0.text.hasPrefix("Launch date: proposed 20 November") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.discussion.contains { $0.text.hasPrefix("Vendor: Pune vendor preferred for lower price") }, debug, file: file, line: line)
        XCTAssertFalse(reduced.discussion.contains { HindiText.containsDevanagari($0.text) }, debug, file: file, line: line)

        // Every quote stays an exact substring of the turn it cites.
        let sources = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0.text) })
        var evidence: [SourceEvidence] = reduced.tasks.flatMap(\.evidence)
        evidence += reduced.decisions.flatMap(\.evidence)
        evidence += reduced.openIssues.flatMap(\.evidence)
        evidence += reduced.discussion.flatMap(\.evidence)
        evidence += reduced.minutes.actions.flatMap(\.evidence)
        evidence += reduced.minutes.resolutions.flatMap(\.evidence)
        for item in evidence {
            XCTAssertTrue(sources[item.turnID]?.contains(item.quote) == true, "Ungrounded quote: \(item.quote)",
                          file: file, line: line)
        }
    }

    // MARK: - Reduction

    func testNoisyTranscriptWithAnEmptyModelResult() {
        let turns = makeTurns(speaker: alternating)
        assertExpectedMinutes(reduce(turns, model: emptyModel), turns: turns)
    }

    func testNoisyTranscriptWithTheNoisyModelResult() {
        let turns = makeTurns(speaker: alternating)
        assertExpectedMinutes(reduce(turns, model: noisyModel), turns: turns)
    }

    func testNoisyTranscriptWhenEveryTurnCarriesTheSameVoiceLabel() {
        // With one label the request and its acceptance cannot be paired by voice, so the commitment is found
        // twice. It must still reduce to one task per owner and object.
        let turns = makeTurns(speaker: oneVoice)
        let reduced = reduce(turns, model: noisyModel)
        let debug = "tasks=\(reduced.tasks.map { "\($0.title)|\($0.owner ?? "nil")|\($0.deadlineText ?? "nil")" })"
        XCTAssertEqual(reduced.tasks.count, 2, debug)
        XCTAssertEqual(Set(reduced.tasks.map(\.title)), ["Prepare the agenda", "Send the presentation to the client"], debug)
        XCTAssertEqual(reduced.decisions.count, 2, reduced.decisions.map(\.text).joined(separator: " | "))
        XCTAssertEqual(reduced.openIssues.count, 2, reduced.openIssues.map(\.text).joined(separator: " | "))
    }

    func testFinalizedAndUndecidedSentencesAreNeverTasks() {
        let turns = makeTurns(speaker: alternating)
        let reduced = reduce(turns, model: noisyModel)
        let taskQuotes = reduced.tasks.flatMap(\.evidence).map(\.quote)
        XCTAssertFalse(taskQuotes.contains { $0.contains("फाइनल") }, "\(taskQuotes)")
        XCTAssertFalse(taskQuotes.contains { $0.contains("अभीते") }, "\(taskQuotes)")
    }

    // MARK: - Device model output

    /// What the 1.7B model returned on a device for this dialogue. It copies the owner and the deadline of the
    /// agenda task onto the presentation task, turns the budget question into a task, and claims that the
    /// design change was agreed although the transcript says it is still pending. Turn ids are 1-based.
    private var deviceModel: LocalAnalysisResult {
        let launchFinal = SourceEvidence(turnID: "t4", quote: "लोंच 20 नोवेंबर को ही फाइनल करते हैं")
        let puneChoice = SourceEvidence(turnID: "t7", quote: "लेट एस गो विद दिपुने वेंदर")
        let agendaRequest = SourceEvidence(turnID: "t8", quote: "पवन, क्या तुम फ्राइडे तक अजेंड तयार कर सकते हो")
        let presentationRequest = SourceEvidence(turnID: "t10", quote: "और निहा, तुम कल तक प्लायंट को प्रेजंटेशन भेज दोगी")
        let presentationPromise = SourceEvidence(turnID: "t11", quote: "मैं कल तक प्रेजंटेशन भेज दूंगी")
        let budgetQuestion = SourceEvidence(turnID: "t12", quote: "बजित का क्या करें, मार्केटिंग के लिए कितना रखें")
        let budgetOpen = SourceEvidence(turnID: "t13", quote: "बजट अभी डिसाइड नहीं हुआ है")
        let designOpen = SourceEvidence(turnID: "t14", quote: "डिजाइन चेंज करना है या नहीं, वो भी अभीते नहीं हुआ")
        let designPending = SourceEvidence(turnID: "t15", quote: "वो भी पेंडिंग है")
        let decisions: [SupportedPoint] = [
            SupportedPoint(text: "That the launch be held on 20 November.", evidence: [launchFinal]),
            SupportedPoint(text: "That the Pune vendor be engaged for the launch (preferred for lower price).", evidence: [puneChoice]),
            SupportedPoint(text: "That the design change be adopted.", evidence: [designOpen, designPending])
        ]
        let discussion: [SupportedPoint] = [
            SupportedPoint(text: "It was agreed to go with the design change.", evidence: [designOpen, designPending])
        ]
        let tasks: [SuggestedTask] = [
            SuggestedTask(title: "Prepare the agenda for the next meeting", category: "Create/Update", owner: "Pawan",
                          deadlineText: "Friday", priority: nil, evidence: [agendaRequest]),
            SuggestedTask(title: "Send launch presentation to client", category: "Follow-up", owner: "Pawan",
                          deadlineText: "Friday", priority: nil, evidence: [presentationRequest]),
            SuggestedTask(title: "Discuss budget for marketing", category: "Follow-up", owner: "Pawan",
                          deadlineText: "Friday", priority: nil, evidence: [budgetQuestion, budgetOpen]),
            SuggestedTask(title: "Send the launch presentation to the client", category: "Follow-up", owner: "Neha",
                          deadlineText: "by tomorrow", priority: nil, evidence: [presentationPromise])
        ]
        return LocalAnalysisResult(discussion: discussion, decisions: decisions, tasks: tasks)
    }

    func testDeviceModelOutputReducesToTheExpectedMinutes() {
        let turns = makeTurns(speaker: alternating)
        let reduced = reduce(turns, model: deviceModel)
        assertExpectedMinutes(reduced, turns: turns)
        let debug = "tasks=\(reduced.tasks.map { "\($0.title)|\($0.owner ?? "nil")|\($0.deadlineText ?? "nil")" }) decisions=\(reduced.decisions.map(\.text)) discussion=\(reduced.discussion.map(\.text)) summary=\(reduced.executiveSummary)"

        // Tasks: the borrowed owner and deadline never reach the presentation task, and the budget question is no task.
        XCTAssertEqual(reduced.tasks.map { $0.owner ?? "nil" }, ["Pawan", "Neha"], debug)
        XCTAssertFalse(reduced.tasks.contains { $0.title.lowercased().contains("budget") || $0.title.lowercased().contains("discuss") }, debug)
        let stored = reduced.checkpoint.analysis.flatMap(\.tasks)
        XCTAssertEqual(stored.count, 2, debug)
        XCTAssertEqual(stored.map { $0.owner ?? "nil" }, ["Pawan", "Neha"], debug)
        XCTAssertEqual(stored.map { $0.deadlineText ?? "nil" }, ["by Friday", "by tomorrow"], debug)
        XCTAssertTrue(stored.first?.title.hasPrefix("Prepare the agenda") == true, debug)

        // The design change is open, never agreed.
        XCTAssertFalse(reduced.decisions.contains { $0.text.lowercased().contains("design") }, debug)
        XCTAssertFalse(reduced.minutes.resolutions.contains { $0.text.lowercased().contains("design") }, debug)
        XCTAssertFalse(reduced.discussion.contains { $0.text.lowercased().contains("agreed") }, debug)
        XCTAssertFalse(reduced.executiveSummary.lowercased().contains("go with the design change"), debug)

        // The summary names each deadline once, with "by".
        let summary = reduced.executiveSummary
        XCTAssertFalse(summary.contains("Friday Friday"), debug)
        XCTAssertEqual(summary.components(separatedBy: "by Friday").count - 1, 1, debug)
        XCTAssertEqual(summary.components(separatedBy: "by tomorrow").count - 1, 1, debug)
        XCTAssertFalse(summary.contains("agenda Friday"), debug)
        XCTAssertFalse(summary.lowercased().contains("budget for marketing"), debug)
    }

    func testDiscussionTasksAreNotActions() {
        let turns = makeTurns(speaker: alternating)
        let question = SourceEvidence(turnID: "t12", quote: "बजित का क्या करें, मार्केटिंग के लिए कितना रखें")
        let model = LocalAnalysisResult(discussion: [], decisions: [], tasks: [
            SuggestedTask(title: "Discuss the budget for marketing", category: "Follow-up", owner: nil, deadlineText: nil,
                          priority: nil, evidence: [question]),
            SuggestedTask(title: "Talk about the marketing budget", category: "Follow-up", owner: nil, deadlineText: nil,
                          priority: nil, evidence: [question])
        ])
        let reduced = reduce(turns, model: model)
        let titles = reduced.tasks.map(\.title)
        XCTAssertEqual(reduced.tasks.count, 2, "\(titles)")
        XCTAssertFalse(titles.contains { $0.lowercased().contains("budget") || $0.lowercased().contains("discuss") }, "\(titles)")
    }

    func testModelOwnerAndDeadlineMustComeFromTheCitedTurns() {
        let turns = makeTurns(speaker: alternating)
        let source = TaskGrounding.source(turns: turns, participants: ["Neha", "Pawan"], speakerNames: [:])
        let request = [SourceEvidence(turnID: "t10", quote: "और निहा, तुम कल तक प्लायंट को प्रेजंटेशन भेज दोगी")]
        XCTAssertNil(TaskGrounding.groundedOwner("Pawan", evidence: request, source: source))
        XCTAssertEqual(TaskGrounding.groundedOwner("Neha", evidence: request, source: source), "Neha")
        XCTAssertNil(TaskGrounding.groundedDeadline("Friday", evidence: request, source: source))
        XCTAssertEqual(TaskGrounding.groundedDeadline("by tomorrow", evidence: request, source: source), "by tomorrow")
        XCTAssertEqual(TaskGrounding.groundedDeadline("कल तक", evidence: request, source: source), "कल तक")
        XCTAssertEqual(TaskGrounding.groundedDeadline("ASAP", evidence: request, source: source), "ASAP")
        // A promise that names nobody cannot contradict the owner.
        let promise = [SourceEvidence(turnID: "t11", quote: "मैं कल तक प्रेजंटेशन भेज दूंगी")]
        XCTAssertEqual(TaskGrounding.groundedOwner("Neha", evidence: promise, source: source), "Neha")
        XCTAssertEqual(TaskGrounding.timeIdentity("फ्राइडे तक"), ["friday"])
        XCTAssertEqual(TaskGrounding.timeIdentity("by tomorrow"), ["tomorrow"])
        XCTAssertEqual(TaskGrounding.timeIdentity("20th November"), ["20", "november"])
    }

    func testModelDecisionAboutAnOpenMatterIsDroppedInEnglishToo() {
        let turns = MinutesFixtures.turns(MinutesFixtures.english)
        let claim = SupportedPoint(text: "That the design change be adopted.",
                                   evidence: [SourceEvidence(turnID: "t13", quote: "We will discuss it in the next meeting.")])
        let model = LocalAnalysisResult(discussion: [], decisions: [claim], tasks: [])
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "english", stage: .completed, turns: turns,
            speakers: [], analysis: [model], analyzedChunks: 1)
        let reduced = MeetingAnalysisReducer.reduce(checkpoint, participants: ["Neha", "Pawan"])
        XCTAssertEqual(reduced.decisions.count, 2, reduced.decisions.map(\.text).joined(separator: " | "))
        XCTAssertFalse(reduced.decisions.contains { $0.text.lowercased().contains("design") })
        XCTAssertEqual(reduced.openIssues.count, 2, reduced.openIssues.map(\.text).joined(separator: " | "))
    }

    // MARK: - Summary wording

    func testSummaryNamesEachDeadlineOnceWithBy() {
        let tasks = [
            SuggestedTask(title: "Send presentation to client by Friday", category: "Follow-up", owner: "Pawan",
                          deadlineText: "Friday", priority: nil, evidence: []),
            SuggestedTask(title: "Prepare the agenda", category: "Create/Update", owner: "Pawan",
                          deadlineText: "Friday", priority: nil, evidence: []),
            SuggestedTask(title: "Send the report", category: "Follow-up", owner: nil,
                          deadlineText: "by Friday Friday", priority: nil, evidence: [])
        ]
        let summary = MinutesComposer.executiveSummary(names: [], topics: [], decisionPhrases: [], tasks: tasks, openSubjects: [])
        XCTAssertEqual(summary, "Pawan will send presentation to client by Friday; Pawan will prepare the agenda by Friday; "
            + "To do: send the report by Friday.")
        XCTAssertEqual(MinutesComposer.summaryDeadline("tomorrow"), "by tomorrow")
        XCTAssertEqual(MinutesComposer.summaryDeadline("कल तक"), "by tomorrow")
        XCTAssertEqual(MinutesComposer.summaryDeadline("20 November"), "by 20 November")
        XCTAssertEqual(MinutesComposer.summaryDeadline("next week"), "next week")
        XCTAssertEqual(MinutesComposer.summaryDeadline("ASAP"), "ASAP")
    }

    // MARK: - Loanwords

    func testPhoneticLoanwordsResolveToEnglish() {
        let expected: [(String, String)] = [
            ("लोंज", "launch"), ("लौंच", "launch"), ("लोंच", "launch"), ("बज़त", "budget"), ("बजित", "budget"),
            ("बजट", "budget"), ("नोवेंबर", "November"), ("अजेंड", "agenda"), ("अजेंडा", "agenda"),
            ("प्रेजंटेशन", "presentation"), ("प्लायंट", "client"), ("वेंदर", "vendor"), ("फ्राइडे", "Friday"),
            ("डिसाइड", "decide"), ("डिजाइन", "design"), ("चेंज", "change"), ("फाइनल", "final"),
            ("पेंडिंग", "pending"), ("मीटिंग", "meeting"), ("प्राइस", "price"), ("मार्केटिंग", "marketing"),
            ("पुने", "Pune"), ("पुणे", "Pune")
        ]
        for (word, english) in expected {
            XCTAssertEqual(HindiText.lookup(HindiText.normalized(word)), english, word)
        }
    }

    func testNamesAndHindiWordsAreNotMistakenForLoanwords() {
        for word in ["पवन", "नेहा", "निहा", "नहा", "रोहन", "पारस", "बाजार", "किताब", "कमरा", "रखें"] {
            XCTAssertFalse(HindiText.isKnownWord(word), word)
        }
        XCTAssertEqual(HindiText.lookup(HindiText.normalized("दोस्त")), "dost")
        XCTAssertEqual(HindiText.lookup(HindiText.normalized("लंच")), "lunch")
    }

    func testFusedWordsSplitIntoTwoTokensWithExactRanges() {
        let text = "हाँ, लेट एस गो विद दिपुने वेंदर।"
        let tokens = HindiText.tokenize(text)
        XCTAssertEqual(tokens.map(\.key), ["haan", "lets", "go", "with", "the", "pune", "vendor"])
        XCTAssertTrue(tokens.allSatisfy { $0.isKnown })
        XCTAssertEqual(HindiText.text(of: tokens, in: text), text)
        let source = "पुनेवाला वेंदर"
        let fused = HindiText.tokenize(source)
        XCTAssertEqual(fused.map(\.key), ["pune", "wala", "vendor"])
        guard fused.count == 3 else { return }
        XCTAssertEqual(String(source[fused[0].start..<fused[0].end]), "पुने")
        XCTAssertEqual(String(source[fused[1].start..<fused[1].end]), "वाला")
    }

    func testLatinMisspellingOfVendorIsRestored() {
        let tokens = HindiText.tokenize("Wendor के बारे में")
        XCTAssertEqual(tokens.first?.key, "vendor")
        XCTAssertEqual(tokens.first?.display, "vendor")
        XCTAssertEqual(tokens.first?.raw, "Wendor")
    }

    func testModelPromptReadsLoanwordsAsEnglish() {
        let turn = AnalysisTurn(id: "t1", text: noisyTexts[3], start: 0, end: 4, speaker: nil)
        let roman = PromptNormalizer.romanized([turn])[0].text
        XCTAssertTrue(roman.contains("launch 20 November"), roman)
        XCTAssertFalse(HindiText.containsDevanagari(roman), roman)
        let lets = HindiRomanizer.romanize(noisyTexts[6])
        XCTAssertTrue(lets.contains("let's go with the Pune vendor"), lets)
        let budget = HindiRomanizer.romanize(noisyTexts[11])
        XCTAssertTrue(budget.lowercased().hasPrefix("budget"), budget)
    }

    func testEnglishPhraseTranslatesLoanwordsAndSpellsTheRest() {
        XCTAssertEqual(HindiText.englishPhrase("Create अजेंड"), "Create agenda")
        XCTAssertEqual(HindiText.englishPhrase("Send प्रेजंटेशन"), "Send presentation")
        XCTAssertEqual(HindiText.englishPhrase("Prepare the agenda"), "Prepare the agenda")
        XCTAssertFalse(HindiText.containsDevanagari(HindiText.englishPhrase("Send टेंडर")))
    }

    // MARK: - Deadlines

    func testModelDeadlineThatIsNotATimeIsDropped() {
        XCTAssertNil(MeetingAnalysisReducer.plausibleDeadline("Abhite nahi hua"))
        XCTAssertNil(MeetingAnalysisReducer.plausibleDeadline(nil))
        XCTAssertEqual(MeetingAnalysisReducer.plausibleDeadline("by Friday"), "by Friday")
        XCTAssertEqual(MeetingAnalysisReducer.plausibleDeadline("कल तक"), "कल तक")
        XCTAssertEqual(MeetingAnalysisReducer.plausibleDeadline("फ्राइडे तक"), "फ्राइडे तक")
        XCTAssertEqual(MeetingAnalysisReducer.plausibleDeadline("20 November"), "20 November")
        XCTAssertEqual(MeetingAnalysisReducer.plausibleDeadline("ASAP"), "ASAP")
        XCTAssertEqual(MinutesComposer.englishDeadline("फ्राइडे तक"), "by Friday")
    }
}
