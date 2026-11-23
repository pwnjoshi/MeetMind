//
//  LiveCaptionLanguageArbiterTests.swift
//  MeetMindTests
//
//  Code-switching live captions: which recognizer (English or Hindi) heard a phrase correctly,
//  the hysteresis that keeps the language stable, and the hub that joins both recognizers.
//

import XCTest
import Foundation
import AVFoundation
@testable import MeetMind

final class LiveCaptionLanguageArbiterTests: XCTestCase {

    private func words(_ text: String, confidence: Float, start: TimeInterval = 0, end: TimeInterval = 3) -> [CaptionWord] {
        CaptionWord.words(from: text, start: start, end: end, confidence: confidence)
    }

    // MARK: - Arbiter

    func test_englishSentenceShowsEnglish() {
        var arbiter = LiveCaptionLanguageArbiter()
        let english = words("Let's review the project deadline with the team", confidence: 0.9)
        let hindi = words("लेट्स रिव्यू द प्रोजेक्ट डेडलाइन विथ द टीम", confidence: 0.6)
        let decision = arbiter.decide(english: english, hindi: hindi)
        XCTAssertEqual(decision.language, .english)
        XCTAssertGreaterThan(decision.evidence.englishScore, decision.evidence.hindiScore)
    }

    func test_hindiSentenceShowsHindi() {
        var arbiter = LiveCaptionLanguageArbiter()
        // The English recognizer hears Hindi as unsure English-looking words.
        let english = words("may be cult some her main call", confidence: 0.3)
        let hindi = words("मैं कल सुबह मीटिंग में जाऊंगा", confidence: 0.85)
        let decision = arbiter.decide(english: english, hindi: hindi)
        XCTAssertEqual(decision.language, .hindi)
        XCTAssertGreaterThan(decision.evidence.hindiFunctionWordRatio, 0)
    }

    func test_hinglishSentenceWithHindiGrammarShowsHindi() {
        var arbiter = LiveCaptionLanguageArbiter()
        let english = words("call key meeting main project deadline discuss car and gay", confidence: 0.5)
        let hindi = words("कल की मीटिंग में प्रोजेक्ट डेडलाइन डिस्कस करेंगे", confidence: 0.8)
        let decision = arbiter.decide(english: english, hindi: hindi)
        XCTAssertEqual(decision.language, .hindi)
        XCTAssertGreaterThan(decision.evidence.hindiFunctionWordRatio, 0.2)
    }

    func test_devanagariSpelledEnglishShowsEnglish() {
        var arbiter = LiveCaptionLanguageArbiter()
        let english = words("meeting project deadline", confidence: 0.9)
        let hindi = words("मीटिंग प्रोजेक्ट डेडलाइन", confidence: 0.8)
        let decision = arbiter.decide(english: english, hindi: hindi)
        XCTAssertEqual(decision.language, .english)
        XCTAssertGreaterThanOrEqual(decision.evidence.transliteratedRatio, 0.99)
        XCTAssertLessThanOrEqual(decision.evidence.hindiScore, 0.2)
    }

    func test_emptyCandidateLosesToTheOtherOne() {
        var arbiter = LiveCaptionLanguageArbiter()
        XCTAssertEqual(arbiter.decide(english: [], hindi: words("मैं यहाँ हूँ", confidence: 0.7)).language, .hindi)
        XCTAssertEqual(arbiter.decide(english: words("I am here today", confidence: 0.7), hindi: []).language, .english)
    }

    func test_decisionRemembersAndReportsSwitches() {
        var arbiter = LiveCaptionLanguageArbiter()
        let englishPhrase = words("Let's review the project deadline with the team", confidence: 0.9)
        let englishInDevanagari = words("लेट्स रिव्यू द प्रोजेक्ट डेडलाइन विथ द टीम", confidence: 0.6)
        let first = arbiter.decide(english: englishPhrase, hindi: englishInDevanagari)
        XCTAssertFalse(first.switched)
        XCTAssertEqual(arbiter.current, .english)

        let hindiPhrase = words("मैं कल सुबह मीटिंग में जाऊंगा", confidence: 0.85)
        let garbled = words("may be cult some her main call", confidence: 0.3)
        let second = arbiter.decide(english: garbled, hindi: hindiPhrase)
        XCTAssertTrue(second.switched)
        XCTAssertEqual(arbiter.current, .hindi)
    }

    // MARK: - Hysteresis

