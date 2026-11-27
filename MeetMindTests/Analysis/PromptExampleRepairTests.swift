import XCTest
import SwiftData
import OfflineEngineKit
@testable import MeetMind

/// The launch-time repair that removes copied prompt examples ("The Pune vendor is engaged")
/// from saved minutes. It once crashed the app on every launch, so it must update stored text
/// in place, run only once, and leave review state alone.
@MainActor
final class PromptExampleRepairTests: XCTestCase {
    private let flag = "MeetMind.promptExampleRepair.v1"
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: flag)
        container = try ModelContainer(for: ModelContainerFactory.schema,
                                       configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: flag)
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func leakedMeeting() throws -> Meeting {
        let meeting = Meeting(title: "Design review", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                              scheduledStartTime: nil, duration: 60, status: .completed, isFavorite: false)
        context.insert(meeting)
        let turn = AnalysisTurn(id: "t1", text: "We have not decided to change the design.", start: 0, end: 3, speaker: nil)
        let leaked = SupportedPoint(text: "The Pune vendor is engaged (lower price).",
                                    evidence: [SourceEvidence(turnID: "t1", quote: "We have not decided")])
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "fixture", stage: .completed, turns: [turn],
            speakers: [], analysis: [LocalAnalysisResult(discussion: [], decisions: [leaked], tasks: [])],
            analyzedChunks: 1)
        meeting.offlineAnalysisData = try JSONEncoder().encode(checkpoint)
        let summary = Summary(executiveSummary: "The Pune vendor is engaged.", keyPoints: [],
                              keyDecisions: ["The Pune vendor is engaged (lower price)."], meeting: meeting)
        meeting.summary = summary
        meeting.minutesNeedFinalization = false
        try context.save()
        return meeting
    }

    func testRepairRemovesCopiedExampleInPlaceAndKeepsReviewState() throws {
        let meeting = try leakedMeeting()
        let summaryID = try XCTUnwrap(meeting.summary?.id)

        AnalysisCoordinator(context: context).repairPromptExampleLeaks()

        XCTAssertEqual(meeting.summary?.id, summaryID, "The existing summary is updated, not replaced")
        XCTAssertFalse(meeting.summary?.keyDecisions.contains { $0.contains("Pune") } ?? true)
        XCTAssertFalse(meeting.summary?.executiveSummary.contains("Pune") ?? true)
        XCTAssertEqual(meeting.minutesNeedFinalization, false, "A repair never reopens reviewed minutes")
        let data = try XCTUnwrap(meeting.offlineAnalysisData)
        let saved = try JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data)
        XCTAssertTrue(saved.analysis.allSatisfy { $0.decisions.isEmpty })
    }

    func testRepairRunsOnlyOnceEvenWhenTheFirstRunStops() throws {
        _ = try leakedMeeting()
        XCTAssertTrue(AnalysisCoordinator.needsPromptExampleRepair)
        AnalysisCoordinator(context: context).repairPromptExampleLeaks()
        XCTAssertFalse(AnalysisCoordinator.needsPromptExampleRepair)
        // A second launch does nothing.
        AnalysisCoordinator(context: context).repairPromptExampleLeaks()
        XCTAssertFalse(AnalysisCoordinator.needsPromptExampleRepair)
    }
}
