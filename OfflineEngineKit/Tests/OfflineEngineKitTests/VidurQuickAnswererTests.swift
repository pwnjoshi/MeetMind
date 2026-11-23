import XCTest
@testable import OfflineEngineKit

/// Measures Vidur's instant tiers on realistic English, Hinglish and Devanagari questions.
final class VidurEvaluationTests: XCTestCase {
    private func run(_ test: VidurEvalCase) -> VidurQuickAnswer {
        VidurQuickAnswerer.answer(question: test.question, records: VidurEvalFixtures.all, history: test.history,
                                  selfNames: VidurEvalFixtures.selfNames, now: VidurEvalFixtures.now,
                                  calendar: VidurEvalFixtures.calendar)
    }

    private func failures(for test: VidurEvalCase, answer: VidurQuickAnswer) -> [String] {
        var problems: [String] = []
        let text = answer.text.lowercased()
        for needle in test.contains where !text.contains(needle.lowercased()) {
            problems.append("missing \u{201C}\(needle)\u{201D}")
        }
        if !test.containsAny.isEmpty, !test.containsAny.contains(where: { text.contains($0.lowercased()) }) {
            problems.append("none of \(test.containsAny) present")
        }
        for needle in test.excludes where text.contains(needle.lowercased()) {
            problems.append("unexpected \u{201C}\(needle)\u{201D}")
        }
        if !test.confidences.contains(VidurQuickConfidenceExpectation(answer.confidence)) {
            problems.append("confidence \(answer.confidence)")
        }
        let titles = Set(answer.sources.map(\.meetingTitle))
        for title in test.sourceMeetings where !titles.contains(title) {
            problems.append("no source from \(title)")
        }
        for person in test.people where !answer.people.contains(person) {
            problems.append("person \(person) missing from \(answer.people)")
        }
        if let intent = test.intent, answer.intent != intent {
            problems.append("intent \(answer.intent) instead of \(intent)")
        }
        if test.needsSource, answer.confidence != .notFound, answer.sources.isEmpty {
            problems.append("answer has no sources")
        }
        if answer.confidence == .notFound, answer.suggestions.isEmpty { problems.append("no suggestions") }
        return problems
    }

    func testEveryFixtureAnswersCorrectly() {
        let cases = VidurEvalCases.all
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        var passed = 0
        for test in cases {
            let answer = run(test)
            let problems = failures(for: test, answer: answer)
            if problems.isEmpty {
                passed += 1
            } else {
                XCTFail("[\(test.id)] \(test.question) -> \(problems.joined(separator: "; "))\nANSWER: \(answer.text)")
            }
        }
        print("VidurEval instant tiers: \(passed)/\(cases.count) fixtures pass")
    }

    func testFixtureIDsAreUnique() {
        let ids = VidurEvalCases.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryAnswerIsQuickAndBounded() {
        for test in VidurEvalCases.all {
            let started = Date()
            let answer = run(test)
            XCTAssertLessThan(Date().timeIntervalSince(started), 0.3, test.id)
            XCTAssertLessThan(answer.text.count, 1_800, "\(test.id) answer should stay short")
            XCTAssertLessThanOrEqual(answer.sources.count, 5, test.id)
        }
    }

    func testLargeLibraryStaysFast() {
        var records: [VidurMeetingRecord] = []
        for number in 0..<20 {
            var turns: [VidurMeetingTurn] = []
            for line in 0..<200 {
                turns.append(VidurMeetingTurn(
                    text: "Item \(line) of review \(number): the vendor invoice, rollout schedule and hiring plan need follow up.",
                    start: Double(line * 10), speaker: line % 2 == 0 ? "Neha Sharma" : "Pawan Kumar"))
            }
            records.append(VidurMeetingRecord(title: "Review \(number)", date: VidurEvalFixtures.date(2025, 10, 1 + number % 28),
                                              attendees: ["Neha Sharma", "Pawan Kumar"], turns: turns))
        }
        let started = Date()
        let answer = VidurQuickAnswerer.answer(question: "What did Pawan say about the vendor invoice?", records: records,
                                               now: VidurEvalFixtures.now, calendar: VidurEvalFixtures.calendar)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertNotEqual(answer.confidence, .notFound)
        // Generous bound for a debug build on a CI machine. A release build on device is far faster.
        XCTAssertLessThan(elapsed, 3.0, "4,000 turns searched in \(elapsed)s")
    }

    func testEmptyLibraryIsTruthful() {
        let answer = VidurQuickAnswerer.answer(question: "What did we decide?", records: [], now: VidurEvalFixtures.now,
                                               calendar: VidurEvalFixtures.calendar)
        XCTAssertTrue(answer.text.contains("no saved meetings"))
        XCTAssertTrue(answer.sources.isEmpty)
    }

    func testNoMeetingsInTheRequestedPeriodIsStatedPlainly() {
        let answer = VidurQuickAnswerer.answer(question: "What did we decide last month?", records: [VidurEvalFixtures.designReview],
                                               now: VidurEvalFixtures.now, calendar: VidurEvalFixtures.calendar)
        XCTAssertTrue(answer.text.contains("couldn\u{2019}t find any meetings last month"), answer.text)
    }
}

final class VidurScriptTests: XCTestCase {
    func testSkeletonsMatchAcrossScripts() {
        XCTAssertEqual(VidurScript.skeleton("Pawan"), VidurScript.skeleton("पवन"))
        XCTAssertEqual(VidurScript.skeleton("Rahul"), VidurScript.skeleton("राहुल"))
        XCTAssertEqual(VidurScript.skeleton("vendor"), VidurScript.skeleton("वेंडर"))
        XCTAssertEqual(VidurScript.skeleton("launch"), VidurScript.skeleton("लॉन्च"))
        XCTAssertEqual(VidurScript.skeleton("Arjun"), VidurScript.skeleton("अर्जुन"))
        XCTAssertEqual(VidurScript.skeleton("meeting"), VidurScript.skeleton("मीटिंग"))
        XCTAssertEqual(VidurScript.skeleton("pricing"), VidurScript.skeleton("प्राइसिंग"))
    }