    func test_hysteresisKeepsLanguageOnSmallMargins() {
        let config = LiveCaptionLanguageArbiter.Configuration()
        // Short phrase, Hindi ahead by only 0.1: stay English.
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.1, phraseWords: 3, current: .english, configuration: config), .english)
        // The same margin on a long phrase is still too small.
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.1, phraseWords: 12, current: .english, configuration: config), .english)
        // A clear win switches at any length.
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.5, phraseWords: 2, current: .english, configuration: config), .hindi)
        // A medium margin switches only when the phrase is long.
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.2, phraseWords: 3, current: .english, configuration: config), .english)
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.2, phraseWords: 8, current: .english, configuration: config), .hindi)
        // Symmetric for Hindi to English.
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: 0.15, phraseWords: 3, current: .hindi, configuration: config), .hindi)
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: 0.4, phraseWords: 3, current: .hindi, configuration: config), .english)
    }

    func test_firstDecisionFollowsTheMarginWithoutHysteresis() {
        let config = LiveCaptionLanguageArbiter.Configuration()
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: -0.01, phraseWords: 1, current: nil, configuration: config), .hindi)
        XCTAssertEqual(LiveCaptionLanguageArbiter.resolve(margin: 0, phraseWords: 1, current: nil, configuration: config), .english)
    }

    func test_previewDoesNotChangeTheRememberedLanguage() {
        var arbiter = LiveCaptionLanguageArbiter()
        _ = arbiter.decide(english: words("Let's review the project deadline with the team", confidence: 0.9),
                           hindi: words("लेट्स रिव्यू द प्रोजेक्ट डेडलाइन विथ द टीम", confidence: 0.6))
        let shown = arbiter.preview(english: words("may be cult some her main call", confidence: 0.3),
                                    hindi: words("मैं कल सुबह मीटिंग में जाऊंगा", confidence: 0.85))
        XCTAssertEqual(shown, .hindi)
        XCTAssertEqual(arbiter.current, .english)
    }

    // MARK: - Lexicon

    func test_lexiconHasEnoughLoanwordsAndFunctionWords() {
        XCTAssertGreaterThanOrEqual(LiveCaptionLexicon.englishLoanwords.count, 150)
        for word in ["है", "हैं", "का", "की", "के", "को", "में", "नहीं", "और", "तो", "भी", "क्या", "हम", "आप", "मैं", "ये", "वो", "कर", "था", "थी", "गया", "रहा"] {
            XCTAssertTrue(LiveCaptionLexicon.hindiFunctionWords.contains(word), word)
        }
        XCTAssertTrue(LiveCaptionLexicon.englishLoanwords.contains("मीटिंग"))
        XCTAssertTrue(LiveCaptionLexicon.englishLoanwords.contains("प्रोजेक्ट"))
        XCTAssertTrue(LiveCaptionLexicon.englishLoanwords.contains("डेडलाइन"))
    }

    func test_skeletonsMatchSpellingsOfTheSameEnglishWord() {
        XCTAssertEqual(LiveCaptionLexicon.devanagariSkeleton("प्रोजेक्ट"), LiveCaptionLexicon.englishSkeleton("project"))
        XCTAssertEqual(LiveCaptionLexicon.devanagariSkeleton("मीटिंग"), LiveCaptionLexicon.englishSkeleton("meeting"))
        XCTAssertEqual(LiveCaptionLexicon.devanagariSkeleton("डेडलाइन"), LiveCaptionLexicon.englishSkeleton("deadline"))
    }

    func test_unlistedLoanwordIsRecognizedFromTheEnglishCandidate() {
        XCTAssertTrue(LiveCaptionLexicon.isTransliteratedEnglish("स्प्रिंट", englishTokens: ["sprint"]))
        XCTAssertFalse(LiveCaptionLexicon.isTransliteratedEnglish("स्प्रिंट", englishTokens: []))
        XCTAssertFalse(LiveCaptionLexicon.isTransliteratedEnglish("सुबह", englishTokens: ["sprint", "review"]))
    }

    // MARK: - Locale plan

    func test_onlyHinglishAndAutomaticUseTwoRecognizers() throws {
        let hinglish = try XCTUnwrap(LiveCaptionLocalePlanner.dualPlan(language: .hinglish, preferredLocaleIdentifier: "hi-IN"))
        XCTAssertEqual(hinglish.english.candidates, ["en-IN", "en-US"])
        XCTAssertEqual(hinglish.hindi.candidates, ["hi-IN"])
        XCTAssertNotNil(LiveCaptionLocalePlanner.dualPlan(language: .automatic, preferredLocaleIdentifier: nil))
        XCTAssertNil(LiveCaptionLocalePlanner.dualPlan(language: .english, preferredLocaleIdentifier: nil))
        XCTAssertNil(LiveCaptionLocalePlanner.dualPlan(language: .hindi, preferredLocaleIdentifier: nil))
    }

    // MARK: - Router fan-out

    func test_routerDeliversEveryBufferToEverySlot() async throws {
        let router = CaptionAudioRouter()
        let first = router.attach(slot: 0)
        let second = router.attach(slot: 1)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        router.send(buffer)
        router.send(buffer)
        router.finish()

        var firstCount = 0
        for await _ in first.stream { firstCount += 1 }
        var secondCount = 0
        for await _ in second.stream { secondCount += 1 }
        XCTAssertEqual(firstCount, 2)
        XCTAssertEqual(secondCount, 2)
        XCTAssertEqual(router.deliveredSeconds, 0.2, accuracy: 0.001)
    }

    // MARK: - Hub

    private final class RecordingSink: CaptionResultSink, @unchecked Sendable {
        private let lock = NSLock()
        private var storedCommits: [[CaptionWord]] = []

        var commits: [[CaptionWord]] {
            lock.lock()
            defer { lock.unlock() }
            return storedCommits
        }

        func setAutoCommit(_ policy: LiveCaptionStitcher.AutoCommitPolicy?) {}
        func updateOpen(_ words: [CaptionWord]) {}
        func commit(_ words: [CaptionWord]) {
            lock.lock()
            storedCommits.append(words)
            lock.unlock()
        }
        func notice(_ message: String) {}
    }

    private func text(_ words: [CaptionWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    func test_hubCommitsOnlyTheWinningLanguageAndNoDuplicates() {
        let sink = RecordingSink()
        let hub = CaptionLanguageHub(downstream: sink)
        let english = hub.sink(for: .english)
        let hindi = hub.sink(for: .hindi)

        english.commit(words("Let's review the project deadline with the team", confidence: 0.9))
        XCTAssertTrue(sink.commits.isEmpty, "waits for the other recognizer")
        hindi.commit(words("लेट्स रिव्यू द प्रोजेक्ट डेडलाइन विथ द टीम", confidence: 0.6))

        XCTAssertEqual(sink.commits.count, 1)
        XCTAssertEqual(text(sink.commits[0]), "Let's review the project deadline with the team")

        // A recognizer restart repeating the same phrase adds nothing.
        english.commit(words("Let's review the project deadline with the team", confidence: 0.9))
        hindi.commit(words("लेट्स रिव्यू द प्रोजेक्ट डेडलाइन विथ द टीम", confidence: 0.6))
        XCTAssertEqual(sink.commits.count, 1)
    }

    func test_hubShowsHindiWhenHindiWasSpoken() {
        let sink = RecordingSink()
        let hub = CaptionLanguageHub(downstream: sink)
        let english = hub.sink(for: .english)
        let hindi = hub.sink(for: .hindi)

        hindi.commit(words("मैं कल सुबह मीटिंग में जाऊंगा", confidence: 0.85))
        english.commit(words("may be cult some her main call", confidence: 0.3))

        XCTAssertEqual(sink.commits.count, 1)
        XCTAssertEqual(text(sink.commits[0]), "मैं कल सुबह मीटिंग में जाऊंगा")
    }

    func test_hubKeepsTheFirstRecognizerWhenTheSecondIsDropped() {
        let sink = RecordingSink()
        let hub = CaptionLanguageHub(downstream: sink)
        let english = hub.sink(for: .english)
        let hindi = hub.sink(for: .hindi)

        hindi.end()
        english.commit(words("Let's review the project deadline with the team", confidence: 0.9))

        XCTAssertEqual(sink.commits.count, 1)
        XCTAssertEqual(text(sink.commits[0]), "Let's review the project deadline with the team")
    }

    func test_hubFinishJudgesPhrasesStillWaiting() {
        let sink = RecordingSink()
        let hub = CaptionLanguageHub(downstream: sink)
        let hindi = hub.sink(for: .hindi)

        hindi.commit(words("मैं कल सुबह मीटिंग में जाऊंगा", confidence: 0.85))
        XCTAssertTrue(sink.commits.isEmpty)
        hub.finish()
        XCTAssertEqual(sink.commits.count, 1)
    }
}
