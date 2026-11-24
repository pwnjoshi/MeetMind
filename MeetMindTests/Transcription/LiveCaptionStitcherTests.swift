//
//  LiveCaptionStitcherTests.swift
//  MeetMindTests
//
//  Pure-logic tests for live captions: locale choice from the recording language,
//  partial/final merging, and duplicate removal across recognizer restarts.
//

import XCTest
import Foundation
import AVFoundation
@testable import MeetMind

final class LiveCaptionStitcherTests: XCTestCase {

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> CaptionWord {
        CaptionWord(text: text, start: start, end: end)
    }

    // MARK: - Locale planning

    func test_hindiAndHinglishAlwaysUseHindiLocale() {
        for language in [LiveCaptionLanguage.hindi, .hinglish] {
            let plan = LiveCaptionLocalePlanner.plan(language: language, preferredLocaleIdentifier: "en-US")
            XCTAssertEqual(plan.candidates, ["hi-IN"])
            XCTAssertEqual(plan.languageName, "Hindi")
        }
    }

    func test_englishPrefersIndianEnglishThenUS() {
        let plan = LiveCaptionLocalePlanner.plan(language: .english, preferredLocaleIdentifier: "hi-IN")
        XCTAssertEqual(plan.candidates, ["en-IN", "en-US"])
        XCTAssertEqual(plan.languageName, "English")
    }

    func test_englishKeepsOtherEnglishPreferenceFirst() {
        let plan = LiveCaptionLocalePlanner.plan(language: .english, preferredLocaleIdentifier: "en_GB")
        XCTAssertEqual(plan.candidates, ["en-GB", "en-IN", "en-US"])
    }

    func test_automaticFollowsPreviewLocaleOrDefaultsToHindi() {
        XCTAssertEqual(LiveCaptionLocalePlanner.plan(language: .automatic, preferredLocaleIdentifier: "hi_IN").candidates, ["hi-IN"])
        XCTAssertEqual(LiveCaptionLocalePlanner.plan(language: .automatic, preferredLocaleIdentifier: "en-US").candidates, ["en-US"])
        XCTAssertEqual(LiveCaptionLocalePlanner.plan(language: .automatic, preferredLocaleIdentifier: nil).candidates, ["hi-IN"])
        XCTAssertEqual(LiveCaptionLocalePlanner.plan(language: .automatic, preferredLocaleIdentifier: "  ").candidates, ["hi-IN"])
    }

    func test_storedLanguageReadsSettingsKeyAndDefaultsToHinglish() throws {
        let suite = "LiveCaptionStitcherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(LiveCaptionLanguage.stored(in: defaults), .hinglish)
        defaults.set("english", forKey: LiveCaptionLanguage.defaultsKey)
        XCTAssertEqual(LiveCaptionLanguage.stored(in: defaults), .english)
        defaults.set("not-a-language", forKey: LiveCaptionLanguage.defaultsKey)
        XCTAssertEqual(LiveCaptionLanguage.stored(in: defaults), .hinglish)
    }

    func test_noticesAreTruthfulAboutOnDeviceLimits() {
        let message = LiveCaptionNotice.unavailable(languageName: "Hindi")
        XCTAssertEqual(message, "Live captions for Hindi aren't available on this iPhone; the full transcript is created after recording.")
        XCTAssertTrue(LiveCaptionNotice.downloading(languageName: "Hindi").contains("Downloading Hindi speech model"))
    }

    func test_contextualStringsAreDeduplicatedTrimmedAndCapped() {
        let strings = LiveCaptionContext.contextualStrings(
            participants: ["Priya Sharma", " priya sharma ", "Rohan", "x"],
            agenda: ["Q4 Roadmap review", ""]
        )
        XCTAssertTrue(strings.contains("Priya Sharma"))
        XCTAssertTrue(strings.contains("Priya"))
        XCTAssertTrue(strings.contains("Rohan"))
        XCTAssertTrue(strings.contains("Roadmap"))
        XCTAssertFalse(strings.contains("x"))
        XCTAssertEqual(strings.filter { $0.lowercased() == "priya sharma" }.count, 1)

        let many = (0..<300).map { "Person\($0)" }
        XCTAssertEqual(LiveCaptionContext.contextualStrings(participants: many, agenda: []).count, LiveCaptionContext.maximumStrings)
    }

    // MARK: - Word helpers

    func test_wordsFromPhraseSpreadTimeAcrossWords() {
        let words = CaptionWord.words(from: "ab cdef", start: 10, end: 16)
        XCTAssertEqual(words.map(\.text), ["ab", "cdef"])
        XCTAssertEqual(words[0].start, 10, accuracy: 0.001)
        XCTAssertEqual(words[0].end, 12, accuracy: 0.001)
        XCTAssertEqual(words[1].start, 12, accuracy: 0.001)
        XCTAssertEqual(words[1].end, 16, accuracy: 0.001)
        XCTAssertTrue(CaptionWord.words(from: "   ", start: 0, end: 1).isEmpty)
    }

