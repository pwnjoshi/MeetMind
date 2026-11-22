import XCTest
@testable import MeetMind

final class SignatureStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sig-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testSaveLoadRemove() throws {
        let store = SignatureStore(directory: directory)
        XCTAssertNil(store.load())
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        try store.save(pngData: data)
        XCTAssertTrue(store.hasSignature)
        XCTAssertEqual(store.load(), data)
        try store.remove()
        XCTAssertNil(store.load())
    }

    func testEraseAllRemovesFolder() throws {
        let store = SignatureStore(directory: directory)
        try store.save(pngData: Data([1, 2, 3]))
        try store.eraseAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testMinutesLanguageDefaultsToEnglish() {
        let defaults = UserDefaults(suiteName: "sig-test-\(UUID().uuidString)")!
        XCTAssertEqual(MinutesLanguagePreference.current(defaults: defaults), .english)
        MinutesLanguagePreference.set(.bilingual, defaults: defaults)
        XCTAssertEqual(MinutesLanguagePreference.current(defaults: defaults), .bilingual)
    }
}
