import XCTest
@testable import OfflineEngineKit

final class SpeechLanguageResolverTests: XCTestCase {
    private func evidence(_ code: String?, _ confidence: Float?, _ seconds: Double) -> RegionLanguageEvidence {
        RegionLanguageEvidence(detected: code, confidence: confidence, duration: seconds)
    }

    func testCanonicalFoldsHindiFamilyAndIgnoresEmpty() {
        XCTAssertEqual(SpeechLanguageResolver.canonical("ur"), "hi")
        XCTAssertEqual(SpeechLanguageResolver.canonical(" PA "), "hi")
        XCTAssertEqual(SpeechLanguageResolver.canonical("mr"), "hi")
        XCTAssertEqual(SpeechLanguageResolver.canonical("ne"), "hi")
        XCTAssertEqual(SpeechLanguageResolver.canonical("en"), "en")
        XCTAssertEqual(SpeechLanguageResolver.canonical("FR"), "fr")
        XCTAssertNil(SpeechLanguageResolver.canonical(nil))
        XCTAssertNil(SpeechLanguageResolver.canonical("  "))
    }

    func testConfidentRegionsKeepTheirOwnLanguage() {
        let result = SpeechLanguageResolver.resolve([
            evidence("en", 0.9, 3), evidence("hi", 0.8, 3), evidence("en", 0.7, 3)])
        XCTAssertEqual(result, ["en", "hi", "en"])
    }

    func testUncertainShortRegionInheritsPreviousLanguage() {
        let result = SpeechLanguageResolver.resolve([
            evidence("hi", 0.9, 5), evidence("en", 0.3, 1.5), evidence("hi", 0.9, 5)])
        XCTAssertEqual(result, ["hi", "hi", "hi"])
    }

    func testUncertainLongRegionIsNotOverridden() {
        let result = SpeechLanguageResolver.resolve([
            evidence("hi", 0.9, 5), evidence("en", 0.3, 8), evidence("hi", 0.9, 5)])
        XCTAssertEqual(result, ["hi", "en", "hi"])
    }

    func testFirstUncertainRegionTakesNextFirmLanguageBeforeOldHint() {
        let result = SpeechLanguageResolver.resolve([evidence("en", 0.3, 1.0), evidence("hi", 0.9, 5)], previous: "en")
        XCTAssertEqual(result, ["hi", "hi"])
    }

    func testPreviousWindowIsOnlyAHint() {
        XCTAssertEqual(SpeechLanguageResolver.resolve([evidence("en", 0.3, 1.0)], previous: "hi"), ["hi"])
        // A firm detection is never overridden by the hint.
        XCTAssertEqual(SpeechLanguageResolver.resolve([evidence("en", 0.9, 3)], previous: "hi"), ["en"])
    }

    func testNoEvidenceFallsBackToHindiAndWeakDetectionBeatsFallback() {
        XCTAssertEqual(SpeechLanguageResolver.resolve([evidence(nil, nil, 2)]), ["hi"])
        XCTAssertEqual(SpeechLanguageResolver.resolve([evidence("en", 0.2, 1)]), ["en"])
    }

    func testUrduAndOtherHindiFamilyBecomeHindi() {
        let result = SpeechLanguageResolver.resolve([evidence("ur", 0.9, 4), evidence("pa", 0.7, 3)])
        XCTAssertEqual(result, ["hi", "hi"])
    }

    func testForeignLanguageNeedsConfidenceAndLength() {
        XCTAssertEqual(SpeechLanguageResolver.resolve([evidence("fr", 0.9, 6)]), ["fr"])
        let shortForeign = SpeechLanguageResolver.resolve([evidence("hi", 0.9, 5), evidence("ms", 0.9, 1.5)])
        XCTAssertEqual(shortForeign, ["hi", "hi"])
        let unsureForeign = SpeechLanguageResolver.resolve([evidence("en", 0.9, 5), evidence("nn", 0.3, 8)])
        XCTAssertEqual(unsureForeign, ["en", "en"])
    }

    func testEmptyInput() {
        XCTAssertTrue(SpeechLanguageResolver.resolve([]).isEmpty)
    }

    func testRedecodeOnlyWhenLanguageDiffers() {
        XCTAssertFalse(SpeechLanguageResolver.needsRedecode(used: "hi", chosen: "hi"))
        XCTAssertFalse(SpeechLanguageResolver.needsRedecode(used: "EN", chosen: "en"))
        XCTAssertTrue(SpeechLanguageResolver.needsRedecode(used: "ur", chosen: "hi"))
        XCTAssertTrue(SpeechLanguageResolver.needsRedecode(used: "en", chosen: "hi"))
        XCTAssertTrue(SpeechLanguageResolver.needsRedecode(used: nil, chosen: "en"))
    }

    func testConfidenceIsLengthWeightedMeanTokenProbability() {
        XCTAssertNil(SpeechLanguageResolver.confidence(avgLogprobs: []))
        let certain = SpeechLanguageResolver.confidence(avgLogprobs: [(0, 2)])
        XCTAssertEqual(certain ?? -1, 1, accuracy: 0.0001)
        let half = SpeechLanguageResolver.confidence(avgLogprobs: [(-0.6931471805599453, 3)])
        XCTAssertEqual(half ?? -1, 0.5, accuracy: 0.001)
        let mixed = SpeechLanguageResolver.confidence(avgLogprobs: [(0, 1), (-1, 3)])
        XCTAssertEqual(mixed ?? -1, Float(exp(-0.75)), accuracy: 0.001)
    }

    func testScriptContradiction() {
        XCTAssertFalse(SpeechLanguageResolver.scriptContradicts(language: "en", text: "Send it by Friday"))
        XCTAssertTrue(SpeechLanguageResolver.scriptContradicts(language: "en", text: "कल तक भेज देना"))
        XCTAssertFalse(SpeechLanguageResolver.scriptContradicts(language: "hi", text: "कल तक भेज देना"))
        XCTAssertFalse(SpeechLanguageResolver.scriptContradicts(language: "hi", text: "Send it by Friday"))
        XCTAssertTrue(SpeechLanguageResolver.scriptContradicts(language: "hi", text: "مرحبا بكم جميعا"))
        XCTAssertFalse(SpeechLanguageResolver.scriptContradicts(language: "en", text: "ok"))
        XCTAssertEqual(SpeechLanguageResolver.alternate(of: "en"), "hi")
        XCTAssertEqual(SpeechLanguageResolver.alternate(of: "hi"), "en")
    }

    func testStatsAccumulateAndDescribeWithoutContent() {
        var total = SpeechDecodeStats()
        var run = SpeechDecodeStats()
        run.runs = 1
        run.regions = 4
        run.detections = 4
        run.redecodes = 1
        run.speechSeconds = 12.34
        total.add(run)
        total.add(run)
        XCTAssertEqual(total.regions, 8)
        XCTAssertEqual(total.redecodes, 2)
        XCTAssertTrue(total.description.contains("regions=8"))
        XCTAssertTrue(total.description.contains("redecodes=2"))
    }
}
