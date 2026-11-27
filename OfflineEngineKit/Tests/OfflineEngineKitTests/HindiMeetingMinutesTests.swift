import XCTest
@testable import OfflineEngineKit

/// The real-device script spoken in Hindi by Neha and Pawan, in the three transcript shapes Whisper produces.
final class HindiMeetingMinutesTests: XCTestCase {
    private struct Line {
        let speaker: String?
        let text: String
    }

    // (a) Devanagari with English words in Latin script.
    private let latinWords: [Line] = [
        Line(speaker: "S1", text: "हाय पवन, चलो आज की मीटिंग शुरू करते हैं। आज हमें launch और budget पर बात करनी है।"),
        Line(speaker: "S2", text: "हाँ नेहा, ठीक है। पहले launch date की बात कर लेते हैं।"),
        Line(speaker: "S1", text: "मुझे लगता है हमें 20 November को launch करना चाहिए। तुम्हें क्या लगता है?"),
        Line(speaker: "S2", text: "हाँ, 20 November सही रहेगा। चलो, launch 20 November को ही final करते हैं।"),
        Line(speaker: "S1", text: "ठीक है, यह final है। अब vendor के बारे में बात करते हैं।"),
        Line(speaker: "S2", text: "मेरे हिसाब से Pune वाला vendor अच्छा है, उसका price भी कम है।"),
        Line(speaker: "S1", text: "हाँ, let's go with the Pune vendor."),
        Line(speaker: "S1", text: "पवन, क्या तुम Friday तक agenda तैयार कर सकते हो?"),
        Line(speaker: "S2", text: "हाँ, ज़रूर। मैं Friday तक agenda बना दूँगा।"),
        Line(speaker: "S2", text: "और नेहा, तुम कल तक client को presentation भेज दोगी?"),
        Line(speaker: "S1", text: "हाँ, मैं कल तक presentation भेज दूँगी।"),
        Line(speaker: "S2", text: "Budget का क्या करें? Marketing के लिए कितना रखें?"),
        Line(speaker: "S1", text: "Budget अभी decide नहीं हुआ है। उस पर अगली मीटिंग में बात करेंगे।"),
        Line(speaker: "S2", text: "ठीक है। Design change करना है या नहीं, वो भी अभी तय नहीं हुआ।"),
        Line(speaker: "S1", text: "हाँ, वो भी pending है। ठीक है, आज के लिए इतना ही। Thank you पवन।")
    ]

    // (b) English loanwords transliterated, "या" for "यह", punctuation missing between some sentences.
    private let transliterated: [Line] = [
        Line(speaker: nil, text: "हाय पवन, चलो आज की मीटिंग शुरू करते हैं। आज हमें लॉन्च और बजट पर बात करनी है।"),
        Line(speaker: nil, text: "हाँ नेहा, ठीक है। पहले लॉन्च डेट की बात कर लेते हैं।"),
        Line(speaker: nil, text: "मुझे लगता है हमें 20 नवंबर को लॉन्च करना चाहिए। तुम्हें क्या लगता है?"),
        Line(speaker: nil, text: "हाँ, 20 नवंबर सही रहेगा। चलो, लॉन्च 20 नवंबर को ही फाइनल करते हैं।"),
        Line(speaker: nil, text: "ठीक है या फाइनल है अब वेंडर के बारे में बात करते हैं"),
        Line(speaker: nil, text: "मेरे हिसाब से पुणे वाला वेंडर अच्छा है, उसका प्राइस भी कम है।"),
        Line(speaker: nil, text: "हाँ, लेट्स गो विद द पुणे वेंडर"),
        Line(speaker: nil, text: "पवन, क्या तुम फ्राइडे तक एजेंडा तैयार कर सकते हो?"),
        Line(speaker: nil, text: "हाँ ज़रूर मैं फ्राइडे तक एजेंडा बना दूँगा"),
        Line(speaker: nil, text: "और नेहा, तुम कल तक क्लाइंट को प्रेजेंटेशन भेज दोगी?"),
        Line(speaker: nil, text: "हाँ, मैं कल तक प्रेजेंटेशन भेज दूँगी।"),
        Line(speaker: nil, text: "बजट का क्या करें? मार्केटिंग के लिए कितना रखें?"),
        Line(speaker: nil, text: "बजट अभी डिसाइड नहीं हुआ है उस पर अगली मीटिंग में बात करेंगे"),
        Line(speaker: nil, text: "ठीक है डिज़ाइन चेंज करना है या नहीं वो भी अभी तय नहीं हुआ"),
        Line(speaker: nil, text: "हाँ वो भी पेंडिंग है ठीक है आज के लिए इतना ही थैंक यू पवन")
    ]

