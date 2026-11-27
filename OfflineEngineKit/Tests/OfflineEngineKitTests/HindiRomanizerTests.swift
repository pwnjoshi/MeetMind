import XCTest
@testable import OfflineEngineKit

final class HindiRomanizerTests: XCTestCase {
    func testLatinTextIsReturnedUnchanged() {
        let text = "Please send the budget by Friday, 5 PM."
        XCTAssertEqual(HindiRomanizer.romanize(text), text)
        XCTAssertEqual(HindiRomanizer.romanize(""), "")
    }

    func testReadableHinglishForCommonSentence() {
        XCTAssertEqual(HindiRomanizer.romanize("कल तक भेज देना।"), "Kal tak bhej dena.")
    }

    func testOutputHasNoDevanagariAndNoDiacritics() {
        let out = HindiRomanizer.romanize("मुझे लगता है कि हमें कल तक प्रोजेक्ट भेजना चाहिए।")
        XCTAssertFalse(HindiText.containsDevanagari(out))
        for scalar in out.unicodeScalars { XCTAssertLessThan(scalar.value, 0x80, "non-ASCII scalar in \(out)") }
    }

    func testLatinWordsInsideHindiAreKept() {
        let out = HindiRomanizer.romanize("आज meeting है और Budget decide नहीं हुआ।")
        XCTAssertTrue(out.contains("meeting"))
        XCTAssertTrue(out.contains("Budget decide"))
        XCTAssertFalse(HindiText.containsDevanagari(out))
        XCTAssertTrue(out.hasSuffix("."))
    }

    func testInherentVowelIsDroppedAtWordEndAndBetweenVowels() {
        XCTAssertEqual(HindiRomanizer.romanize("किताब"), "Kitaab")
        XCTAssertEqual(HindiRomanizer.romanize("कमरा"), "Kamra")
        XCTAssertEqual(HindiRomanizer.romanize("पवन"), "Pavan")
        XCTAssertEqual(HindiRomanizer.romanize("ज्ञान"), "Gyaan")
    }

    func testNasalBeforeLabialUsesM() {
        XCTAssertEqual(HindiRomanizer.romanize("कंपनी"), "Kampani")
    }

    func testDevanagariDigitsBecomeAsciiAndSentenceCasingFollowsPunctuation() {
        XCTAssertEqual(HindiRomanizer.romanize("२० तारीख।"), "20 taarikh.")
        let two = HindiRomanizer.romanize("किताब। कमरा")
        XCTAssertEqual(two, "Kitaab. Kamra")
    }

    func testRomanizingTwiceChangesNothing() {
        let once = HindiRomanizer.romanize("कल तक भेज देना।")
        XCTAssertEqual(HindiRomanizer.romanize(once), once)
    }
}