    // MARK: - Partial and final merging

    func test_partialChunksReplaceEachOtherAndFinalCommits() throws {
        var stitcher = LiveCaptionStitcher()

        let first = stitcher.updateOpen([word("hello", 0, 0.4)])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].text, "hello")
        XCTAssertFalse(first[0].isFinal)

        let second = stitcher.updateOpen([word("hello", 0, 0.4), word("world", 0.4, 0.9)])
        XCTAssertEqual(second.map(\.text), ["hello world"])
        XCTAssertEqual(stitcher.committedWordCount, 0)

        let final = try XCTUnwrap(stitcher.commit([word("Hello", 0, 0.4), word("world.", 0.4, 0.9)]))
        XCTAssertTrue(final.isFinal)
        XCTAssertEqual(final.text, "Hello world.")
        XCTAssertEqual(final.segments.count, 2)
        XCTAssertEqual(final.segments[1].startTime, 0.4, accuracy: 0.001)
        XCTAssertEqual(final.segments[1].duration, 0.5, accuracy: 0.001)
        XCTAssertEqual(stitcher.committedWordCount, 2)
        XCTAssertTrue(stitcher.openWords.isEmpty)
    }

    func test_identicalFinalIsNotEmittedTwice() {
        var stitcher = LiveCaptionStitcher()
        XCTAssertNotNil(stitcher.commit([word("good", 0, 0.3), word("morning", 0.3, 0.8)]))
        XCTAssertNil(stitcher.commit([word("good", 0, 0.3), word("morning", 0.3, 0.8)]))
    }

    func test_blankWordsAreIgnored() {
        var stitcher = LiveCaptionStitcher()
        XCTAssertTrue(stitcher.updateOpen([word("  ", 0, 0.1)]).isEmpty)
        XCTAssertNil(stitcher.commit([word("", 0, 0.1)]))
    }

    func test_clearOpenPreservesCommittedFrontier() {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("fixed", 0, 0.5)])
        _ = stitcher.updateOpen([word("mutable", 0.5, 1.0)])
        stitcher.clearOpen()

        XCTAssertTrue(stitcher.openWords.isEmpty)
        XCTAssertEqual(stitcher.committedEnd, 0.5, accuracy: 0.001)
        XCTAssertEqual(stitcher.committedWordCount, 1)
    }

    @MainActor
    func test_emptyNonFinalChunkClearsViewModelInterimText() {
        let viewModel = LiveRecordingViewModel(updatesFromRecordingClock: false)
        viewModel.receiveLiveTranscriptChunk(LiveTranscriptChunk(text: "mutable phrase", isFinal: false))
        XCTAssertEqual(viewModel.interimTranscriptText, "mutable phrase")

        viewModel.receiveLiveTranscriptChunk(LiveTranscriptChunk(text: "", isFinal: false, segments: []))
        XCTAssertEqual(viewModel.interimTranscriptText, "")
    }

    func test_captionAssemblerEmitsExplicitEmptyInterimAfterCommit() {
        final class ChunkRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: [LiveTranscriptChunk] = []
            func append(_ chunk: LiveTranscriptChunk) {
                lock.lock()
                stored.append(chunk)
                lock.unlock()
            }
            var chunks: [LiveTranscriptChunk] {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
        }

        let recorder = ChunkRecorder()
        let assembler = CaptionAssembler { recorder.append($0) }
        assembler.updateOpen([word("mutable", 0, 0.5)])
        assembler.commit([word("final", 0, 0.5)])

        XCTAssertEqual(recorder.chunks.map(\.isFinal), [false, true, false])
        XCTAssertEqual(recorder.chunks.last?.text, "")
        XCTAssertTrue(recorder.chunks.last?.segments.isEmpty == true)
    }

    // MARK: - Restart de-duplication

    func test_restartedRequestDoesNotRepeatWordsHeardTwice() throws {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("hello", 0, 0.5), word("world", 0.5, 1.0), word("how", 1.0, 1.3)])

        // The next request replays the last two seconds, so it hears the same words again.
        let next = try XCTUnwrap(stitcher.commit([
            word("world", 0.5, 1.0), word("how", 1.0, 1.3), word("are", 1.3, 1.6), word("you", 1.6, 2.0)
        ]))
        XCTAssertEqual(next.text, "are you")
        XCTAssertEqual(next.segments.first?.startTime ?? -1, 1.3, accuracy: 0.001)
    }

    func test_boundaryWordWithShiftedTimestampIsTrimmedByText() throws {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("hello", 0, 0.5), word("world", 0.5, 1.0)])

        // The second recognizer aligned "world" 0.4 s later, so the time check alone keeps it.
        let next = try XCTUnwrap(stitcher.commit([word("world", 0.9, 1.2), word("again", 1.2, 1.6)]))
        XCTAssertEqual(next.text, "again")
    }

    func test_genuineRepeatedWordAfterCommittedAudioIsKept() throws {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("no", 0.5, 1.0)])
        let next = try XCTUnwrap(stitcher.commit([word("no", 1.1, 1.4), word("way", 1.4, 1.8)]))
        XCTAssertEqual(next.text, "no way")
    }

    func test_punctuationAndCaseDoNotDefeatHindiAndEnglishDeduplication() throws {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("कैसे", 0, 0.5), word("हैं।", 0.5, 1.0)])
        let hindi = try XCTUnwrap(stitcher.commit([word("हैं", 0.9, 1.2), word("आप", 1.2, 1.5)]))
        XCTAssertEqual(hindi.text, "आप")

        var english = LiveCaptionStitcher()
        _ = english.commit([word("Thanks,", 0, 0.5), word("everyone.", 0.5, 1.0)])
        let tail = try XCTUnwrap(english.commit([word("EVERYONE", 0.9, 1.2), word("let's", 1.2, 1.5)]))
        XCTAssertEqual(tail.text, "let's")
    }

    func test_openUpdateAfterRestartOnlyShowsNewTail() {
        var stitcher = LiveCaptionStitcher()
        _ = stitcher.commit([word("one", 0, 0.4), word("two", 0.4, 0.8)])
        let chunks = stitcher.updateOpen([word("two", 0.4, 0.8), word("three", 0.8, 1.2)])
        XCTAssertEqual(chunks.map(\.text), ["three"])
        XCTAssertEqual(chunks.map(\.isFinal), [false])
    }

    // MARK: - Automatic phrase commits

    func test_pauseClosesPhraseAndKeepsTailOpen() {
        var stitcher = LiveCaptionStitcher(autoCommit: .captions)
        let chunks = stitcher.updateOpen([
            word("one", 0, 0.3), word("two", 0.3, 0.6), word("three", 0.6, 0.9),
            word("four", 2.5, 2.8), word("five", 2.8, 3.1)
        ])
        XCTAssertEqual(chunks.map(\.text), ["one two three", "four five"])
        XCTAssertEqual(chunks.map(\.isFinal), [true, false])

        // A later hypothesis repeats the closed phrase; only the new tail appears.
        let later = stitcher.updateOpen([
            word("one", 0, 0.3), word("two", 0.3, 0.6), word("three", 0.6, 0.9),
            word("four", 2.5, 2.8), word("five", 2.8, 3.1), word("six", 3.1, 3.4)
        ])
        XCTAssertEqual(later.map(\.text), ["four five six"])
        XCTAssertEqual(later.map(\.isFinal), [false])
    }

    func test_shortPauseInsideShortPhraseDoesNotSplit() {
        var stitcher = LiveCaptionStitcher(autoCommit: .captions)
        let chunks = stitcher.updateOpen([word("um", 0, 0.2), word("so", 1.5, 1.7), word("yes", 1.7, 2.0)])
        XCTAssertEqual(chunks.map(\.isFinal), [false])
        XCTAssertEqual(chunks.first?.text, "um so yes")
    }

    func test_veryLongPartialIsSplitIntoStablePhrase() {
        var stitcher = LiveCaptionStitcher(autoCommit: .captions)
        let words = (0..<40).map { word("w\($0)", Double($0) * 0.3, Double($0) * 0.3 + 0.25) }
        let chunks = stitcher.updateOpen(words)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].isFinal)
        XCTAssertEqual(chunks[0].segments.count, 32)
        XCTAssertFalse(chunks[1].isFinal)
        XCTAssertEqual(chunks[1].segments.count, 8)
    }

    func test_disabledAutoCommitNeverSplitsPartials() {
        var stitcher = LiveCaptionStitcher()
        let chunks = stitcher.updateOpen([
            word("one", 0, 0.3), word("two", 0.3, 0.6), word("three", 0.6, 0.9), word("four", 5, 5.3)
        ])
        XCTAssertEqual(chunks.map(\.isFinal), [false])
        XCTAssertEqual(chunks.first?.segments.count, 4)
    }

    // MARK: - Audio router timeline

    func test_routerReportsRecordingRelativeOffsets() throws {
        let router = CaptionAudioRouter()
        let first = router.attach()
        XCTAssertEqual(first.startOffset, 0, accuracy: 0.0001)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        for _ in 0..<10 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
            buffer.frameLength = 4_410
            router.send(buffer)
        }
        XCTAssertEqual(router.deliveredSeconds, 1.0, accuracy: 0.001)

        let second = router.attach()
        XCTAssertEqual(second.startOffset, 1.0, accuracy: 0.001)
        router.finish()
    }
}