    private func reduce(_ lines: [Line], participants: [String] = [], speakerNames: [String: String] = [:])
        -> (reduced: ReducedMeetingAnalysis, turns: [AnalysisTurn]) {
        var turns: [AnalysisTurn] = []
        for (index, line) in lines.enumerated() {
            turns.append(AnalysisTurn(id: "t\(index + 1)", text: line.text, start: Double(index * 5),
                                      end: Double(index * 5 + 4), speaker: line.speaker))
        }
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "hindi", stage: .completed, turns: turns, speakers: [],
            analysis: [LocalAnalysisResult(discussion: [], decisions: [], tasks: [])], analyzedChunks: 1)
        return (MeetingAnalysisReducer.reduce(checkpoint, participants: participants, speakerNames: speakerNames), turns)
    }

    private func assertFullMinutes(_ lines: [Line], participants: [String], speakerNames: [String: String] = [:],
                                   ownersKnown: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let (reduced, turns) = reduce(lines, participants: participants, speakerNames: speakerNames)
        let debug = "tasks=\(reduced.tasks.map { "\($0.title)|\($0.owner ?? "nil")|\($0.deadlineText ?? "nil")" }) decisions=\(reduced.decisions.map(\.text)) open=\(reduced.openIssues.map(\.text)) topics=\(reduced.agendaTopics) summary=\(reduced.executiveSummary)"

        XCTAssertEqual(reduced.tasks.count, 2, debug, file: file, line: line)
        let agenda = reduced.tasks.first { $0.title == "Prepare the agenda" }
        XCTAssertNotNil(agenda, debug, file: file, line: line)
        if ownersKnown { XCTAssertEqual(agenda?.owner, "Pawan", debug, file: file, line: line) }
        let agendaDeadline = agenda?.deadlineText ?? ""
        XCTAssertTrue(agendaDeadline.hasSuffix("\u{0924}\u{0915}") && (agendaDeadline.contains("Friday") || agendaDeadline.contains("\u{092B}\u{094D}\u{0930}\u{093E}\u{0907}\u{0921}\u{0947}")),
                      debug, file: file, line: line)
        let presentation = reduced.tasks.first { $0.title == "Send the presentation to the client" }
        XCTAssertNotNil(presentation, debug, file: file, line: line)
        if ownersKnown { XCTAssertEqual(presentation?.owner, "Neha", debug, file: file, line: line) }
        XCTAssertEqual(presentation?.deadlineText, "\u{0915}\u{0932} \u{0924}\u{0915}", debug, file: file, line: line)

        XCTAssertEqual(reduced.decisions.count, 2, debug, file: file, line: line)
        XCTAssertTrue(reduced.decisions.contains { $0.text.hasPrefix("Launch on 20 November") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.decisions.contains { $0.text.hasPrefix("Go with the Pune vendor") }, debug, file: file, line: line)

        XCTAssertEqual(reduced.openIssues.count, 2, debug, file: file, line: line)
        XCTAssertTrue(reduced.openIssues.contains { $0.text.lowercased().contains("budget") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.openIssues.contains { $0.text.lowercased().contains("design change") }, debug, file: file, line: line)

        let topics = reduced.agendaTopics.map { $0.lowercased() }
        for expected in ["launch", "vendor", "budget"] {
            XCTAssertTrue(topics.contains { $0.contains(expected) }, debug, file: file, line: line)
        }

        XCTAssertFalse(HindiText.containsDevanagari(reduced.executiveSummary), debug, file: file, line: line)
        XCTAssertTrue(reduced.executiveSummary.contains("20 November"), debug, file: file, line: line)
        XCTAssertTrue(reduced.executiveSummary.contains("Pune vendor"), debug, file: file, line: line)
        XCTAssertTrue(reduced.discussion.contains { $0.text.hasPrefix("Launch date: proposed 20 November") }, debug, file: file, line: line)
        XCTAssertTrue(reduced.discussion.contains { $0.text.hasPrefix("Vendor: Pune vendor preferred for lower price") }, debug, file: file, line: line)

        // Every quote must be an exact substring of its cited turn.
        let sources = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0.text) })
        let evidence = reduced.tasks.flatMap(\.evidence) + reduced.decisions.flatMap(\.evidence)
            + reduced.openIssues.flatMap(\.evidence) + reduced.discussion.flatMap(\.evidence)
        for item in evidence {
            XCTAssertTrue(sources[item.turnID]?.contains(item.quote) == true, "Ungrounded quote: \(item.quote)", file: file, line: line)
        }
    }

    func testDevanagariWithLatinEnglishWords() {
        assertFullMinutes(latinWords.map { Line(speaker: nil, text: $0.text) }, participants: ["Neha", "Pawan"])
    }

    func testTransliteratedLoanwordsWithMissingPunctuation() {
        assertFullMinutes(transliterated, participants: ["Neha", "Pawan"])
    }

    func testSpeakerLabelledTurnsWithParticipantsOnly() {
        assertFullMinutes(latinWords, participants: ["Neha", "Pawan"])
    }

    func testSpeakerLabelledTurnsWithMappedVoices() {
        assertFullMinutes(latinWords, participants: ["Neha", "Pawan"], speakerNames: ["S1": "Neha", "S2": "Pawan"])
    }

    func testNamesAreTransliteratedWhenNoParticipantsAreKnown() {
        let (reduced, _) = reduce(latinWords)
        XCTAssertEqual(reduced.tasks.first { $0.title == "Prepare the agenda" }?.owner, "Pawan")
        XCTAssertEqual(reduced.tasks.first { $0.title == "Send the presentation to the client" }?.owner, "Neha")
        XCTAssertEqual(reduced.decisions.count, 2)
        XCTAssertEqual(reduced.openIssues.count, 2)
    }

    func testSummaryNamesTheParticipantsAndOutcomes() {
        let (reduced, _) = reduce(latinWords, participants: ["Neha", "Pawan"])
        XCTAssertTrue(reduced.executiveSummary.hasPrefix("Neha and Pawan discussed the"), reduced.executiveSummary)
        XCTAssertTrue(reduced.executiveSummary.contains("Pawan will prepare the agenda by Friday"), reduced.executiveSummary)
        XCTAssertTrue(reduced.executiveSummary.contains("Neha will send the presentation to the client by tomorrow"), reduced.executiveSummary)
        XCTAssertTrue(reduced.executiveSummary.contains("remain open"), reduced.executiveSummary)
    }

    func testDeclinedRequestProducesNoTask() {
        let lines = [
            Line(speaker: "S1", text: "पवन, क्या तुम Friday तक agenda तैयार कर सकते हो?"),
            Line(speaker: "S2", text: "नहीं, मैं नहीं कर पाऊँगा।")
        ]
        let (reduced, _) = reduce(lines, participants: ["Pawan"])
        XCTAssertTrue(reduced.tasks.isEmpty, "\(reduced.tasks.map(\.title))")
    }

    func testCommonRequestAndPromiseShapes() {
        let lines = [
            Line(speaker: nil, text: "पवन, report कल तक भेज देना।"),
            Line(speaker: nil, text: "नेहा को client को proposal भेजना है।"),
            Line(speaker: nil, text: "पवन budget देख लेगा।")
        ]
        let (reduced, _) = reduce(lines, participants: ["Neha", "Pawan"])
        let titles = reduced.tasks.map(\.title)
        XCTAssertTrue(titles.contains("Send the report"), "\(titles)")
        XCTAssertEqual(reduced.tasks.first { $0.title == "Send the report" }?.owner, "Pawan")
        XCTAssertEqual(reduced.tasks.first { $0.title == "Send the report" }?.deadlineText, "\u{0915}\u{0932} \u{0924}\u{0915}")
        XCTAssertTrue(titles.contains("Send the proposal to the client"), "\(titles)")
        XCTAssertEqual(reduced.tasks.first { $0.title == "Send the proposal to the client" }?.owner, "Neha")
        XCTAssertTrue(titles.contains("Review the budget"), "\(titles)")
    }

    func testModelFragmentsInHindiNeverBecomeTheSummary() {
        var turns: [AnalysisTurn] = []
        for (index, line) in latinWords.enumerated() {
            turns.append(AnalysisTurn(id: "t\(index + 1)", text: line.text, start: Double(index), end: Double(index + 1), speaker: line.speaker))
        }
        let fragment = "ठीक है या final है अब vendor के बारे में"
        let model = LocalAnalysisResult(
            discussion: [SupportedPoint(text: fragment, evidence: [SourceEvidence(turnID: "t5", quote: "ठीक है, यह final है।")])],
            decisions: [], tasks: [])
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "frag", stage: .completed, turns: turns, speakers: [],
                                                   analysis: [model], analyzedChunks: 1)
        let reduced = MeetingAnalysisReducer.reduce(checkpoint, participants: ["Neha", "Pawan"])
        XCTAssertFalse(HindiText.containsDevanagari(reduced.executiveSummary))
        XCTAssertFalse(reduced.discussion.contains { HindiText.containsDevanagari($0.text) })
    }

    func testEnglishAgendaStatementFillsAgendaTopics() {
        let turn = AnalysisTurn(id: "t1", text: "Today we'll discuss pricing and hiring.", start: 0, end: 2, speaker: nil)
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "en", stage: .completed, turns: [turn], speakers: [],
            analysis: [LocalAnalysisResult(discussion: [], decisions: [], tasks: [])], analyzedChunks: 1)
        let reduced = MeetingAnalysisReducer.reduce(checkpoint)
        XCTAssertEqual(reduced.agendaTopics, ["Pricing", "Hiring"])
    }

    // MARK: - Helpers

    func testTransliterationAndCrossScriptNameMatching() {
        XCTAssertEqual(HindiText.transliterate("\u{092A}\u{0935}\u{0928}"), "Pawan")
        XCTAssertEqual(HindiText.transliterate("\u{0928}\u{0947}\u{0939}\u{093E}"), "Neha")
        XCTAssertTrue(HindiText.namesMatch("\u{092A}\u{0935}\u{0928}", "Pawan"))
        XCTAssertTrue(HindiText.namesMatch("\u{0928}\u{0947}\u{0939}\u{093E}", "Neha"))
        XCTAssertTrue(HindiText.namesMatch("\u{0930}\u{093E}\u{0939}\u{0941}\u{0932}", "Rahul"))
        XCTAssertFalse(HindiText.namesMatch("\u{092A}\u{0935}\u{0928}", "Neha"))
        XCTAssertEqual(HindiText.matchParticipant("\u{0928}\u{0947}\u{0939}\u{093E}", participants: ["Pawan Kumar", "Neha Sharma"]), "Neha Sharma")
    }

    func testDeadlineTranslation() {
        XCTAssertEqual(MinutesComposer.englishDeadline("Friday \u{0924}\u{0915}"), "by Friday")
        XCTAssertEqual(MinutesComposer.englishDeadline("\u{0915}\u{0932} \u{0924}\u{0915}"), "by tomorrow")
        XCTAssertEqual(MinutesComposer.englishDeadline("by Friday"), "by Friday")
    }

    func testExcessSpeakerClustersMergeIntoTheNearestNeighbour() {
        let spans = [
            SpeakerSpan(speaker: "A", start: 0, end: 10), SpeakerSpan(speaker: "B", start: 10, end: 20),
            SpeakerSpan(speaker: "C", start: 20, end: 21), SpeakerSpan(speaker: "A", start: 21, end: 30)
        ]
        let merged = SpeakerClusterMerge.mergeExcess(spans, expected: 2)
        XCTAssertEqual(Set(merged.map(\.speaker)).count, 2)
        XCTAssertEqual(merged.count, spans.count)
        XCTAssertEqual(SpeakerClusterMerge.mergeExcess(spans, expected: nil).count, spans.count)
        XCTAssertEqual(Set(SpeakerClusterMerge.mergeExcess(spans, expected: 1).map(\.speaker)).count, 1)
    }

    func testSpeechVocabularyUsesNamesAndAgendaWordsOnly() {
        XCTAssertNil(SpeechVocabulary.make(participants: ["Speaker 1"], agenda: nil))
        let vocabulary = SpeechVocabulary.make(participants: ["Neha", "Pawan", "Speaker 2"], agenda: "Launch date\nVendor and budget")
        XCTAssertEqual(vocabulary?.names, ["Neha", "Pawan"])
        XCTAssertEqual(vocabulary?.terms, ["Launch", "date", "Vendor", "budget"])
        let prompt = vocabulary?.promptText(languageCode: nil) ?? ""
        XCTAssertTrue(prompt.contains("Neha, Pawan"))
        XCTAssertTrue(prompt.contains("Launch, date, Vendor, budget"))
        XCTAssertFalse((vocabulary?.promptText(languageCode: "en") ?? "").contains("\u{0928}\u{092E}\u{0938}\u{094D}\u{0924}\u{0947}"))
    }
}