    func testPersonIndexMergesSpellingsAndKeepsLatinName() {
        let index = VidurPersonIndex(names: ["पवन", "Pawan Kumar", "S1", "Speaker 2", "Neha Sharma", "नेहा", "Nina Rao"])
        XCTAssertEqual(index.people.map(\.canonical), ["Pawan Kumar", "Neha Sharma", "Nina Rao"])
        XCTAssertEqual(index.person(forWord: "pawan")?.canonical, "Pawan Kumar")
        XCTAssertEqual(index.person(forWord: "पवन")?.canonical, "Pawan Kumar")
        XCTAssertEqual(index.person(forWord: "नेहा")?.canonical, "Neha Sharma")
        XCTAssertNotEqual(index.person(forWord: "nina")?.canonical, "Neha Sharma")
        XCTAssertNil(index.person(forWord: "vendor"))
    }

    func testGenericSpeakerLabels() {
        for label in ["S1", "s12", "Speaker 3", "speaker_4", "Note", "Unknown speaker"] {
            XCTAssertTrue(VidurPersonIndex.isGenericLabel(label), label)
        }
        XCTAssertFalse(VidurPersonIndex.isGenericLabel("Sam"))
    }

    func testKeysBridgeEnglishAndDevanagari() {
        let english = Set(VidurScript.keys("vendor payment"))
        let hindi = Set(VidurScript.keys("वेंडर पेमेंट"))
        XCTAssertFalse(english.isDisjoint(with: hindi))
        XCTAssertTrue(Set(VidurScript.keys("budget")).contains("cx:budget"))
        XCTAssertTrue(Set(VidurScript.keys("बजट")).contains("cx:budget"))
    }
}

final class VidurQuestionParserTests: XCTestCase {
    private let index = VidurPersonIndex(names: ["Neha Sharma", "Pawan Kumar"])
    private func parse(_ question: String) -> VidurParsedQuestion {
        VidurQuestionParser.parse(question, index: index, titles: ["Weekly sync"], now: VidurEvalFixtures.now,
                                  calendar: VidurEvalFixtures.calendar)
    }

    func testTimePhrases() {
        XCTAssertEqual(parse("what happened last week").rangeLabel, "last week")
        XCTAssertEqual(parse("summary of this week").rangeLabel, "this week")
        XCTAssertEqual(parse("pichhle hafte kya hua").rangeLabel, "last week")
        XCTAssertEqual(parse("what did we decide today").rangeLabel, "today")
        XCTAssertEqual(parse("decisions last month").rangeLabel, "last month")
        XCTAssertTrue(parse("what was the last meeting about").lastMeeting)
    }

    func testDueRangeIsOnlyUsedForDueQuestions() {
        XCTAssertNotNil(parse("tasks due this week").dueRange)
        XCTAssertNil(parse("tasks due this week").meetingRange)
        XCTAssertNotNil(parse("what did Pawan promise this week").meetingRange)
        XCTAssertNil(parse("what did Pawan promise this week").dueRange)
        XCTAssertNotNil(parse("what is due tomorrow").dueRange)
    }

    func testIntents() {
        XCTAssertEqual(parse("What did we decide?").intents, [.decisions])
        XCTAssertEqual(parse("Who was absent?").intents, [.absent])
        XCTAssertEqual(parse("When is the next meeting?").intents, [.nextMeeting])
        XCTAssertEqual(parse("Pending for Neha").intents, [.tasks])
        XCTAssertEqual(parse("Kya tay hua?").intents, [.decisions])
        XCTAssertEqual(parse("फैसले क्या थे?").intents, [.decisions])
        XCTAssertEqual(parse("Why did the vendor delay shipment?").intents, [.topic])
        XCTAssertTrue(parse("Why did the vendor delay shipment?").wantsReasoning)
    }

    func testTopicWordsTurnSummaryIntoSearch() {
        let parsed = parse("What did we discuss about pricing?")
        XCTAssertEqual(parsed.intents, [.topic])
        XCTAssertEqual(parsed.residual, ["pricing"])
    }

    func testMeetingTitleScopesTheQuestion() {
        let parsed = parse("Who attended the weekly sync?")
        XCTAssertEqual(parsed.matchedTitles, ["Weekly sync"])
        XCTAssertEqual(parsed.intents, [.attendees])
        XCTAssertTrue(parsed.residual.isEmpty)
        XCTAssertEqual(parse("Summarize Weekly sync").intents, [.summary])
        XCTAssertTrue(parse("Who attended the weekly meeting?").matchedTitles.isEmpty)
    }

    func testPeopleAreFoundInDevanagariToo() {
        XCTAssertEqual(parse("पवन का काम क्या है").people.map(\.canonical), ["Pawan Kumar"])
        XCTAssertEqual(parse("पवन का काम क्या है").intents, [.tasks])
    }
}
