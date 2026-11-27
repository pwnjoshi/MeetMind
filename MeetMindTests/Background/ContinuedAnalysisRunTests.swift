import XCTest
@testable import MeetMind

/// Registering an identifier that Info.plist does not permit raises an exception in
/// BackgroundTasks, so the identifier must be chosen from the permitted patterns.
final class ContinuedAnalysisRunTests: XCTestCase {
    private let permitted = [
        "com.meetmind.app.offline-analysis",
        "com.meetmind.app.continued-analysis.*",
        "com.meetmind.app.JK2M3K5ACG.continued-analysis.*",
    ]

    func testPrefersTheRunningBundleIdentifierWhenPermitted() {
        let identifier = ContinuedAnalysisRun.continuedTaskIdentifier(
            bundleIdentifier: "com.meetmind.app.JK2M3K5ACG", permitted: permitted, suffix: "abc")
        XCTAssertEqual(identifier, "com.meetmind.app.JK2M3K5ACG.continued-analysis.abc")
    }

    func testFallsBackToTheProjectPrefixForAnUnlistedBundleIdentifier() {
        let identifier = ContinuedAnalysisRun.continuedTaskIdentifier(
            bundleIdentifier: "com.example.resigned", permitted: permitted, suffix: "abc")
        XCTAssertEqual(identifier, "com.meetmind.app.continued-analysis.abc")
    }

    func testReturnsNilWhenNoPatternPermitsContinuedTasks() {
        let identifier = ContinuedAnalysisRun.continuedTaskIdentifier(
            bundleIdentifier: "com.meetmind.app", permitted: ["com.meetmind.app.offline-analysis"], suffix: "abc")
        XCTAssertNil(identifier)
    }

    func testShippedInfoPlistPermitsContinuedTasks() throws {
        let bundle = Bundle(for: ContinuedAnalysisRun.self)
        let identifiers = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])
        XCTAssertNotNil(ContinuedAnalysisRun.continuedTaskIdentifier(
            bundleIdentifier: "com.meetmind.app", permitted: identifiers, suffix: "abc"))
    }
}
